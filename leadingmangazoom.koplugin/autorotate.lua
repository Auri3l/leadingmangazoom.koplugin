--[[--
Auto-rotate module for LeadingMangaZoom plugin.
Based on https://github.com/Extraltodeus/koreader-autorotate
@module leadingmangazoom.autorotate
]]--

local Device = require("device")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local Screen = Device.screen
local Input = Device.input

local AutoRotate = {
    enabled = true,
    clockwise = true,
    last_portrait_rotation_mode = nil,
    page_button_rotation_backup = nil,
}

-- KOReader normally changes RPgBack/RPgFwd when the screen rotates.
-- LeadingMangaZoom rotates in the middle of a page-turn operation, so the
-- same physical button can acquire a different meaning before the operation
-- finishes. Keep page-button names stable while this plugin's auto-rotation
-- is active, then restore KOReader's original mappings when it is disabled.
local PAGE_BUTTON_KEYS = {
    "RPgBack",
    "RPgFwd",
    "LPgBack",
    "LPgFwd",
}

local ROTATION_MODES = {
    Screen.DEVICE_ROTATED_CLOCKWISE,
    Screen.DEVICE_ROTATED_UPSIDE_DOWN,
    Screen.DEVICE_ROTATED_COUNTER_CLOCKWISE,
}

function AutoRotate:stabilizePageButtons()
    if self.page_button_rotation_backup then return end
    if not Input or not Input.rotation_map then return end

    self.page_button_rotation_backup = {}

    for _, rotation_mode in ipairs(ROTATION_MODES) do
        local rotation_map = Input.rotation_map[rotation_mode]
        if rotation_map then
            local saved = {}
            self.page_button_rotation_backup[rotation_mode] = saved

            for _, key_name in ipairs(PAGE_BUTTON_KEYS) do
                -- false is a sentinel for an originally absent mapping.
                saved[key_name] = rotation_map[key_name] or false
                rotation_map[key_name] = key_name
            end
        end
    end
end

function AutoRotate:restorePageButtons()
    if not self.page_button_rotation_backup then return end
    if not Input or not Input.rotation_map then
        self.page_button_rotation_backup = nil
        return
    end

    for rotation_mode, saved in pairs(self.page_button_rotation_backup) do
        local rotation_map = Input.rotation_map[rotation_mode]
        if rotation_map then
            for _, key_name in ipairs(PAGE_BUTTON_KEYS) do
                local original = saved[key_name]
                rotation_map[key_name] = original ~= false and original or nil
            end
        end
    end

    self.page_button_rotation_backup = nil
end

function AutoRotate:init(Settings)
    self.enabled = Settings:get("autorotate_enabled")
    self.clockwise = Settings:get("rotate_clockwise")
    self.last_portrait_rotation_mode = Screen:getRotationMode()

    if self.enabled then
        self:stabilizePageButtons()
    end
end

function AutoRotate:reset()
    self:restorePageButtons()
    self.last_portrait_rotation_mode = nil
end

function AutoRotate:onPageUpdate(document, pageno)
    if not self.enabled or not document then return end

    local page_size = document:getNativePageDimensions(pageno)
    if not page_size then return end

    local cur_rotation = Screen:getRotationMode()

    if page_size.w > page_size.h then
        if cur_rotation == Screen.DEVICE_ROTATED_UPRIGHT or
           cur_rotation == Screen.DEVICE_ROTATED_UPSIDE_DOWN then
            self.last_portrait_rotation_mode = cur_rotation
            local new_rotation
            if self.clockwise then
                new_rotation = Screen.DEVICE_ROTATED_CLOCKWISE
            else
                new_rotation = Screen.DEVICE_ROTATED_COUNTER_CLOCKWISE
            end
            UIManager:broadcastEvent(Event:new("SetRotationMode", new_rotation))
        end
    else
        if cur_rotation == Screen.DEVICE_ROTATED_CLOCKWISE or
           cur_rotation == Screen.DEVICE_ROTATED_COUNTER_CLOCKWISE then
            local new_rotation = self.last_portrait_rotation_mode or Screen.DEVICE_ROTATED_UPRIGHT
            UIManager:broadcastEvent(Event:new("SetRotationMode", new_rotation))
        end
    end
end

function AutoRotate:restorePortrait()
    local cur_rotation = Screen:getRotationMode()
    if cur_rotation == Screen.DEVICE_ROTATED_CLOCKWISE or
       cur_rotation == Screen.DEVICE_ROTATED_COUNTER_CLOCKWISE then
        local new_rotation = self.last_portrait_rotation_mode or Screen.DEVICE_ROTATED_UPRIGHT
        Screen:setRotationMode(new_rotation)
        UIManager:broadcastEvent(Event:new("SetRotationMode", new_rotation))
    end
end

function AutoRotate:toggle()
    self.enabled = not self.enabled

    if self.enabled then
        self:stabilizePageButtons()
    else
        self:restorePortrait()
        self:restorePageButtons()
    end

    return self.enabled
end

function AutoRotate:setDirection(clockwise)
    self.clockwise = clockwise
end

return AutoRotate
