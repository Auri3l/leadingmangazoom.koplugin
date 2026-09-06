--[[--
Grid zoom module for LeadingMangaZoom plugin.
@module leadingmangazoom.grid
]]--

local Device = require("device")
local Event = require("ui/event")
local Screen = Device.screen

local Grid = {
    enabled = true,
    page_zoom_enabled = true,
    rtl_enabled = false,
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

function Grid:init(ui, Settings)
    self:reset()
    self.ui = ui
    self.enabled = Settings:get("grid_enabled")
    self.page_zoom_enabled = Settings:get("page_zoom_enabled")
    if self.page_zoom_enabled == nil then self.page_zoom_enabled = true end
    self.rtl_enabled = Settings:get("grid_rtl_enabled") or false
end

function Grid:reset()
    self.expanded_cell = nil
    self.original_zoom_mode = nil
    self.original_page_turn_direction = nil
    self.original_zoom = nil
    self.original_visible_area = nil
    self.original_scroll = nil
    self.original_config_scroll = nil
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
        handler = function(ges)
            if is_supported() and self.expanded_cell then
                self:collapse()
                return true
            end
            return false
        end,
    }

    self.ui:registerTouchZones(zones)
end

function Grid:saveView()
    local view, zooming = self.ui.view, self.ui.zooming
    self.original_zoom_mode = zooming.zoom_mode
    self.original_zoom = zooming.zoom
    self.original_visible_area = { x = view.visible_area.x, y = view.visible_area.y }
    self.original_scroll = view.page_scroll
    self.original_config_scroll = self.ui.document.configurable.page_scroll
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
    local zooming = self.ui.zooming

    if not view or not zooming then return false end

    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()

    -- Get page dimensions for accurate zoom calculation
    local page_size = self.ui.document:getNativePageDimensions(zooming.current_page)
    if not page_size or page_size.w <= 0 or page_size.h <= 0 then return false end
    if (view.state.rotation or 0) % 180 ~= 0 then
        page_size = { w = page_size.h, h = page_size.w }
    end

    -- Calculate zoom to fit page at 2x (a generous zoom for reading)
    local zoom_w = screen_w / page_size.w
    local zoom_h = screen_h / page_size.h
    local new_zoom = math.min(zoom_w, zoom_h) * 2

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

    -- Follow KOReader's onToggleFreeZoom pattern:
    -- 1. Set zoom value FIRST
    -- 2. Then trigger mode change (which recalculates using our zoom value)
    -- 3. Then set center position
    self:saveView()
    self.expanded_cell = 0 -- 0 indicates full page zoom
    self:setZoom(new_zoom, center_x, center_y)
    return true
end

function Grid:expand(cell)
    local view = self.ui.view
    local zooming = self.ui.zooming

    if not view or not zooming then return false end
    local page_size = self.ui.document:getNativePageDimensions(zooming.current_page)
    if not page_size or page_size.w <= 0 or page_size.h <= 0 then return false end
    if (view.state.rotation or 0) % 180 ~= 0 then
        page_size = { w = page_size.h, h = page_size.w }
    end
    self:saveView()
    self.expanded_cell = cell

    -- Save and set RTL direction if enabled
    if self.rtl_enabled then
        local configurable = self.ui.document and self.ui.document.configurable
        if configurable then
            self.original_page_turn_direction = { value = configurable.writing_direction }
            configurable.writing_direction = 1 -- 1 = RTL in KOReader
        end
    end

    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()

    -- Calculate zoom to fit one quadrant to the screen
    -- Each quadrant is half the page width and half the page height
    local zoom_w = screen_w / (page_size.w / 2)
    local zoom_h = screen_h / (page_size.h / 2)
    local new_zoom = math.min(zoom_w, zoom_h)

    -- Calculate center of the target quadrant in page coordinates, scaled by new zoom
    local col = (cell - 1) % 2
    local row = math.floor((cell - 1) / 2)
    local center_x = (col * 0.5 + 0.25) * page_size.w * new_zoom
    local center_y = (row * 0.5 + 0.25) * page_size.h * new_zoom

    -- Follow KOReader's onToggleFreeZoom pattern:
    -- 1. Set zoom value FIRST
    -- 2. Then trigger mode change (which recalculates using our zoom value)
    -- 3. Then set center position
    self:setZoom(new_zoom, center_x, center_y)
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
    self.ui.document.configurable.page_scroll = self.original_config_scroll
    if self.original_visible_area then
        local area = self.original_visible_area
        local visible = self.ui.view.visible_area
        self.ui.view:PanningUpdate(area.x - visible.x, area.y - visible.y)
    end
    self:reset()
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
    if self.expanded_cell then
        self:collapse()
        return true
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

function Grid:togglePageZoom()
    self.page_zoom_enabled = not self.page_zoom_enabled
    if not self.page_zoom_enabled and self.expanded_cell == 0 then
        self:collapse()
    end
    return self.page_zoom_enabled
end

return Grid
