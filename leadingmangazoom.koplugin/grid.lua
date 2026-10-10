--[[--
Grid zoom module for LeadingMangaZoom plugin.
@module leadingmangazoom.grid
]]--

local Device = require("device")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local Screen = Device.screen

local Grid = {
    enabled = true,
    page_zoom_enabled = true,
    rtl_enabled = false,
    navigation_enabled = true,
    expanded_cell = nil,
    original_zoom_mode = nil,
    original_page_turn_direction = nil,
    ui = nil,
}

local QUADRANTS = {
    { id = "lmz_2tap_q1", x = 0,   y = 0,   w = 0.5, h = 0.5 },
    { id = "lmz_2tap_q2", x = 0.5, y = 0,   w = 0.5, h = 0.5 },
    { id = "lmz_2tap_q3", x = 0,   y = 0.5, w = 0.5, h = 0.5 },
    { id = "lmz_2tap_q4", x = 0.5, y = 0.5, w = 0.5, h = 0.5 },
}

-- Quadrant reading order: rows top to bottom, columns by reading direction.
local LTR_ORDER = { 1, 2, 3, 4 }
local RTL_ORDER = { 2, 1, 4, 3 }

function Grid:init(ui, Settings)
    self:reset()
    self.ui = ui
    self.enabled = Settings:get("grid_enabled")
    self.page_zoom_enabled = Settings:get("page_zoom_enabled")
    if self.page_zoom_enabled == nil then self.page_zoom_enabled = true end
    self.rtl_enabled = Settings:get("grid_rtl_enabled") or false
    self.navigation_enabled = Settings:get("grid_navigation_enabled")
    if self.navigation_enabled == nil then self.navigation_enabled = true end
end

function Grid:clearState()
    self.expanded_cell = nil
    self.original_zoom_mode = nil
    self.original_page_turn_direction = nil
    self.original_zoom = nil
    self.original_visible_area = nil
    self.original_scroll = nil
    self.original_config_scroll = nil
    self.original_page = nil
end

function Grid:cancelExpand()
    if self.pending_expand then
        UIManager:unschedule(self.pending_expand)
        self.pending_expand = nil
    end
end

function Grid:reset()
    self:cancelExpand()
    if self.paging and self.paging.onGotoViewRel == self.navigation_wrapper then
        self.paging.onGotoViewRel = self.inner_navigation
    end
    self.paging = nil
    self.navigation_wrapper = nil
    self.inner_navigation = nil
    self.can_continue = nil
    self:clearState()
end

function Grid:isCellExpanded()
    local cell = self.expanded_cell
    return cell ~= nil and cell >= 1 and cell <= 4
end

function Grid:isRTL()
    local config = self.ui.document and self.ui.document.configurable
    return self.rtl_enabled
        or (config and (config.writing_direction or 0) > 0)
        or (self.ui.view and self.ui.view.inverse_reading_order)
        or false
end

function Grid:readingOrder()
    return self:isRTL() and RTL_ORDER or LTR_ORDER
end

