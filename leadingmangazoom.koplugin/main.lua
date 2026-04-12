--[[--
LeadingMangaZoom plugin for KOReader
@module koplugin.leadingmangazoom
@credits Forked from Maximum by @shac0x, maintained by @Aur13l
]]--

local InputContainer = require("ui/widget/container/inputcontainer")

local Settings = require("settings")
local AutoRotate = require("autorotate")
local Grid = require("grid")
local PageSplit = require("pagesplit")
local Menu = require("menu")

local SUPPORTED_EXTENSIONS = {
    cbz = true,
    cbr = true,
    pdf = true,
    cbt = true,
    cb7 = true,
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
    Grid:setupTouchZones(function(quadrant, ges)
        return self:onGridGesture(quadrant, ges)
    end)
    AutoRotate:init(Settings)
    PageSplit:init(self.ui, Settings)
end

function LeadingMangaZoom:isComic()
    local doc = self.ui and self.ui.document
    if not doc or not doc.file then return false end
    local ext = doc.file:match("%.([^%.]+)$")
    return ext and SUPPORTED_EXTENSIONS[ext:lower()] or false
end

function LeadingMangaZoom:onPageUpdate(pageno)
    if self:isComic() then
        AutoRotate:onPageUpdate(self.ui.document, pageno)
        PageSplit:onPageUpdate(self.ui.document, pageno)
    end
end

function LeadingMangaZoom:onGotoNextPos()
    if self:isComic() and PageSplit.enabled then
        return PageSplit:onGotoNextPage()
    end
    return false
end

function LeadingMangaZoom:onGotoPreviousPos()
    if self:isComic() and PageSplit.enabled then
        return PageSplit:onGotoPrevPage()
    end
    return false
end

function LeadingMangaZoom:onGridGesture(quadrant, ges)
    if not self:isComic() then return false end
    return Grid:onGesture(quadrant)
end

function LeadingMangaZoom:addToMainMenu(menu_items)
    menu_items.leadingmangazoom = Menu:build(self, Grid, AutoRotate, PageSplit, Settings)
end

function LeadingMangaZoom:onCloseDocument()
    Grid:reset()
    if AutoRotate.enabled then
        AutoRotate:restorePortrait()
    end
    AutoRotate:reset()
    PageSplit:reset()
end

return LeadingMangaZoom
