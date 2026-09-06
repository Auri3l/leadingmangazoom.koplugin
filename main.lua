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

local SUPPORTED_EXTENSIONS = {
    cbz = true,
    cbr = true,
    pdf = true,
    cbt = true,
    cb7 = true,
    czb = true,
}

local LeadingMangaZoom = InputContainer:extend{
    name = "leadingmangazoom",
    is_doc_only = true,
}

function LeadingMangaZoom:init()
    self.ui.menu:registerToMainMenu(self)
end

function LeadingMangaZoom:onReaderReady()
    Grid:init(self.ui, Settings)
    PageSplit:init(self.ui, Settings, Grid, function() return self:isComic() end)
    if not self:isComic() then return end
    AutoRotate:init(Settings, PageSplit.enabled)
    -- The opening PageUpdate occurs before ReaderReady. Wait until every
    -- reader module has initialized, then apply settings to the current page.
    self.ui:registerPostReaderReadyCallback(function()
        Grid:setupTouchZones(function() return self:isComic() end)
        PageSplit:installNavigation()
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
        AutoRotate:onPageUpdate(self.ui.document, pageno)
        PageSplit:onPageUpdate(self.ui.document, pageno)
    end
end

function LeadingMangaZoom:refreshPage()
    if self.ready and self:isComic() then
        self:onPageUpdate(self.ui.paging.current_page)
    end
end

function LeadingMangaZoom:addToMainMenu(menu_items)
    menu_items.leadingmangazoom = Menu:build(self, Grid, AutoRotate, PageSplit, Settings)
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