function Grid:setupTouchZones(is_supported)
    if not Device:isTouchDevice() then return end

    local zones = {}
    for i, q in ipairs(QUADRANTS) do
        zones[#zones + 1] = {
            id = q.id,
            ges = "two_finger_tap",
            overrides = {
                "two_finger_tap_top_left_corner", "two_finger_tap_top_right_corner",
                "two_finger_tap_bottom_left_corner", "two_finger_tap_bottom_right_corner",
            },
            screen_zone = { ratio_x = q.x, ratio_y = q.y, ratio_w = q.w, ratio_h = q.h },
            handler = function()
                if not is_supported() then return false end
                return self:onGesture(i)
            end,
        }
    end

    zones[#zones + 1] = {
        id = "lmz_single_tap",
        ges = "tap",
        overrides = {
            "tap_forward", "tap_backward", "readerconfigmenu_tap", "readermenu_tap",
            "tap_top_left_corner", "tap_top_right_corner",
            "tap_bottom_left_corner", "tap_bottom_right_corner",
        },
        screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
        handler = function(ges)
            if not is_supported() then return false end
            return self:onSingleTap(ges)
        end,
    }

    -- Menu and edge swipes also override paging_swipe and were registered
    -- earlier, so they keep priority over this zone.
    zones[#zones + 1] = {
        id = "lmz_cell_swipe",
        ges = "swipe",
        overrides = { "paging_swipe" },
        screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
        handler = function(ges)
            if not is_supported() then return false end
            return self:onSwipe(ges)
        end,
    }

    zones[#zones + 1] = {
        id = "lmz_page_spread",
        ges = "spread",
        overrides = { "spread_gesture" },
        screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
        handler = function(ges)
            if is_supported() and self.page_zoom_enabled and not self.expanded_cell then
                return self:expandPage(ges)
            end
            return false
        end,
    }

    zones[#zones + 1] = {
        id = "lmz_page_pinch",
        ges = "pinch",
        overrides = { "pinch_gesture" },
        screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
        handler = function()
            if is_supported() and self.expanded_cell then
                self:collapse()
                return true
            end
            return false
        end,
    }

    self.ui:registerTouchZones(zones)
end

-- Page buttons and KOReader's own page-turn paths call ReaderPaging's
-- onGotoViewRel. While a quadrant is zoomed, step through quadrants instead.
-- Install after PageSplit so this wrapper runs first.
function Grid:installNavigation(is_supported, can_continue)
    if self.navigation_wrapper or not self.ui.paging then return end
    local paging = self.ui.paging
    local inner = paging.onGotoViewRel
    self.paging = paging
    self.inner_navigation = inner
    self.can_continue = can_continue
    self.navigation_wrapper = function(reader, diff, no_page_turn)
        if self.navigation_enabled and self:isCellExpanded() and no_page_turn ~= true
                and (diff == 1 or diff == -1) and is_supported() then
            return self:step(diff)
        end
        return inner(reader, diff, no_page_turn)
    end
    paging.onGotoViewRel = self.navigation_wrapper
end

-- Returns the page size as displayed (accounting for document rotation).
function Grid:getPageSize()
    local zooming = self.ui.zooming
    local page_size = self.ui.document:getNativePageDimensions(zooming.current_page)
    if not page_size or page_size.w <= 0 or page_size.h <= 0 then return nil end
    if (self.ui.view.state.rotation or 0) % 180 ~= 0 then
        page_size = { w = page_size.h, h = page_size.w }
    end
    return page_size
end

-- Returns the area available to the page, like ReaderZooming:getZoom().
function Grid:getViewSize()
    local dimen = self.ui.zooming.dimen or self.ui.dimen
    local w = dimen and dimen.w or Screen:getWidth()
    local h = dimen and dimen.h or Screen:getHeight()
    local view = self.ui.view
    local footer = view.footer
    if view.footer_visible and footer and footer.getHeight
            and not (footer.settings and footer.settings.reclaim_height) then
        h = h - footer:getHeight()
    end
    return w, h
end

function Grid:saveView()
    local view, zooming = self.ui.view, self.ui.zooming
    self.original_zoom_mode = zooming.zoom_mode
    self.original_zoom = zooming.zoom
    self.original_visible_area = { x = view.visible_area.x, y = view.visible_area.y }
    self.original_scroll = view.page_scroll
    self.original_config_scroll = self.ui.document.configurable.page_scroll
    self.original_page = zooming.current_page
    if view.page_scroll then self.ui:handleEvent(Event:new("SetScrollMode", false)) end
end

function Grid:setZoom(zoom, x, y)
    local zooming = self.ui.zooming
    local was_free = zooming.zoom_mode == "free"
    zooming.zoom = zoom
    self.ui:handleEvent(Event:new("SetZoomMode", "free"))
    -- KOReader ignores a SetZoomMode event when the mode is unchanged.
    if was_free then zooming:setZoom() end
    self.ui.view:SetZoomCenter(x, y)
