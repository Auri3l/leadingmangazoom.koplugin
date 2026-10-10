--[[--
Menu module for LeadingMangaZoom plugin.
@module leadingmangazoom.menu
]]--

local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local _ = require("gettext")

local Menu = {}

function Menu:showMessage(text, timeout)
    UIManager:show(InfoMessage:new{
        text = text,
        timeout = timeout or 2,
    })
end

function Menu:build(plugin, Grid, AutoRotate, PageSplit, Settings)
    local self_menu = self
    return {
        text = _("Leading Manga Zoom"),
        sorting_hint = "typeset",
        enabled_func = function() return plugin:isComic() end,
        sub_item_table = {
            {
                text = _("Enable Grid Mode"),
                checked_func = function() return Grid.enabled end,
                callback = function()
                    if not plugin:isComic() then
                        self_menu:showMessage("Open a CBZ, CBR, CBT, CB7, CZB or PDF file first.")
                        return
                    end
                    local enabled = Grid:toggle()
                    self_menu:showMessage(enabled
                        and "Grid Mode ON\n2-FINGER TAP any quadrant"
                        or "Grid Mode OFF")
                end,
                hold_callback = function()
                    Settings:set("grid_enabled", Grid.enabled)
                    self_menu:showMessage("Grid Mode default: " .. (Grid.enabled and "ON" or "OFF"))
                end,
            },
            {
                text = _("Grid RTL Mode (Right-to-Left)"),
                checked_func = function() return Grid.rtl_enabled end,
                callback = function()
                    local enabled = Grid:toggleRTL()
                    self_menu:showMessage(enabled
                        and "RTL Mode ON\nReading direction: Right-to-Left"
                        or "RTL Mode OFF\nReading direction: Left-to-Right")
                end,
                hold_callback = function()
                    Settings:set("grid_rtl_enabled", Grid.rtl_enabled)
                    self_menu:showMessage("RTL Mode default: " .. (Grid.rtl_enabled and "ON" or "OFF"))
                end,
            },
            {
                text = _("Swipe/tap to move between quadrants"),
                checked_func = function() return Grid.navigation_enabled end,
                callback = function()
                    local enabled = Grid:toggleNavigation()
                    self_menu:showMessage(enabled
                        and "Quadrant navigation ON\nSwipe, tap the left/right side\nor use page buttons to move"
                        or "Quadrant navigation OFF\nTap anywhere to return to the page")
                end,
                hold_callback = function()
                    Settings:set("grid_navigation_enabled", Grid.navigation_enabled)
                    self_menu:showMessage("Quadrant navigation default: " .. (Grid.navigation_enabled and "ON" or "OFF"))
                end,
            },
            {
                text = _("Enable Page Zoom"),
                checked_func = function() return Grid.page_zoom_enabled end,
                callback = function()
                    local enabled = Grid:togglePageZoom()
                    self_menu:showMessage(enabled
                        and "Page Zoom ON\nPinch or Spread on the page to zoom"
                        or "Page Zoom OFF")
                end,
                hold_callback = function()
                    Settings:set("page_zoom_enabled", Grid.page_zoom_enabled)
                    self_menu:showMessage("Page Zoom default: " .. (Grid.page_zoom_enabled and "ON" or "OFF"))
                end,
            },
            {
                text = _("Auto-rotate landscape pages"),
                checked_func = function() return AutoRotate.enabled end,
                callback = function()
                    local enabled = AutoRotate:toggle()
                    local msg = ""
                    if enabled then
                        if PageSplit.enabled then
                            PageSplit:toggle()
                            msg = "Auto-rotate ON\nPage Split disabled\nLandscape pages will rotate automatically"
                        else
                            msg = "Auto-rotate ON\nLandscape pages will rotate automatically"
                        end
                    else
                        msg = "Auto-rotate OFF"
                    end
                    plugin:refreshPage()
                    self_menu:showMessage(msg)
                end,
                hold_callback = function()
                    Settings:set("autorotate_enabled", AutoRotate.enabled)
                    self_menu:showMessage("Auto-rotate default: " .. (AutoRotate.enabled and "ON" or "OFF"))
                end,
            },
            {
                text = _("Rotation direction"),
                sub_item_table = {
                    {
                        text = _("Clockwise (90°)"),
                        checked_func = function() return AutoRotate.clockwise end,
                        callback = function()
                            AutoRotate:setDirection(true)
                            plugin:refreshPage()
                            self_menu:showMessage("Rotation: Clockwise", 1)
                        end,
                        hold_callback = function()
                            AutoRotate:setDirection(true)
                            Settings:set("rotate_clockwise", true)
                            self_menu:showMessage("Default rotation: Clockwise")
                        end,
                    },
                    {
                        text = _("Counter-clockwise (270°)"),
                        checked_func = function() return not AutoRotate.clockwise end,
                        callback = function()
                            AutoRotate:setDirection(false)
                            plugin:refreshPage()
                            self_menu:showMessage("Rotation: Counter-clockwise", 1)
                        end,
                        hold_callback = function()
                            AutoRotate:setDirection(false)
                            Settings:set("rotate_clockwise", false)
                            self_menu:showMessage("Default rotation: Counter-clockwise")
                        end,
                    },
                },
            },
            {
                text = _("Split landscape pages"),
                checked_func = function() return PageSplit.enabled end,
                callback = function()
                    local enabled = PageSplit:toggle()
                    local msg = ""
                    if enabled then
                        if AutoRotate.enabled then
                            AutoRotate:toggle()
                            msg = "Page Split ON\nAuto-rotate disabled\nLandscape pages will show in two halves"
                        else
                            msg = "Page Split ON\nLandscape pages will show in two halves"
                        end
                    else
                        msg = "Page Split OFF"
                    end
                    plugin:refreshPage()
                    self_menu:showMessage(msg)
                end,
                hold_callback = function()
                    Settings:set("pagesplit_enabled", PageSplit.enabled)
                    self_menu:showMessage("Page Split default: " .. (PageSplit.enabled and "ON" or "OFF"))
                end,
            },
            {
                text = _("About"),
                callback = function()
                    self_menu:showMessage(
                        "Leading Manga Zoom\n\n" ..
                        "2-FINGER TAP to zoom quadrant.\n" ..
                        "SWIPE or TAP the sides to move\n" ..
                        "between quadrants.\n" ..
                        "TAP the middle to return.\n" ..
                        "Auto-rotates landscape pages.\n" ..
                        "Split landscape into two pages.\n\n" ..
                        "Hold option to set as default.\n\n" ..
                        "Supports: CBZ, CBR, CBT, CB7, CZB, PDF\n\n" ..
                        "Forked from Maximum by @shac0x\n" ..
                        "Maintained by @Aur13l"
                    )
                end,
            },
        },
    }
end

return Menu
