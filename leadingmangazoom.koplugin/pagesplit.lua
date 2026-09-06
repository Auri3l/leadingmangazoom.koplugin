-- Landscape spreads are two logical views of one physical page.
local Event = require("ui/event")
local UIManager = require("ui/uimanager")

local PageSplit = { enabled = false }

function PageSplit:init(ui, Settings, grid, is_supported)
    self:reset()
    self.ui = ui
    self.grid = grid
    self.is_supported = is_supported
    self.enabled = Settings:get("pagesplit_enabled")
end

function PageSplit:cancelPan()
    if self.pending_pan then
        UIManager:unschedule(self.pending_pan)
        self.pending_pan = nil
    end
end

function PageSplit:reset()
    self:cancelPan()
    if self.paging and self.paging.onGotoViewRel == self.navigation_wrapper then
        self.paging.onGotoViewRel = self.original_navigation
    end
    self.paging = nil
    self.navigation_wrapper = nil
    self.original_navigation = nil
    self.current_half = nil
    self.is_landscape_page = false
    self.original_zoom_mode = nil
    self.original_zoom = nil
    self.original_scroll = nil
    self.original_config_scroll = nil
    self.last_pageno = nil
    self.document = nil
    self.navigation_direction = nil
end

function PageSplit:isPageLandscape(document, pageno)
    local size = document and document:getNativePageDimensions(pageno)
    return size and size.w > size.h and size.h > 0 or false
end

function PageSplit:isRTL()
    local config = self.document and self.document.configurable
    return self.grid.rtl_enabled or (config and (config.writing_direction or 0) > 0) or false
end

function PageSplit:zoomToHalf(half)
    local view, zooming = self.ui.view, self.ui.zooming
    if not view or not zooming then return end
    self:cancelPan()
    if not self.original_zoom_mode then
        self.original_zoom_mode = zooming.zoom_mode
        self.original_zoom = zooming.zoom
        self.original_scroll = view.page_scroll
        self.original_config_scroll = self.ui.document.configurable.page_scroll
    end
    self.current_half = half
    -- A spread must be rendered as a single page, without cropping its gutter.
    if view.page_scroll then self.ui:handleEvent(Event:new("SetScrollMode", false)) end
    self.ui:handleEvent(Event:new("SetZoomMode", "pageheight"))

    -- PageUpdate can still trigger a footer/layout recalculation. Pan once
    -- after that event finishes, cancelling stale work on navigation/close.
    local pageno = self.last_pageno
    self.pending_pan = function()
        self.pending_pan = nil
        if not self.enabled or self.last_pageno ~= pageno or self.current_half ~= half then return end
        local area, visible = view.page_area, view.visible_area
        if not area or not visible then return end
        local x = half == "left" and area.x or area.x + area.w - visible.w
        view:PanningUpdate(x - visible.x, area.y - visible.y)
    end
    UIManager:nextTick(self.pending_pan)
end

function PageSplit:restoreZoom()
    self:cancelPan()
    if self.original_zoom_mode then
        local mode = self.original_zoom_mode
        self.original_zoom_mode = nil
        if mode == "free" then self.ui.zooming.zoom = self.original_zoom end
        self.ui:handleEvent(Event:new("SetZoomMode", mode))
        if self.original_scroll ~= nil and self.ui.view.page_scroll ~= self.original_scroll then
            self.ui:handleEvent(Event:new("SetScrollMode", self.original_scroll))
        end
        self.ui.document.configurable.page_scroll = self.original_config_scroll
    end
    self.current_half = nil
end

function PageSplit:onPageUpdate(document, pageno)
    if not self.enabled then return end
    self.document = document
    if self:isPageLandscape(document, pageno) then
        local first = self:isRTL() and "right" or "left"
        local last = first == "left" and "right" or "left"
        local half = self.current_half
        if pageno ~= self.last_pageno or not half then
            half = self.navigation_direction == -1 and last or first
        end
        self.last_pageno = pageno
        self.is_landscape_page = true
        self:zoomToHalf(half)
    else
        self.is_landscape_page = false
        self.last_pageno = pageno
        self:restoreZoom()
    end
end

function PageSplit:installNavigation()
    if self.navigation_wrapper then return end
    local paging = self.ui.paging
    local original = paging.onGotoViewRel
    self.paging = paging
    self.original_navigation = original
    -- Both touch-zone callbacks and physical keys call this reader instance.
    -- A plugin event handler alone runs too late (ReaderPaging consumes it).
    self.navigation_wrapper = function(reader, diff, no_page_turn)
        if not self.enabled or not self.is_supported() or no_page_turn == true
                or (diff ~= 1 and diff ~= -1) then
            return original(reader, diff, no_page_turn)
        end
        if self.grid.expanded_cell then self.grid:collapse() end
        self.navigation_direction = diff
        local result
        if self.is_landscape_page then
            local first = self:isRTL() and "right" or "left"
            local last = first == "left" and "right" or "left"
            if diff == 1 and self.current_half == first then
                self:zoomToHalf(last)
            elseif diff == -1 and self.current_half == last then
                self:zoomToHalf(first)
            else
                local target = reader.current_page + diff
                if target >= 1 and target <= reader.number_of_pages then
                    reader:_gotoPage(target)
                elseif diff == 1 then
                    self.ui:handleEvent(Event:new("EndOfBook"))
                end
            end
            reader:setPagePosition(reader:getTopPage(), reader:getTopPosition())
            result = true
        else
            result = original(reader, diff, no_page_turn)
        end
        self.navigation_direction = nil
        return result
    end
    paging.onGotoViewRel = self.navigation_wrapper
end

function PageSplit:toggle()
    self.enabled = not self.enabled
    if not self.enabled then
        self:restoreZoom()
        self.is_landscape_page = false
    end
    return self.enabled
end

return PageSplit