end

function Grid:expandPage(ges)
    local view = self.ui.view
    if not view or not self.ui.zooming then return false end

    local page_size = self:getPageSize()
    if not page_size then return false end

    -- Zoom to twice the page-fit size (a generous zoom for reading)
    local view_w, view_h = self:getViewSize()
    local new_zoom = math.min(view_w / page_size.w, view_h / page_size.h) * 2

    -- Determine center point from gesture or default to page center
    local center_x, center_y
    if ges and ges.pos then
        -- Convert screen position to page coordinates, then scale to new zoom
        local old_zoom = view.state.zoom or 1
        local vx = view.visible_area and view.visible_area.x or 0
        local vy = view.visible_area and view.visible_area.y or 0
        local offset = view.state.offset or { x = 0, y = 0 }
        center_x = (vx + ges.pos.x - offset.x) * new_zoom / old_zoom
        center_y = (vy + ges.pos.y - offset.y) * new_zoom / old_zoom
    else
        center_x = page_size.w * new_zoom / 2
        center_y = page_size.h * new_zoom / 2
    end

    self:saveView()
    self.expanded_cell = 0 -- 0 indicates full page zoom
    self:setZoom(new_zoom, center_x, center_y)
    return true
end

-- Zooms the view onto a quadrant. The original view must already be saved.
function Grid:showCell(cell, page_size)
    local view_w, view_h = self:getViewSize()
    -- Each quadrant is half the page width and half the page height
    local new_zoom = math.min(view_w / (page_size.w / 2), view_h / (page_size.h / 2))
    local col = (cell - 1) % 2
    local row = math.floor((cell - 1) / 2)
    local center_x = (col * 0.5 + 0.25) * page_size.w * new_zoom
    local center_y = (row * 0.5 + 0.25) * page_size.h * new_zoom
    self.expanded_cell = cell
    self:setZoom(new_zoom, center_x, center_y)
    return true
end

function Grid:expand(cell)
    if not self.ui.view or not self.ui.zooming then return false end
    local page_size = self:getPageSize()
    if not page_size then return false end
    self:saveView()

    -- Save and set RTL direction if enabled
    if self.rtl_enabled then
        local configurable = self.ui.document and self.ui.document.configurable
        if configurable then
            self.original_page_turn_direction = { value = configurable.writing_direction }
            configurable.writing_direction = 1 -- 1 = RTL in KOReader
        end
    end

    return self:showCell(cell, page_size)
end

-- Moves an already zoomed view to another quadrant, keeping the saved view.
function Grid:moveTo(cell)
    if cell == self.expanded_cell then return true end
    local page_size = self:getPageSize()
    if not page_size then return false end
    return self:showCell(cell, page_size)
end

-- Steps through quadrants in reading order. Past the first or last quadrant,
-- turns the page and zooms on the quadrant where reading continues.
function Grid:step(diff)
    local order = self:readingOrder()
    local index
    for i, cell in ipairs(order) do
        if cell == self.expanded_cell then index = i end
    end
    local target = index and order[index + diff]
    if target then return self:moveTo(target) end
    return self:turnPage(diff)
end

