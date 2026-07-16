--[[--
Settings module for LeadingMangaZoom plugin.
@module leadingmangazoom.settings
]]--

local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")

local Settings = {}
local settings_file = DataStorage:getSettingsDir() .. "/leadingmangazoom.lua"
local settings = nil

local DEFAULTS = {
    grid_enabled = true,
    grid_rtl_enabled = false,
    page_zoom_enabled = true,
    autorotate_enabled = true,
    rotate_clockwise = true,
    pagesplit_enabled = false,
}

function Settings:load()
    settings = LuaSettings:open(settings_file)
end

function Settings:get(key)
    if not settings then self:load() end
    local value = settings:readSetting(key)
    if value == nil then return DEFAULTS[key] end
    return value
end

function Settings:set(key, value)
    if not settings then self:load() end
    settings:saveSetting(key, value)
    settings:flush()
end

return Settings
