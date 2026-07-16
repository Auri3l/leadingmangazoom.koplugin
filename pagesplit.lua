--[[--
Page split module for LeadingMangaZoom plugin.
Splits landscape pages into two views.
@module leadingmangazoom.pagesplit
]]--

local Device = require("device")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local Screen = Device.screen

local PageSplit = {
    enabled = false,
    current_half = nil,
    is_landscape_page = false,
    original_zoom_mode = nil,
    ui = nil,
    document = nil,
    last_pageno = nil,
}

function PageSplit:init(ui, Settings)
    self.ui = ui
    self.enabled = Settings:get("pagesplit_enabled")
    self:reset()
end

function PageSplit:reset()
    self.current_half = nil
    self.is_landscape_page = false
    self.original_zoom_mode = nil
    self.last_pageno = nil
end

function PageSplit:isPageLandscape(document, pageno)
    if not document then return false end
    local page_size = document:getNativePageDimensions(pageno)
    if not page_size then return false end
    return page_size.w > page_size.h
end

function PageSplit:isRTL()
    local Grid = require("grid")
    if Grid and Grid.rtl_enabled then
        return true
    end
    -- Fallback to document's writing direction
    if self.document and self.document.configurable then
        return self.document.configurable.writing_direction == 1
    end
    return false
end

function PageSplit:zoomToHalf(half)
    local view = self.ui.view
    local zooming = self.ui.zooming
    if not view or not zooming then return end

    if not self.original_zoom_mode then
        self.original_zoom_mode = zooming.zoom_mode
    end

    self.current_half = half

    -- Use contentheight zoom mode to fit the full page height on screen
    self.ui:handleEvent(Event:new("SetZoomMode", "contentheight"))

    -- Schedule pan after zoom mode has been applied and recalculate() has run
    UIManager:scheduleIn(0.1, function()
        if not view or not view.visible_area or not view.page_area then return end

        -- Pan the visible_area to the correct half using the view's PanningUpdate
        if half == "left" then
            -- Pan to the leftmost position
            local dx = view.page_area.x - view.visible_area.x
            view:PanningUpdate(dx, 0)
        else
            -- Pan to the rightmost position
            local dx = (view.page_area.x + view.page_area.w - view.visible_area.w) - view.visible_area.x
            view:PanningUpdate(dx, 0)
        end
    end)
end

function PageSplit:restoreZoom()
    if self.original_zoom_mode then
        self.ui:handleEvent(Event:new("SetZoomMode", self.original_zoom_mode))
        self.original_zoom_mode = nil
    end
    self.current_half = nil
end

function PageSplit:onPageUpdate(document, pageno)
    if not self.enabled then return end

    self.document = document
    local is_landscape = self:isPageLandscape(document, pageno)

    if is_landscape then
        if not self.is_landscape_page or pageno ~= self.last_pageno then
            self.is_landscape_page = true
            self.last_pageno = pageno
            if self:isRTL() then
                self:zoomToHalf("right")
            else
                self:zoomToHalf("left")
            end
        end
    elseif not is_landscape and self.is_landscape_page then
        self.is_landscape_page = false
        self.last_pageno = pageno
        self:restoreZoom()
    end
end

function PageSplit:onGotoNextPage()
    if not self.enabled or not self.is_landscape_page then
        return false
    end

    local rtl = self:isRTL()
    if rtl then
        if self.current_half == "right" then
            self:zoomToHalf("left")
            return true
        elseif self.current_half == "left" then
            self.is_landscape_page = false
            self:restoreZoom()
            return false
        end
    else
        if self.current_half == "left" then
            self:zoomToHalf("right")
            return true
        elseif self.current_half == "right" then
            self.is_landscape_page = false
            self:restoreZoom()
            return false
        end
    end

    return false
end

function PageSplit:onGotoPrevPage()
    if not self.enabled or not self.is_landscape_page then
        return false
    end

    local rtl = self:isRTL()
    if rtl then
        if self.current_half == "left" then
            self:zoomToHalf("right")
            return true
        elseif self.current_half == "right" then
            self.is_landscape_page = false
            self:restoreZoom()
            return false
        end
    else
        if self.current_half == "right" then
            self:zoomToHalf("left")
            return true
        elseif self.current_half == "left" then
            self.is_landscape_page = false
            self:restoreZoom()
            return false
        end
    end

    return false
end

function PageSplit:toggle()
    self.enabled = not self.enabled
    if not self.enabled and self.is_landscape_page then
        self:restoreZoom()
        self.is_landscape_page = false
    end
    return self.enabled
end

return PageSplit