function Grid:turnPage(diff)
    local paging = self.ui.paging
    self:cancelExpand()
    self:collapse()
    if not paging then return true end
    local page = paging.current_page
    paging:onGotoViewRel(diff)
    local new_page = paging.current_page
    if new_page == page then return true end
    -- Wait for page-turn work (rotation, split-page panning) scheduled by
    -- the page change, then zoom on the new page.
    self.pending_expand = function()
        self.pending_expand = nil
        if self.expanded_cell or not self.enabled or not self.ui.paging
                or self.ui.paging.current_page ~= new_page
                or (self.can_continue and not self.can_continue()) then
            return
        end
        local order = self:readingOrder()
        self:expand(diff > 0 and order[1] or order[#order])
    end
    UIManager:nextTick(self.pending_expand)
    return true
end

function Grid:collapse()
    local zooming = self.ui.zooming
    if not zooming then return end

    self.expanded_cell = nil

    -- Restore original page turn direction if RTL was enabled
    if self.original_page_turn_direction ~= nil then
        local configurable = self.ui.document and self.ui.document.configurable
        if configurable then
            configurable.writing_direction = self.original_page_turn_direction.value
            self.original_page_turn_direction = nil
        end
    end

    if self.original_zoom_mode then
        if self.original_zoom_mode == "free" then
            zooming.zoom = self.original_zoom
            zooming:setZoom()
        end
        self.ui:handleEvent(Event:new("SetZoomMode", self.original_zoom_mode))
        self.original_zoom_mode = nil
    else
        self.ui:handleEvent(Event:new("SetZoomMode", "page"))
    end
    if self.original_scroll ~= nil and self.ui.view.page_scroll ~= self.original_scroll then
        self.ui:handleEvent(Event:new("SetScrollMode", self.original_scroll))
    end
    if self.original_config_scroll ~= nil then
        self.ui.document.configurable.page_scroll = self.original_config_scroll
    end
    -- The saved pan position only applies to the page it was taken on.
    if self.original_visible_area and zooming.current_page == self.original_page then
        local area = self.original_visible_area
        local visible = self.ui.view.visible_area
        self.ui.view:PanningUpdate(area.x - visible.x, area.y - visible.y)
    end
    self:clearState()
end

-- A page change from elsewhere (go to page, links, TOC) ends the zoom, so the
-- free zoom of one page is not carried over to a page of another size.
function Grid:onPageUpdate(pageno)
    if self.expanded_cell and self.original_page and pageno ~= self.original_page then
        self:collapse()
    end
end

function Grid:onGesture(quadrant)
    if not self.enabled then return false end

    if self.expanded_cell then
        self:collapse()
    else
        return self:expand(quadrant)
    end

    return true
end

function Grid:onSingleTap(ges)
    if not self.expanded_cell then return false end
    if self.navigation_enabled and self:isCellExpanded() and ges and ges.pos then
        -- Outer thirds move between quadrants; the middle returns to the page.
        local width = Screen:getWidth()
        local side
        if ges.pos.x < width / 3 then
            side = -1
        elseif ges.pos.x > width * 2 / 3 then
            side = 1
        end
        if side then
            -- Right is forward in LTR, left is forward in RTL.
            return self:step(self:isRTL() and -side or side)
        end
    end
    self:collapse()
    return true
end

function Grid:onSwipe(ges)
    if not (self.navigation_enabled and self:isCellExpanded() and ges) then return false end
    local direction = ges.direction
    if direction == "west" or direction == "east" then
        -- The content follows the finger: a westward swipe reveals the right column.
        local reveal_right = direction == "west"
        local forward = reveal_right ~= self:isRTL()
        return self:step(forward and 1 or -1)
    elseif direction == "north" or direction == "south" then
        local cell = self.expanded_cell
        local bottom_row = cell > 2
        if direction == "north" and not bottom_row then
            return self:moveTo(cell + 2)
        elseif direction == "south" and bottom_row then
            return self:moveTo(cell - 2)
        end
        return true -- Already at that edge; keep the zoom.
    end
    return false
end

function Grid:toggle()
    self.enabled = not self.enabled
    if not self.enabled and self.expanded_cell then
        self:collapse()
    end
    return self.enabled
end

function Grid:toggleRTL()
    self.rtl_enabled = not self.rtl_enabled
    return self.rtl_enabled
end

function Grid:toggleNavigation()
    self.navigation_enabled = not self.navigation_enabled
    return self.navigation_enabled
end

function Grid:togglePageZoom()
    self.page_zoom_enabled = not self.page_zoom_enabled
    if not self.page_zoom_enabled and self.expanded_cell == 0 then
        self:collapse()
    end
    return self.page_zoom_enabled
end

return Grid
