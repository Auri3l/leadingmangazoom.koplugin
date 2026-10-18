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

function Menu:build(plugin, Grid, AutoRotate, PageSplit, Settings, Updater)
    local self_menu = self
    local items = {
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
                text_func = function()
                    return _("Double-tap to zoom") .. (Grid.double_tap_enabled
                        and (" (" .. tostring(Grid.double_tap_level):gsub("%.0$", "") .. "×)") or "")
                end,
                sub_item_table_func = function()
                    local items = {
                        {
                            text = _("Double-tap to zoom"),
                            help_text = _("Double tap anywhere on the page to zoom in on that spot; double tap again to return to the page. This turns on double taps for supported books, so single taps (page turns) wait a moment to see whether a second tap follows."),
                            checked_func = function() return Grid.double_tap_enabled end,
                            -- Remembered right away, unlike the reading options (tap: this
                            -- book, hold: default): those default to ON, but this one is off,
                            -- so a this-book-only switch seemed to turn itself off (#12).
                            callback = function()
                                local enabled = Grid:toggleDoubleTap()
                                Settings:set("double_tap_zoom", enabled)
                                plugin:applyDoubleTap()
                                self_menu:showMessage(enabled
                                    and "Double-tap zoom ON\nDouble tap anywhere to zoom in or out"
                                    or "Double-tap zoom OFF")
                            end,
                            hold_callback = function()
                                Settings:set("double_tap_zoom", Grid.double_tap_enabled)
                                self_menu:showMessage("Double-tap zoom default: " .. (Grid.double_tap_enabled and "ON" or "OFF"))
                            end,
                            separator = true,
                        },
                    }
                    for __, level in ipairs(Grid.DOUBLE_TAP_LEVELS) do
                        local label = tostring(level):gsub("%.0$", "") .. "×"
                        items[#items + 1] = {
                            text = _("Zoom level") .. ": " .. label,
                            radio = true,
                            enabled_func = function() return Grid.double_tap_enabled end,
                            checked_func = function() return Grid.double_tap_level == level end,
                            callback = function()
                                Grid.double_tap_level = level
                                Settings:set("double_tap_zoom_level", level)
                            end,
                        }
                    end
                    return items
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
                        "DOUBLE TAP to zoom (if on in menu).\n" ..
                        "SWIPE or TAP the sides to move\n" ..
                        "between quadrants.\n" ..
                        "TAP the middle to return.\n" ..
                        "SPREAD to zoom freely, DRAG\n" ..
                        "to pan, PINCH to zoom out.\n" ..
                        "Desktop: CTRL + WHEEL or CTRL +/-\n" ..
                        "to zoom, WHEEL to scroll,\n" ..
                        "CTRL 0 to return.\n" ..
                        "Auto-rotates landscape pages.\n" ..
                        "Split landscape into two pages.\n\n" ..
                        "Hold option to set as default.\n" ..
                        "Updates: menu > Updates.\n\n" ..
                        "Supports: CBZ, CBR, CBT, CB7, CZB, PDF\n\n" ..
                        "Forked from Maximum by @shac0x\n" ..
                        "Maintained by @Aur13l"
                    )
                end,
            },
    }
    -- Reading features need a supported document; About and Updates don't.
    local is_comic = function() return plugin:isComic() end
    local about = _("About")
    for __, item in ipairs(items) do
        if item.text ~= about then item.enabled_func = is_comic end
    end
    if Updater then
        table.insert(items, #items, {
            text_func = function()
                return _("Updates") .. " (v" .. Updater:installedVersion() .. ")"
            end,
            sub_item_table = {
                {
                    text = _("Check for updates"),
                    keep_menu_open = true,
                    callback = function() Updater:check() end,
                },
                {
                    text = _("Check automatically once a day"),
                    help_text = _("When Wi-Fi is already on, check GitHub for a new version at most once a day and offer to install it. Wi-Fi is never turned on for this."),
                    checked_func = function() return Updater:autoCheckEnabled() end,
                    callback = function() Updater:setAutoCheck(not Updater:autoCheckEnabled()) end,
                },
            },
        })
    end
    return {
        text = _("Leading Manga Zoom"),
        sorting_hint = "typeset",
        sub_item_table = items,
    }
end

return Menu
