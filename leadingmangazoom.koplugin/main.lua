--[[--
LeadingMangaZoom plugin for KOReader
@module koplugin.leadingmangazoom
@credits Forked from Maximum by @shac0x, maintained by @Aur13l
]]--

local InputContainer = require("ui/widget/container/inputcontainer")

-- Plugin directories share package.path and package.loaded. Load our own
-- files explicitly so Maximum (or another plugin) cannot supply our modules.
local plugin_dir = debug.getinfo(1, "S").source:match("^@(.+[/\\])")
local Settings = dofile(plugin_dir .. "settings.lua")
local AutoRotate = dofile(plugin_dir .. "autorotate.lua")
local Grid = dofile(plugin_dir .. "grid.lua")
local PageSplit = dofile(plugin_dir .. "pagesplit.lua")
local Menu = dofile(plugin_dir .. "menu.lua")
local Updater = dofile(plugin_dir .. "updater.lua")

local SUPPORTED_EXTENSIONS = {
    cbz = true,
    cbr = true,
    pdf = true,
    cbt = true,
    cb7 = true,
    czb = true,
}

local Device = require("device")

local LeadingMangaZoom = InputContainer:extend{
    name = "leadingmangazoom",
    is_doc_only = true,
}

function LeadingMangaZoom:init()
    self.ui.menu:registerToMainMenu(self)
    Updater:init(plugin_dir, Settings)
    -- Desktop and keyboard devices: Ctrl + / Ctrl - zoom, Ctrl 0 returns to
    -- the page. "+" usually needs Shift, so accept it with or without Shift.
    -- KOReader's desktop key map has no keypad +, - and 0 (SDL keycodes
    -- 0x40000057, 0x40000056, 0x40000062), so those keys did nothing. Give
    -- them the same names as the main keys; codes already mapped are left alone.
    local input = Device.input
    if Device.isSDL and Device:isSDL() and input and input.event_map then
        for code, name in pairs({ [0x40000057] = "+", [0x40000056] = "-", [0x40000062] = "0" }) do
            if input.event_map[code] == nil then input.event_map[code] = name end
        end
    end
    if Device.hasKeyboard and Device:hasKeyboard() then
        self.key_events = {
            LMZZoomIn = {
                { "Ctrl", "=" }, { "Ctrl", "Shift", "=" }, { "Ctrl", "+" }, { "Ctrl", "Shift", "+" },
                event = "LMZZoom", args = "in",
            },
            LMZZoomOut = {
                { "Ctrl", "-" }, { "Ctrl", "Shift", "-" },
                event = "LMZZoom", args = "out",
            },
            LMZZoomReset = {
                { "Ctrl", "0" },
                event = "LMZZoom", args = "reset",
            },
        }
    end
end

function LeadingMangaZoom:onLMZZoom(direction)
    if not (self.ready and self:isComic()) then return false end
    if direction == "reset" then
        if not Grid.expanded_cell then return false end
        Grid:collapse()
        return true
    end
    if not Grid.page_zoom_enabled then return false end
    if direction == "in" then return Grid:zoomStepIn() end
    return Grid:zoomStepOut()
end

function LeadingMangaZoom:onReaderReady()
    -- Opt-in, at most once a day, never turns Wi-Fi on by itself.
    pcall(Updater.maybeAutoCheck, Updater)
    Grid:init(self.ui, Settings)
    PageSplit:init(self.ui, Settings, Grid, function() return self:isComic() end)
    if not self:isComic() then return end
    AutoRotate:init(Settings, PageSplit.enabled)
    -- The opening PageUpdate occurs before ReaderReady. Wait until every
    -- reader module has initialized, then apply settings to the current page.
    self.ui:registerPostReaderReadyCallback(function()
        local is_comic = function() return self:isComic() end
        Grid:setupTouchZones(is_comic)
        PageSplit:installNavigation()
        -- Quadrant navigation continues onto the next page, except onto a
        -- split spread, whose halves PageSplit already shows separately.
        Grid:installNavigation(is_comic, function() return not PageSplit.is_landscape_page end)
        Grid:installWheel(is_comic)
        self:applyDoubleTap()
        self.ready = true
        self:refreshPage()
    end)
end

function LeadingMangaZoom:isComic()
    local doc = self.ui and self.ui.document
    if not doc or not doc.file or not self.ui.paging or not self.ui.zooming
            or type(doc.getNativePageDimensions) ~= "function"
            or (doc.configurable and doc.configurable.text_wrap == 1) then
        return false
    end
    local ext = doc.file:match("%.([^%.]+)$")
    return ext and SUPPORTED_EXTENSIONS[ext:lower()] or false
end

function LeadingMangaZoom:onPageUpdate(pageno)
    if self.ready and self:isComic() then
        Grid:onPageUpdate(pageno)
        AutoRotate:onPageUpdate(self.ui.document, pageno)
        PageSplit:onPageUpdate(self.ui.document, pageno)
    end
end

-- Runs after ReaderZooming saved "free", our temporary mode.
function LeadingMangaZoom:onSaveSettings()
    local mode = self.ready and Grid:savedZoomMode()
    if mode and self.ui.doc_settings then
        self.ui.doc_settings:saveSetting("zoom_mode", mode)
    end
end

-- KOReader only reports double taps when its "double tap" setting is on
-- (off by default, as single taps then wait to see if a second follows).
-- While double-tap zoom is on, turn double taps on for this book; otherwise
-- follow KOReader's setting.
function LeadingMangaZoom:applyDoubleTap()
    local want_double_tap = Grid.double_tap_enabled and self:isComic()
    local disable
    if want_double_tap then
        disable = false
    else
        disable = not (G_reader_settings and G_reader_settings.isFalse
            and G_reader_settings:isFalse("disable_double_tap"))
    end
    self.ui.disable_double_tap = disable
    local input = Device.input
    if input then input.disable_double_tap = disable end
end

function LeadingMangaZoom:onZoomModeUpdate(new_mode)
    if self.ready then Grid:onZoomModeUpdate(new_mode) end
end

function LeadingMangaZoom:refreshPage()
    if self.ready and self:isComic() then
        self:onPageUpdate(self.ui.paging.current_page)
    end
end

function LeadingMangaZoom:addToMainMenu(menu_items)
    menu_items.leadingmangazoom = Menu:build(self, Grid, AutoRotate, PageSplit, Settings, Updater)
end

function LeadingMangaZoom:onCloseDocument()
    self.ready = false
    if Grid.expanded_cell then Grid:collapse() end
    Grid:reset()
    if AutoRotate.last_portrait_rotation_mode ~= nil then
        AutoRotate:restorePortrait()
    end
    AutoRotate:reset()
    PageSplit:restoreZoom()
    PageSplit:reset()
end

return LeadingMangaZoom
