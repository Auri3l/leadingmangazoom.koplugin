-- Run from the repository root: luajit tests/run.lua
-- Small KOReader doubles exercise plugin behavior without a device or renderer.
local root = "leadingmangazoom.koplugin/"
local function eq(actual, expected, message)
    assert(actual == expected, (message or "value") .. ": expected " ..
        tostring(expected) .. ", got " .. tostring(actual))
end
local function near(actual, expected)
    assert(math.abs(actual - expected) < 0.000001, tostring(actual) .. " ~= " .. expected)
end
local count = 0
local function test(name, fn)
    fn()
    count = count + 1
    print("ok " .. count .. " - " .. name)
end

local saved, queue, messages = {}, {}, {}
local screen = {
    DEVICE_ROTATED_UPRIGHT = 0, DEVICE_ROTATED_CLOCKWISE = 1,
    DEVICE_ROTATED_UPSIDE_DOWN = 2, DEVICE_ROTATED_COUNTER_CLOCKWISE = 3,
    rotation = 0,
    getWidth = function() return 600 end,
    getHeight = function() return 800 end,
    getRotationMode = function(self) return self.rotation end,
}
local input = { rotation_map = {
    [1] = { RPgFwd = "RPgBack", RPgBack = "RPgFwd", Up = "Left" },
    [2] = { RPgFwd = "RPgBack" }, [3] = {},
} }
local manager = {
    nextTick = function(_, fn) queue[#queue + 1] = fn end,
    unschedule = function(_, fn)
        for i = #queue, 1, -1 do
            if queue[i] == fn then table.remove(queue, i) end
        end
    end,
    broadcastEvent = function(_, event)
        if event.name == "SetRotationMode" then screen.rotation = event[1] end
    end,
    show = function(_, msg) messages[#messages + 1] = msg end,
}
local function flush()
    local pending = queue
    queue = {}
    for _, fn in ipairs(pending) do fn() end
end
package.loaded.device = { screen = screen, input = input, isTouchDevice = function() return true end }
package.loaded["ui/event"] = { new = function(_, name, ...) return { name = name, ... } end }
package.loaded["ui/uimanager"] = manager
package.loaded.gettext = function(s) return s end
package.loaded.datastorage = { getSettingsDir = function() return "." end }
package.loaded.luasettings = { open = function()
    return {
        readSetting = function(_, key) return saved[key] end,
        saveSetting = function(_, key, value) saved[key] = value end,
        flush = function() end,
    }
end }
package.loaded["ui/widget/infomessage"] = { new = function(_, v) return v end }
package.loaded["ui/widget/container/inputcontainer"] = {
    extend = function(_, t) t.__index = t; return t end,
}

local function settings(values)
    return { get = function(_, key)
        if values[key] ~= nil then return values[key] end
        return false
    end }
end

local function reader(pages, start)
    local ui = { zones = {}, post = {}, events = {} }
    ui.document = {
        file = "comic.cbz",
        configurable = { text_wrap = 0, writing_direction = 0, page_scroll = 0 },
        getNativePageDimensions = function(_, n) return pages[n] end,
    }
    ui.view = {
        page_scroll = false,
        state = { zoom = 1, rotation = 0, offset = { x = 0, y = 0 } },
        page_area = { x = 0, y = 0, w = 600, h = 800 },
        visible_area = { x = 0, y = 0, w = 600, h = 800 },
        SetZoomCenter = function(self, x, y) self.center = { x = x, y = y } end,
        PanningUpdate = function(self, dx, dy)
            self.visible_area.x = self.visible_area.x + dx
            self.visible_area.y = self.visible_area.y + dy
            self.pans = (self.pans or 0) + 1
        end,
    }
    ui.zooming = {
        current_page = start or 1, zoom_mode = "page", zoom = 1,
        setZoom = function(self)
            local size = pages[self.current_page]
            if self.zoom_mode == "pageheight" then self.zoom = 800 / size.h
            elseif self.zoom_mode ~= "free" then self.zoom = math.min(600 / size.w, 800 / size.h) end
            ui.view.state.zoom = self.zoom
            ui.view.page_area.w, ui.view.page_area.h = size.w * self.zoom, size.h * self.zoom
            self.recalculations = (self.recalculations or 0) + 1
        end,
    }
    ui.paging = {
        current_page = start or 1, number_of_pages = #pages, calls = 0,
        _gotoPage = function(self, n)
            if n ~= self.current_page and n >= 1 and n <= self.number_of_pages then
                ui:handleEvent({ name = "PageUpdate", n })
            end
            return true
        end,
        onGotoViewRel = function(self, diff, no_page_turn)
            self.calls = self.calls + 1
            if no_page_turn == true then return end
            return self:_gotoPage(self.current_page + diff)
        end,
        setPagePosition = function(self, page) self.position_page = page end,
        getTopPage = function(self) return self.current_page end,
        getTopPosition = function() return 0 end,
    }
    ui.menu = { registerToMainMenu = function() end }
    function ui:registerTouchZones(zones)
        for _, zone in ipairs(zones) do self.zones[zone.id] = zone end
    end
    function ui:registerPostReaderReadyCallback(fn) self.post[#self.post + 1] = fn end
    function ui:handleEvent(event)
        self.events[#self.events + 1] = event
        if event.name == "SetZoomMode" then
            -- Real ReaderZooming only recalculates when the mode changes.
            if self.zooming.zoom_mode ~= event[1] then
                self.zooming.zoom_mode = event[1]
                self.zooming:setZoom()
            end
        elseif event.name == "SetScrollMode" then
            self.view.page_scroll = event[1]
            if not event[1] then self.document.configurable.page_scroll = 0 end
        elseif event.name == "PageUpdate" then
            self.paging.current_page = event[1]
            self.zooming.current_page = event[1]
            self.zooming:setZoom()
            if self.onPage then self.onPage(event[1]) end
        end
    end
    return ui
end

local portrait = { w = 600, h = 800 }
local landscape = { w = 1200, h = 800 }
local function gridReader()
    local ui = reader({ portrait })
    local grid = dofile(root .. "grid.lua")
    grid:init(ui, settings({ grid_enabled = true, page_zoom_enabled = true }))
    return grid, ui
end
local function splitReader(rtl, start)
    local ui = reader({ landscape, landscape, portrait }, start)
    local grid = { rtl_enabled = rtl }
    local split = dofile(root .. "pagesplit.lua")
    split:init(ui, settings({ pagesplit_enabled = true }), grid, function() return true end)
    ui.onPage = function(n) split:onPageUpdate(ui.document, n) end
    split:installNavigation()
    split:onPageUpdate(ui.document, ui.paging.current_page)
    flush()
    return split, ui
end

test("plugin loads its own modules despite Maximum/core name collisions", function()
    saved = {}
    local sentinels = {}
    for _, name in ipairs({ "settings", "menu", "grid", "pagesplit", "autorotate" }) do
        sentinels[name] = { foreign = true }
        package.loaded[name] = sentinels[name]
    end
    local plugin_class = dofile(root .. "main.lua")
    local ui = reader({ landscape })
    local plugin = setmetatable({ ui = ui }, plugin_class)
    ui.onPage = function(n) plugin:onPageUpdate(n) end
    plugin:init()
    plugin:onPageUpdate(1) -- arrives before ReaderReady in KOReader
    plugin:onReaderReady()
    for _, fn in ipairs(ui.post) do fn() end
    eq(screen.rotation, 1, "opening landscape page rotates")
    local menu = {}
    plugin:addToMainMenu(menu)
    for _, item in ipairs(menu.leadingmangazoom.sub_item_table) do
        if item.hold_callback then item.hold_callback() end
    end
    eq(saved.grid_enabled, true, "saving defaults does not crash")
    for name, sentinel in pairs(sentinels) do eq(package.loaded[name], sentinel) end
    plugin:onCloseDocument()
    eq(screen.rotation, 0)
end)

test("unsupported/reflowed documents install no gesture or navigation hooks", function()
    for _, kind in ipairs({ "epub", "reflow" }) do
        local ui = reader({ portrait })
        if kind == "epub" then ui.document.file = "book.epub"; ui.zooming = nil; ui.paging = nil
        else ui.document.configurable.text_wrap = 1 end
        local class = dofile(root .. "main.lua")
        local plugin = setmetatable({ ui = ui }, class)
        plugin:onReaderReady()
        eq(#ui.post, 0)
        eq(next(ui.zones), nil)
        plugin:onCloseDocument()
    end
end)

test("saving either landscape default disables the other", function()
    saved = {}
    local s = dofile(root .. "settings.lua")
    s:set("pagesplit_enabled", true)
    eq(s:get("autorotate_enabled"), false)
    s:set("autorotate_enabled", true)
    eq(s:get("pagesplit_enabled"), false)
end)

test("split defaults win over legacy conflicting rotation defaults", function()
    local rotate = dofile(root .. "autorotate.lua")
    rotate:init(settings({ autorotate_enabled = true }), true)
    eq(rotate.enabled, false)
    eq(rotate.page_button_rotation_backup, nil)
    rotate:reset()
end)

test("gesture overrides precede built-in handlers and fall through when unsupported", function()
    local grid, ui = gridReader()
    local supported = true
    grid:setupTouchZones(function() return supported end)
    local spread = ui.zones.lmz_page_spread
    eq(spread.overrides[1], "spread_gesture")
    eq(ui.zones.lmz_page_pinch.overrides[1], "pinch_gesture")
    eq(ui.zones.lmz_single_tap.overrides[1], "tap_forward")
    assert(#ui.zones.lmz_2tap_q1.overrides == 4)
    eq(spread.handler({ pos = { x = 300, y = 400 } }), true)
    eq(grid.expanded_cell, 0)
    eq(ui.zones.lmz_single_tap.handler(), true)
    supported = false
    eq(spread.handler(), false)
    eq(ui.zones.lmz_2tap_q1.handler(), false)
    eq(ui.zones.lmz_single_tap.handler(), false)
end)

test("all quadrant handlers select their own quadrant; pinch works with page zoom disabled", function()
    local grid, ui = gridReader()
    grid.page_zoom_enabled = false
    grid:setupTouchZones(function() return true end)
    for i = 1, 4 do
        eq(ui.zones["lmz_2tap_q" .. i].handler(), true)
        eq(grid.expanded_cell, i)
        eq(ui.zones.lmz_page_pinch.handler(), true)
        eq(grid.expanded_cell, nil)
    end
end)

test("spread coordinates account for panning and centered-page margins", function()
    local grid, ui = gridReader()
    ui.view.visible_area.x, ui.view.visible_area.y = 100, 50
    ui.view.state.offset = { x = 40, y = 80 }
    grid:expandPage({ pos = { x = 240, y = 280 } })
    near(ui.view.center.x, 600)
    near(ui.view.center.y, 500)
    grid:collapse()
    eq(ui.view.visible_area.x, 100)
    eq(ui.view.visible_area.y, 50)
end)

test("zoom from free mode recalculates and restores the original zoom and scroll state", function()
    local grid, ui = gridReader()
    ui.zooming.zoom_mode, ui.zooming.zoom = "free", 1.3
    ui.view.state.zoom = 1.3
    ui.view.page_scroll = true
    ui.document.configurable.page_scroll = 1
    grid:expand(1)
    eq(ui.view.state.zoom, 2)
    eq(ui.view.page_scroll, false)
    grid:collapse()
    near(ui.view.state.zoom, 1.3)
    eq(ui.view.page_scroll, true)
    eq(ui.document.configurable.page_scroll, 1)
end)

test("RTL restores even if toggled off while zoomed; nil direction is preserved", function()
    for _, direction in ipairs({ 0, false }) do
        local grid, ui = gridReader()
        ui.document.configurable.writing_direction = direction ~= false and direction or nil
        grid.rtl_enabled = true
        grid:expand(1)
        grid:toggleRTL()
        grid:collapse()
        eq(ui.document.configurable.writing_direction, direction ~= false and direction or nil)
    end
end)

test("missing page dimensions do not leave a phantom zoom active", function()
    local grid, ui = gridReader()
    ui.document.getNativePageDimensions = function() return nil end
    eq(grid:expand(1), false)
    eq(grid:expandPage(), false)
    eq(grid.expanded_cell, nil)
    eq(grid.original_zoom_mode, nil)
end)

local function navReader(rtl, pages)
    local ui = reader(pages or { portrait, portrait, portrait })
    local grid = dofile(root .. "grid.lua")
    grid:init(ui, settings({ grid_enabled = true, page_zoom_enabled = true,
        grid_rtl_enabled = rtl, grid_navigation_enabled = true }))
    ui.onPage = function(n) grid:onPageUpdate(n) end
    grid:setupTouchZones(function() return true end)
    grid:installNavigation(function() return true end)
    return grid, ui
end
local function tap(ui, x) return ui.zones.lmz_single_tap.handler({ pos = { x = x, y = 400 } }) end
local function swipe(ui, direction) return ui.zones.lmz_cell_swipe.handler({ direction = direction }) end

test("swipes, side taps and page buttons move between quadrants (issue #7)", function()
    local grid, ui = navReader(false)
    eq(swipe(ui, "west"), false, "swipe without zoom falls through")
    grid:expand(1)
    eq(swipe(ui, "west"), true)
    eq(grid.expanded_cell, 2)
    near(ui.view.center.x, 900)
    near(ui.view.center.y, 400)
    eq(swipe(ui, "north"), true)
    eq(grid.expanded_cell, 4)
    eq(swipe(ui, "north"), true, "edge swipe keeps the zoom")
    eq(grid.expanded_cell, 4)
    eq(swipe(ui, "south"), true)
    eq(grid.expanded_cell, 2)
    eq(tap(ui, 50), true)
    eq(grid.expanded_cell, 1)
    eq(tap(ui, 550), true)
    eq(grid.expanded_cell, 2)
    ui.paging:onGotoViewRel(1, {}) -- physical page button
    eq(grid.expanded_cell, 3)
    ui.paging:onGotoViewRel(-1)
    eq(grid.expanded_cell, 2)
    eq(ui.paging.calls, 0, "quadrant steps do not turn the page")
    eq(ui.zooming.recalculations > 0, true)
    eq(tap(ui, 300), true, "middle tap returns to the page")
    eq(grid.expanded_cell, nil)
    eq(ui.zooming.zoom_mode, "page")
    eq(ui.view.state.zoom, 1)
    grid:reset()
end)

test("RTL quadrant order runs right to left", function()
    local grid, ui = navReader(true)
    grid:expand(2)
    eq(ui.document.configurable.writing_direction, 1)
    eq(swipe(ui, "east"), true)
    eq(grid.expanded_cell, 1)
    eq(tap(ui, 50), true, "left side is forward in RTL")
    eq(grid.expanded_cell, 4)
    ui.paging:onGotoViewRel(1)
    eq(grid.expanded_cell, 3)
    eq(swipe(ui, "west"), true)
    eq(grid.expanded_cell, 4)
    grid:collapse()
    eq(ui.document.configurable.writing_direction, 0)
    -- KOReader's inverse reading order also means right-to-left.
    grid.rtl_enabled = false
    ui.view.inverse_reading_order = true
    grid:expand(2)
    ui.paging:onGotoViewRel(1)
    eq(grid.expanded_cell, 1)
    grid:reset()
end)

test("stepping past the last quadrant continues on the next page", function()
    local grid, ui = navReader(false)
    grid:expand(4)
    ui.paging:onGotoViewRel(1)
    eq(ui.paging.current_page, 2)
    eq(grid.expanded_cell, nil, "zoom is released for the page turn")
    eq(ui.zooming.zoom_mode, "page")
    flush()
    eq(grid.expanded_cell, 1)
    eq(grid.original_page, 2)
    eq(grid.original_zoom_mode, "page")
    eq(tap(ui, 50), true, "backward from the first quadrant")
    eq(ui.paging.current_page, 1)
    flush()
    eq(grid.expanded_cell, 4)
    grid:collapse()
    -- No page left: stay on the page without zooming again.
    ui.paging.current_page, ui.zooming.current_page = 3, 3
    grid:expand(4)
    eq(swipe(ui, "west"), true)
    flush()
    eq(ui.paging.current_page, 3)
    eq(grid.expanded_cell, nil)
    grid:reset()
end)

test("continuation stops on split spreads and when navigation is off", function()
    local grid, ui = navReader(false)
    grid.can_continue = function() return false end
    grid:expand(4)
    swipe(ui, "west")
    flush()
    eq(ui.paging.current_page, 2)
    eq(grid.expanded_cell, nil)
    grid.can_continue = nil
    grid:toggleNavigation()
    grid:expand(1)
    eq(swipe(ui, "west"), false, "KOReader handles swipes")
    eq(tap(ui, 550), true)
    eq(grid.expanded_cell, nil, "any tap returns when navigation is off")
    grid:expand(1)
    ui.paging:onGotoViewRel(1)
    eq(ui.paging.current_page, 3, "page buttons turn the page")
    eq(grid.expanded_cell, nil, "page change releases the zoom")
    grid:reset()
end)

test("page changes from elsewhere release the zoom without restoring an old pan", function()
    local grid, ui = navReader(false)
    ui.view.visible_area.y = 40
    grid:expand(3)
    ui.view.pans = 0
    ui:handleEvent({ name = "PageUpdate", 2 })
    eq(grid.expanded_cell, nil)
    eq(ui.zooming.zoom_mode, "page")
    eq(ui.view.pans, 0)
    grid:expand(1)
    ui:handleEvent({ name = "PageUpdate", 2 }) -- redraw of the same page
    eq(grid.expanded_cell, 1)
    grid:reset()
end)

test("zoom levels leave room for a visible footer", function()
    local grid, ui = gridReader()
    ui.view.footer_visible = true
    ui.view.footer = { settings = {}, getHeight = function() return 40 end }
    grid:expand(1)
    near(ui.zooming.zoom, 1.9)
    grid:collapse()
    ui.view.footer.settings.reclaim_height = true
    grid:expand(1)
    near(ui.zooming.zoom, 2)
    grid:reset()
end)

test("navigation wrappers unwind in order on close", function()
    local ui = reader({ landscape, portrait })
    local grid = dofile(root .. "grid.lua")
    grid:init(ui, settings({ grid_enabled = true, grid_navigation_enabled = true }))
    local split = dofile(root .. "pagesplit.lua")
    split:init(ui, settings({ pagesplit_enabled = true }), grid, function() return true end)
    local original = ui.paging.onGotoViewRel
    split:installNavigation()
    local split_wrapper = ui.paging.onGotoViewRel
    grid:installNavigation(function() return true end)
    assert(ui.paging.onGotoViewRel ~= split_wrapper)
    grid:reset()
    eq(ui.paging.onGotoViewRel, split_wrapper)
    split:reset()
    eq(ui.paging.onGotoViewRel, original)
end)

test("LTR split traverses halves, pages, portrait exit and backward re-entry", function()
    local split, ui = splitReader(false)
    eq(split.current_half, "left")
    eq(ui.zooming.zoom_mode, "pageheight")
    ui.paging:onGotoViewRel(1, {}) -- physical key's second argument is a table
    flush()
    eq(ui.paging.current_page, 1)
    eq(split.current_half, "right")
    eq(ui.view.visible_area.x, 600)
    ui.paging:onGotoViewRel(1)
    flush()
    eq(ui.paging.current_page, 2)
    eq(split.current_half, "left")
    ui.paging:onGotoViewRel(1)
    ui.paging:onGotoViewRel(1)
    flush()
    eq(ui.paging.current_page, 3)
    eq(ui.zooming.zoom_mode, "page")
    eq(split.current_half, nil)
    ui.paging:onGotoViewRel(-1)
    flush()
    eq(ui.paging.current_page, 2)
    eq(split.current_half, "right")
    split:restoreZoom(); split:reset()
end)

test("RTL split supports reverse navigation between adjacent spreads", function()
    local split, ui = splitReader(true)
    eq(split.current_half, "right")
    ui.paging:onGotoViewRel(1)
    eq(split.current_half, "left")
    ui.paging:onGotoViewRel(1)
    eq(ui.paging.current_page, 2)
    eq(split.current_half, "right")
    ui.paging:onGotoViewRel(-1)
    eq(ui.paging.current_page, 1)
    eq(split.current_half, "left")
    ui.paging:onGotoViewRel(-1)
    eq(split.current_half, "right")
    ui.paging:onGotoViewRel(-1)
    eq(ui.paging.current_page, 1)
    eq(split.current_half, "right")
    split:restoreZoom(); split:reset()
end)

test("redraw keeps the current half and cancels outdated pans", function()
    local split, ui = splitReader(false)
    ui.paging:onGotoViewRel(1)
    ui:handleEvent({ name = "PageUpdate", 1 })
    eq(split.current_half, "right")
    eq(#queue, 1)
    split:toggle()
    local pans = ui.view.pans
    flush()
    eq(ui.view.pans, pans)
    eq(ui.zooming.zoom_mode, "page")
    split:reset()
end)

test("search probes bypass split navigation and teardown restores original handler", function()
    local split, ui = splitReader(false)
    eq(ui.paging:onGotoViewRel(1, true), nil)
    eq(split.current_half, "left")
    eq(ui.paging.calls, 1)
    local original = split.original_navigation
    split:restoreZoom(); split:reset()
    eq(ui.paging.onGotoViewRel, original)
    eq(#queue, 0)
end)

test("split restores an existing free zoom and continuous view", function()
    local ui = reader({ landscape })
    ui.zooming.zoom_mode, ui.zooming.zoom = "free", 1.5
    ui.view.page_scroll = true
    ui.document.configurable.page_scroll = 1
    local split = dofile(root .. "pagesplit.lua")
    split:init(ui, settings({ pagesplit_enabled = true }), {}, function() return true end)
    split:onPageUpdate(ui.document, 1)
    eq(ui.view.page_scroll, false)
    split:toggle()
    eq(ui.zooming.zoom_mode, "free")
    near(ui.zooming.zoom, 1.5)
    eq(ui.view.page_scroll, true)
    eq(ui.document.configurable.page_scroll, 1)
    split:reset()
end)

test("auto-rotation preserves the physical-button fix and restores missing mappings", function()
    local rotate = dofile(root .. "autorotate.lua")
    rotate:init(settings({ autorotate_enabled = true, rotate_clockwise = true }))
    eq(input.rotation_map[1].RPgFwd, "RPgFwd")
    eq(input.rotation_map[1].Up, "Left")
    rotate:reset()
    eq(input.rotation_map[1].RPgFwd, "RPgBack")
    eq(input.rotation_map[3].RPgFwd, nil)
end)

-- Free page zoom for newspapers and magazines (Euphoriyy/KOReader.patches#26).
local function freeReader()
    local grid, ui = gridReader()
    -- PanningUpdate clamps to the page like ReaderView's offsetWithin.
    ui.view.PanningUpdate = function(self, dx, dy)
        local a, p = self.visible_area, self.page_area
        a.x = math.max(0, math.min(a.x + dx, p.w - a.w))
        a.y = math.max(0, math.min(a.y + dy, p.h - a.h))
        self.pans = (self.pans or 0) + 1
    end
    grid:setupTouchZones(function() return true end)
    return grid, ui
end
local function spread(span, x, y)
    return { pos = { x = x or 300, y = y or 400 }, start_span = 100, span = span }
end

test("spread zooms by finger distance and repeats up to a ceiling", function()
    local grid, ui = freeReader()
    eq(ui.zones.lmz_page_spread.handler(spread(300)), true)
    eq(grid.expanded_cell, 0)
    near(ui.view.state.zoom, 3)
    eq(ui.zones.lmz_page_spread.handler(spread(200)), true)
    near(ui.view.state.zoom, 6)
    ui.zones.lmz_page_spread.handler(spread(500))
    near(ui.view.state.zoom, 8, "zoom is capped at 8x the fitted page")
    -- A barely-open spread still zooms noticeably on the first gesture.
    grid:collapse()
    ui.zones.lmz_page_spread.handler(spread(105))
    near(ui.view.state.zoom, 1.25)
end)

test("pinch zooms out step by step and returns to the page near fit", function()
    local grid, ui = freeReader()
    ui.zones.lmz_page_spread.handler(spread(400))
    eq(ui.zones.lmz_page_pinch.handler(spread(50)), true)
    near(ui.view.state.zoom, 2)
    eq(grid.expanded_cell, 0)
    ui.zones.lmz_page_pinch.handler(spread(40))
    eq(grid.expanded_cell, nil)
    eq(ui.zooming.zoom_mode, "page")
    near(ui.view.state.zoom, 1)
end)

test("drags pan the zoomed page freely in both axes on release", function()
    local grid, ui = freeReader()
    ui.zones.lmz_page_spread.handler(spread(400, 0, 0))
    ui.view.visible_area.x, ui.view.visible_area.y = 600, 800
    local pans = ui.view.pans or 0
    -- Pan events only record the drag; nothing redraws until release.
    eq(ui.zones.lmz_page_pan.handler({ relative = { x = -100, y = 0 } }), true)
    eq(ui.zones.lmz_page_pan.handler({ relative = { x = -150, y = -200 } }), true)
    eq(ui.view.pans or 0, pans)
    eq(ui.zones.lmz_page_pan_release.handler({}), true)
    eq(ui.view.visible_area.x, 750)
    eq(ui.view.visible_area.y, 1000)
    -- Direction changes keep the position instead of jumping to a corner.
    ui.zones.lmz_page_pan.handler({ relative = { x = 50, y = 120 } })
    ui.zones.lmz_page_pan_release.handler({})
    eq(ui.view.visible_area.x, 700)
    eq(ui.view.visible_area.y, 880)
    eq(ui.zooming.zoom_mode, "free")
    eq(ui.paging.current_page, 1)
end)

test("swipes pan a free page zoom instead of stepping or turning pages", function()
    local grid, ui = freeReader()
    ui.zones.lmz_page_spread.handler(spread(400, 0, 0))
    ui.view.visible_area.x, ui.view.visible_area.y = 600, 800
    local calls = ui.paging.calls
    ui.zones.lmz_page_pan.handler({ relative = { x = -10, y = 0 } })
    eq(ui.zones.lmz_cell_swipe.handler({
        direction = "northwest", pos = { x = 500, y = 600 }, end_pos = { x = 200, y = 200 },
    }), true)
    eq(ui.view.visible_area.x, 900)
    eq(ui.view.visible_area.y, 1200)
    eq(ui.paging.calls, calls)
    eq(grid.pan_delta, nil, "a swipe discards the drag that preceded it")
    eq(ui.zones.lmz_page_pan_release.handler({}), false)
end)

test("pans fall through outside free page zoom", function()
    local grid, ui = freeReader()
    eq(ui.zones.lmz_page_pan.handler({ relative = { x = 10, y = 10 } }), false)
    eq(ui.zones.lmz_page_pan_release.handler({}), false)
    grid:expand(1)
    eq(ui.zones.lmz_page_pan.handler({ relative = { x = 10, y = 10 } }), false)
    eq(ui.zones.lmz_page_pan.overrides[1], "paging_pan")
    eq(ui.zones.lmz_page_pan_release.overrides[1], "paging_pan_release")
end)

test("spread on a quadrant switches to free zoom and still restores the page", function()
    local grid, ui = freeReader()
    ui.zooming.zoom_mode, ui.zooming.zoom, ui.view.state.zoom = "free", 1.3, 1.3
    grid:expand(2)
    near(ui.view.state.zoom, 2)
    eq(ui.zones.lmz_page_spread.handler(spread(150)), true)
    eq(grid.expanded_cell, 0)
    near(ui.view.state.zoom, 3)
    grid:collapse()
    near(ui.view.state.zoom, 1.3)
    eq(ui.zooming.zoom_mode, "free")
end)

test("free zoom keeps the zoom menu's genus valid (koptoptions crash)", function()
    local grid, ui = freeReader()
    -- ReaderZooming's mapping: "free" has no genus.
    local genus = { page = 4, content = 3, columns = 2, rows = 1, manual = 0 }
    ui.zooming.mode_to_combo = function(_, mode)
        mode = mode or "pagewidth"
        local g, t = mode:match("^(page)(%l*)$")
        if not g then g, t = mode:match("^(content)(%l*)$") end
        g = g or mode
        return genus[g], ({ [""] = 2, width = 1, height = 0 })[t or ""]
    end
    local config = ui.document.configurable
    for _, start in ipairs({ "page", "contentwidth", "free" }) do
        grid:collapse()
        ui.zooming.zoom_mode = start
        ui.zones.lmz_page_spread.handler(spread(300))
        eq(ui.zooming.zoom_mode, "free")
        assert(type(config.zoom_mode_genus) == "number", start .. " left a nil genus")
        grid:expand(1)
    end
    grid:collapse()
    ui.zooming.zoom_mode = "contentwidth"
    grid:expand(3)
    eq(config.zoom_mode_genus, 3)
    eq(config.zoom_mode_type, 1)
end)

test("choosing a zoom mode while zoomed ends the zoom without overriding it", function()
    local grid, ui = freeReader()
    ui.view.page_scroll = true
    ui.zones.lmz_page_spread.handler(spread(300))
    grid:onZoomModeUpdate("free")
    eq(grid.expanded_cell, 0, "our own free mode is ignored")
    ui.zooming.zoom_mode = "pagewidth"
    grid:onZoomModeUpdate("pagewidth")
    eq(grid.expanded_cell, nil)
    eq(grid.original_zoom_mode, nil)
    flush()
    eq(ui.view.page_scroll, true, "continuous view comes back")
    -- Nothing is left to restore over the user's choice.
    grid:collapse()
    eq(ui.zooming.zoom_mode, "page")
    eq(ui.zones.lmz_page_pan.handler({ relative = { x = 1, y = 1 } }), false)
    grid:onZoomModeUpdate("page")
end)

test("closing or autosaving while zoomed keeps the reader's zoom mode", function()
    saved = {}
    local plugin_class = dofile(root .. "main.lua")
    local ui = reader({ portrait })
    local doc = {}
    ui.doc_settings = { saveSetting = function(_, k, v) doc[k] = v end }
    local plugin = setmetatable({ ui = ui }, plugin_class)
    plugin:init()
    plugin:onReaderReady()
    for _, fn in ipairs(ui.post) do fn() end
    ui.zooming.zoom_mode = "contentwidth"
    -- ReaderZooming saves first, then the plugin.
    doc.zoom_mode = ui.zooming.zoom_mode
    plugin:onSaveSettings()
    eq(doc.zoom_mode, "contentwidth", "nothing changes when not zoomed")
    ui.zones.lmz_2tap_q1.handler()
    doc.zoom_mode = ui.zooming.zoom_mode
    eq(doc.zoom_mode, "free")
    plugin:onSaveSettings()
    eq(doc.zoom_mode, "contentwidth")
    plugin:onCloseDocument()
    eq(ui.zooming.zoom_mode, "contentwidth")
end)

-- Desktop controls (Linux/macOS/Windows builds): mouse wheel and keyboard.
local function wheelReader()
    local grid, ui = freeReader()
    local inner_calls = 0
    ui.paging.onPan = function() inner_calls = inner_calls + 1; return true end
    grid:installWheel(function() return true end)
    local function wheel(notches, x)
        return ui.paging:onPan(nil, { mousewheel_direction = notches, relative = { x = 50 * (x or 0), y = 100 * notches } })
    end
    return grid, ui, wheel, function() return inner_calls end
end
local function hold(mods)
    package.loaded.device.input.modifiers = mods or {}
end

test("Ctrl + wheel zooms in and out around the view", function()
    local grid, ui, wheel, inner = wheelReader()
    hold({ Ctrl = true })
    eq(wheel(1), true)
    eq(grid.expanded_cell, 0)
    near(ui.view.state.zoom, 1.25)
    wheel(2)
    near(ui.view.state.zoom, 1.25 ^ 3)
    wheel(-2)
    near(ui.view.state.zoom, 1.25)
    wheel(-1)
    eq(grid.expanded_cell, nil, "zooming back to the page returns to the page view")
    eq(ui.zooming.zoom_mode, "page")
    eq(wheel(-1), true, "zooming out of the page view does nothing")
    eq(grid.expanded_cell, nil)
    eq(inner(), 0, "Ctrl + wheel never turns pages")
    grid.page_zoom_enabled = false
    wheel(1)
    eq(inner(), 1, "with Page Zoom off, KOReader handles the wheel")
    hold()
    grid:reset()
end)

test("the wheel scrolls a free zoom; elsewhere it keeps KOReader's behaviour", function()
    local grid, ui, wheel, inner = wheelReader()
    hold()
    wheel(-1)
    eq(inner(), 1, "page view: wheel turns pages as before")
    ui.zones.lmz_page_spread.handler(spread(400, 0, 0))
    ui.view.visible_area.x, ui.view.visible_area.y = 600, 800
    wheel(-1)
    eq(ui.view.visible_area.y, 960, "wheel down scrolls down by a fifth of the view")
    wheel(2)
    eq(ui.view.visible_area.y, 640)
    wheel(0, 1)
    eq(ui.view.visible_area.x, 720, "horizontal wheel scrolls sideways")
    hold({ Shift = true })
    wheel(-1)
    eq(ui.view.visible_area.x, 840, "Shift + wheel scrolls sideways")
    eq(ui.view.visible_area.y, 640)
    hold()
    eq(inner(), 1)
    grid:collapse()
    grid:expand(1)
    wheel(-1)
    eq(inner(), 2, "quadrant zoom: wheel still steps through quadrants")
    grid:reset()
    eq(ui.paging.onPan ~= grid.wheel_wrapper, true, "reset unwraps the wheel handler")
end)

test("Ctrl +, Ctrl - and Ctrl 0 zoom from the keyboard", function()
    saved = {}
    package.loaded.device.hasKeyboard = function() return true end
    local plugin_class = dofile(root .. "main.lua")
    local ui = reader({ portrait })
    local plugin = setmetatable({ ui = ui }, plugin_class)
    plugin:init()
    package.loaded.device.hasKeyboard = nil
    local keys = plugin.key_events
    eq(keys.LMZZoomIn[1][2], "=")
    eq(keys.LMZZoomOut[1][2], "-")
    eq(keys.LMZZoomReset[1][2], "0")
    eq(plugin:onLMZZoom("in"), false, "nothing before the reader is ready")
    plugin:onReaderReady()
    for _, fn in ipairs(ui.post) do fn() end
    eq(plugin:onLMZZoom("reset"), false, "Ctrl 0 on the page view is left to others")
    eq(plugin:onLMZZoom("in"), true)
    near(ui.view.state.zoom, 1.25)
    plugin:onLMZZoom("in")
    near(ui.view.state.zoom, 1.5625)
    plugin:onLMZZoom("out")
    near(ui.view.state.zoom, 1.25)
    eq(plugin:onLMZZoom("reset"), true)
    eq(ui.zooming.zoom_mode, "page")
    plugin:onCloseDocument()
end)

test("Ctrl + wheel keeps the spot under the mouse pointer in place", function()
    local grid, ui, wheel = wheelReader()
    grid.pointerPosition = function() return { x = 100, y = 200 } end
    hold({ Ctrl = true })
    -- Page view, zoom 1, nothing panned: page point (100, 200) is under the pointer.
    wheel(1)
    near(ui.view.state.zoom, 1.25)
    -- (125, 250) at the new zoom must land at screen (100, 200): the view's
    -- top-left is (25, 50), so its center is (25 + 300, 50 + 400).
    near(ui.view.center.x, 325)
    near(ui.view.center.y, 450)
    -- Already zoomed and panned: the same rule holds.
    ui.view.visible_area.x, ui.view.visible_area.y = 40, 60
    wheel(1)
    near(ui.view.state.zoom, 1.5625)
    -- Point under the pointer was (140, 260) at 1.25, (175, 325) at 1.5625.
    near(ui.view.center.x, 175 - 100 + 300)
    near(ui.view.center.y, 325 - 200 + 400)
    -- Keyboard zoom still centers on the view.
    grid.pointerPosition = function() error("keyboard must not use the pointer") end
    grid:zoomStepIn()
    hold()
    grid:reset()
end)

test("pointer lookup is skipped off desktop and the wheel then centers", function()
    local grid, ui, wheel = wheelReader()
    eq(grid:pointerPosition(), nil, "not an SDL device")
    hold({ Ctrl = true })
    wheel(1)
    near(ui.view.center.x, 375) -- (300, 400) * 1.25
    near(ui.view.center.y, 500)
    hold()
    grid:reset()
end)

test("keypad +, - and 0 are mapped on desktop without overriding existing keys", function()
    local dev = package.loaded.device
    dev.isSDL = function() return true end
    dev.input.event_map = { [0x40000056] = "Existing" }
    local plugin = setmetatable({ ui = reader({ portrait }) }, dofile(root .. "main.lua"))
    plugin:init()
    eq(dev.input.event_map[0x40000057], "+")
    eq(dev.input.event_map[0x40000062], "0")
    eq(dev.input.event_map[0x40000056], "Existing", "an already-mapped code is left alone")
    dev.isSDL = nil
    dev.input.event_map = nil
    local other = setmetatable({ ui = reader({ portrait }) }, dofile(root .. "main.lua"))
    other:init() -- e-readers: nothing to map, nothing breaks
end)

-- Self-updater (issue: update the plugin without a plugin store).
local Updater = dofile(root .. "updater.lua")
local function release(extra)
    local r = {
        tag_name = "v1.6.0", draft = false, prerelease = false, html_url = "https://example/rel",
        body = "## What's new\n- **Bold** and `code` and [a link](https://x)\n\n> quote",
        assets = {
            { name = "notes.txt", browser_download_url = "https://example/notes.txt" },
            { name = "leadingmangazoom.koplugin.zip", browser_download_url = "https://example/lmz.zip" },
        },
    }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end

test("updater compares versions numerically", function()
    eq(Updater.isNewer("1.10.0", "1.9.9"), true)
    eq(Updater.isNewer("v1.5.0", "1.4.1"), true)
    eq(Updater.isNewer("1.4.1", "1.4.1"), false)
    eq(Updater.isNewer("1.4", "1.4.0"), false)
    eq(Updater.isNewer("1.4.0.1", "1.4"), true)
    eq(Updater.isNewer("1.3.9", "1.4.0"), false)
    eq(Updater.metaVersion('local x\n    version = "1.5.0",\n'), "1.5.0")
end)

test("updater picks the plugin zip from a final release only", function()
    local r = Updater.parseRelease(release())
    eq(r.version, "1.6.0")
    eq(r.url, "https://example/lmz.zip")
    eq(r.page, "https://example/rel")
    eq(Updater.parseRelease(release({ draft = true })), nil)
    eq(Updater.parseRelease(release({ prerelease = true })), nil)
    local none, why = Updater.parseRelease(release({ assets = {} }))
    eq(none, nil)
    assert(why:find("leadingmangazoom.koplugin.zip", 1, true))
    eq(Updater.parseRelease(nil), nil)
    eq(Updater.parseRelease({ message = "Not Found" }), nil)
end)

test("release notes are shown without Markdown and kept short", function()
    local notes = Updater.shortNotes(release().body)
    eq(notes, "What's new\n- Bold and code and a link\n\nquote")
    local long = Updater.shortNotes(string.rep("word ", 200), 50)
    assert(#long <= 54, "cut to the limit")
    assert(long:sub(-3) == "\226\128\166", "ends with an ellipsis")
    -- Never cut inside a multi-byte character.
    for limit = 29, 33 do
        local turkish = Updater.shortNotes(string.rep("\196\159", 40), limit)
        local body = turkish:gsub(" \226\128\166$", "")
        assert(body:gsub("\196\159", "") == "", "cut at " .. limit .. " broke a character")
        assert(#body > 0 and #body <= limit)
    end
end)

test("only a clean plugin archive is accepted", function()
    local function entries(list, mode)
        local t = {}
        for _, p in ipairs(list) do t[#t + 1] = { path = p, mode = p:sub(-1) == "/" and "directory" or (mode or "file") } end
        return t
    end
    local good = { "leadingmangazoom.koplugin/", "leadingmangazoom.koplugin/_meta.lua",
        "leadingmangazoom.koplugin/main.lua", "leadingmangazoom.koplugin/grid.lua" }
    eq(Updater.validateEntries(entries(good)), true)
    local function rejects(list, mode, fragment)
        local ok, why = Updater.validateEntries(entries(list, mode))
        eq(ok, nil)
        assert(why:find(fragment, 1, true), why)
    end
    rejects({ good[2], good[3] }, nil, "missing grid.lua")
    rejects({ good[2], good[3], good[4], "other.koplugin/x.lua" }, nil, "unexpected folder")
    rejects({ good[2], good[3], good[4], "leadingmangazoom.koplugin/../../evil.lua" }, nil, "unsafe path")
    rejects({ "/leadingmangazoom.koplugin/main.lua" }, nil, "unsafe path")
    rejects({ good[2], good[3], good[4], "leadingmangazoom.koplugin/link" }, "link", "unexpected entry")
    -- GitHub's "Source code" zip has the wrong top folder.
    rejects({ "leadingmangazoom.koplugin-1.6.0/leadingmangazoom.koplugin/main.lua" }, nil, "unexpected folder")
end)

-- A small fake KOReader for the dialogs and network.
local function updaterHarness(opts)
    opts = opts or {}
    local shown, scheduled = {}, {}
    local ui = {
        show = function(_, w) shown[#shown + 1] = w end,
        scheduleIn = function(_, _, fn) scheduled[#scheduled + 1] = fn end,
        restartKOReader = function() shown[#shown + 1] = { restarted = true } end,
    }
    local net = { connected = opts.connected ~= false, waited = 0 }
    package.loaded["ui/uimanager"] = setmetatable(ui, { __index = manager })
    package.loaded["ui/widget/confirmbox"] = { new = function(_, v) v.confirm = true; return v end }
    package.loaded["ui/network/manager"] = {
        isConnected = function() return net.connected end,
        runWhenConnected = function(_, fn) net.waited = net.waited + 1; net.pending = fn end,
    }
    local store = {}
    local settings = {
        get = function(_, k) return store[k] end,
        set = function(_, k, v) store[k] = v end,
    }
    local u = dofile(root .. "updater.lua")
    u:init(root, settings)
    local function run()
        while #scheduled > 0 do table.remove(scheduled, 1)() end
    end
    return u, shown, run, net, store
end
local function restoreManager() package.loaded["ui/uimanager"] = manager end

test("checking says up to date, or offers the newer version with its notes", function()
    local u, shown, run, _, store = updaterHarness()
    local meta = io.open(root .. "_meta.lua"):read("*a")
    local installed = Updater.metaVersion(meta)
    u.fetchLatest = function() return Updater.parseRelease(release({ tag_name = "v" .. installed })) end
    u:check()
    run()
    assert(shown[#shown].text:find("up to date", 1, true), shown[#shown].text)
    assert(type(store.last_update_check) == "number")
    u.fetchLatest = function() return Updater.parseRelease(release({ tag_name = "v99.0.0" })) end
    local installed_with = nil
    u.install = function(_, rel) installed_with = rel end
    u:check()
    run()
    local box = shown[#shown]
    eq(box.confirm, true)
    assert(box.text:find("v99.0.0 is available", 1, true))
    assert(box.text:find("You have v" .. installed, 1, true))
    assert(box.text:find("Bold and code", 1, true), "notes are shown")
    box.ok_callback()
    eq(installed_with.version, "99.0.0")
    u.fetchLatest = function() return nil, "the connection timed out" end
    u:check()
    run()
    assert(shown[#shown].text:find("timed out", 1, true))
    assert(shown[#shown].text:find("github.com/Auri3l/leadingmangazoom.koplugin/releases", 1, true))
    restoreManager()
end)

test("checking waits for Wi-Fi instead of failing", function()
    local u, shown, run, net = updaterHarness({ connected = false })
    local fetched = 0
    u.fetchLatest = function() fetched = fetched + 1; return nil, "x" end
    u:check()
    run()
    eq(fetched, 0)
    eq(net.waited, 1)
    net.connected = true
    net.pending()
    run()
    eq(fetched, 1)
    restoreManager()
end)

test("install downloads, unpacks and offers a restart; failures say why", function()
    local u, shown, run = updaterHarness()
    package.loaded.device.canRestart = function() return true end
    local steps = {}
    u.download = function(_, url) steps[#steps + 1] = "download " .. url; return "/tmp/x.zip" end
    u.unpack = function(_, path, v) steps[#steps + 1] = "unpack " .. v; return v end
    u:install(Updater.parseRelease(release()))
    run()
    eq(steps[1], "download https://example/lmz.zip")
    eq(steps[2], "unpack 1.6.0")
    local box = shown[#shown]
    assert(box.text:find("updated to v1.6.0", 1, true))
    box.ok_callback()
    eq(shown[#shown].restarted, true)
    u.unpack = function() return nil, "the download is damaged (bad)" end
    u:install(Updater.parseRelease(release()))
    run()
    assert(shown[#shown].text:find("Update failed", 1, true))
    assert(shown[#shown].text:find("damaged", 1, true))
    package.loaded.device.canRestart = nil
    restoreManager()
end)

test("automatic checks are opt-in, daily, and never turn Wi-Fi on", function()
    local u, shown, run, net, store = updaterHarness()
    local fetched = 0
    u.fetchLatest = function() fetched = fetched + 1; return Updater.parseRelease(release({ tag_name = "v99.0.0" })) end
    u:maybeAutoCheck(); run()
    eq(fetched, 0, "off by default")
    u:setAutoCheck(true)
    u:maybeAutoCheck(); run()
    eq(fetched, 1)
    eq(shown[#shown].confirm, true, "offers the new version")
    u:maybeAutoCheck(); run()
    eq(fetched, 1, "not again within a day")
    store.last_update_check = os.time() - 25 * 3600
    net.connected = false
    u:maybeAutoCheck(); run()
    eq(fetched, 1, "not when offline")
    eq(net.waited, 0, "and never asks to turn Wi-Fi on")
    restoreManager()
end)

test("Updates menu is there even when the document isn't supported", function()
    saved = {}
    local plugin = setmetatable({ ui = reader({ portrait }) }, dofile(root .. "main.lua"))
    plugin:init()
    plugin.ui.document.file = "book.epub"
    local menu = {}
    plugin:addToMainMenu(menu)
    local root_item = menu.leadingmangazoom
    eq(root_item.enabled_func, nil, "the menu itself stays enabled")
    local updates, about, grid
    for _, item in ipairs(root_item.sub_item_table) do
        if item.text_func then updates = item end
        if item.text == "About" then about = item end
        if item.text == "Enable Grid Mode" then grid = item end
    end
    assert(updates.text_func():find("^Updates %(v%d"), updates.text_func())
    eq(updates.enabled_func, nil)
    eq(about.enabled_func, nil)
    eq(grid.enabled_func(), false, "reading features still need a supported file")
    eq(root_item.sub_item_table[#root_item.sub_item_table], about, "About stays last")
end)

-- Double tap to zoom (issue #12).
test("double tap zooms in on the tapped spot at the chosen level, and back out", function()
    local grid, ui = freeReader()
    local dt = ui.zones.lmz_double_tap
    eq(dt.handler({ pos = { x = 150, y = 200 } }), false, "off by default: KOReader's double tap runs")
    grid.double_tap_enabled = true
    eq(dt.handler({ pos = { x = 150, y = 200 } }), true)
    eq(grid.expanded_cell, 0)
    near(ui.view.state.zoom, 2, "default level is twice the page")
    near(ui.view.center.x, 300) -- (150, 200) at 2x, centered
    near(ui.view.center.y, 400)
    eq(dt.handler({ pos = { x = 10, y = 10 } }), true)
    eq(grid.expanded_cell, nil, "double tap again returns to the page")
    eq(ui.zooming.zoom_mode, "page")
    grid.double_tap_level = 3
    dt.handler({ pos = { x = 300, y = 400 } })
    near(ui.view.state.zoom, 3)
    grid:collapse()
    grid:expand(2)
    dt.handler({ pos = { x = 300, y = 400 } })
    eq(grid.expanded_cell, nil, "also leaves a quadrant zoom")
    grid.double_tap_level = 1.5
    dt.handler({ pos = { x = 300, y = 400 } })
    near(ui.view.state.zoom, 1.5, "levels below the spread minimum are honoured")
end)

test("double-tap zoom turns KOReader's double taps on only while it is on", function()
    saved = {}
    local plugin = setmetatable({ ui = reader({ portrait }) }, dofile(root .. "main.lua"))
    plugin:init()
    plugin:onReaderReady()
    for _, fn in ipairs(plugin.ui.post) do fn() end
    local input = package.loaded.device.input
    eq(plugin.ui.disable_double_tap, true, "off: KOReader's default (double taps off)")
    eq(input.disable_double_tap, true)
    local grid_menu = {}
    plugin:addToMainMenu(grid_menu)
    local entry
    for _, item in ipairs(grid_menu.leadingmangazoom.sub_item_table) do
        if item.text_func and item.text_func():find("^Double%-tap to zoom") then entry = item end
    end
    assert(entry, "menu entry")
    local sub = entry.sub_item_table_func()
    sub[1].callback()
    eq(saved.double_tap_zoom, true, "turning it on is remembered")
    eq(plugin.ui.disable_double_tap, false, "on: double taps reach the plugin")
    eq(input.disable_double_tap, false)
    eq(entry.text_func(), "Double-tap to zoom (2×)")
    local levels = {}
    for i = 2, #sub do levels[#levels + 1] = sub[i].text end
    eq(table.concat(levels, ","), "Zoom level: 1.5×,Zoom level: 2×,Zoom level: 2.5×,Zoom level: 3×,Zoom level: 4×")
    sub[5].callback()
    eq(saved.double_tap_zoom_level, 3, "the level is remembered")
    eq(entry.text_func(), "Double-tap to zoom (3×)")
    sub[1].hold_callback()
    eq(saved.double_tap_zoom, true, "hold sets the default")
    sub[1].callback()
    eq(plugin.ui.disable_double_tap, true, "off again: back to KOReader's setting")
    -- Someone who turned double taps on in KOReader keeps them.
    _G.G_reader_settings = { isFalse = function(_, k) return k == "disable_double_tap" end }
    plugin:applyDoubleTap()
    eq(plugin.ui.disable_double_tap, false)
    _G.G_reader_settings = nil
    -- Not for unsupported books.
    sub[1].callback()
    plugin.ui.document.file = "book.epub"
    plugin:applyDoubleTap()
    eq(plugin.ui.disable_double_tap, true)
    input.disable_double_tap = nil
    plugin:onCloseDocument()
end)

test("double-tap zoom is still on after closing and reopening a book", function()
    saved = {}
    local function open_book()
        local plugin = setmetatable({ ui = reader({ portrait }) }, dofile(root .. "main.lua"))
        plugin:init()
        plugin:onReaderReady()
        for _, fn in ipairs(plugin.ui.post) do fn() end
        local menu = {}
        plugin:addToMainMenu(menu)
        for _, item in ipairs(menu.leadingmangazoom.sub_item_table) do
            if item.text_func and item.text_func():find("^Double%-tap to zoom") then
                return plugin, item.sub_item_table_func()
            end
        end
    end
    local first, sub = open_book()
    sub[1].callback()
    sub[4].callback() -- 2.5x
    first:onCloseDocument()
    local second, sub2 = open_book()
    eq(sub2[1].checked_func(), true, "still on in the next book")
    eq(second.ui.disable_double_tap, false, "and double taps work right away")
    eq(sub2[4].checked_func(), true, "with the same zoom level")
    sub2[1].callback()
    second:onCloseDocument()
    local _, sub3 = open_book()
    eq(sub3[1].checked_func(), false, "turning it off is remembered too")
    package.loaded.device.input.disable_double_tap = nil
end)

-- Optional integration test against an unmodified KOReader checkout. The
-- touch-zone graph, geometry, gesture matching and dispatch are real code.
local koreader = os.getenv("KOREADER_SOURCE")
if koreader then
    test("real KOReader touch dispatch honors plugin priority and fallback", function()
        local function upstream(path) return dofile(koreader .. "/frontend/" .. path .. ".lua") end
        package.loaded.dbg = { guard = function() end }
        package.loaded.optmath = upstream("optmath")
        package.loaded.depgraph = upstream("depgraph")
        package.loaded["ui/geometry"] = upstream("ui/geometry")
        package.loaded["ui/time"] = {}
        package.loaded["ui/gesturerange"] = upstream("ui/gesturerange")
        package.loaded.logger = { dbg = function() end }
        package.loaded["ui/widget/container/widgetcontainer"] =
            package.loaded["ui/widget/container/inputcontainer"]
        local input_container = upstream("ui/widget/container/inputcontainer")
        local grid, ui = gridReader()
        ui._zones, ui._ordered_touch_zones, ui.ges_events = {}, {}, {}
        ui.registerTouchZones = input_container.registerTouchZones
        local builtin_calls = 0
        for _, spec in ipairs({
            { "spread_gesture", "spread" }, { "pinch_gesture", "pinch" },
            { "tap_forward", "tap" }, { "two_finger_tap_top_left_corner", "two_finger_tap" },
        }) do
            ui:registerTouchZones({ {
                id = spec[1], ges = spec[2],
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
                handler = function() builtin_calls = builtin_calls + 1; return true end,
            } })
        end
        grid:setupTouchZones(function() return true end)
        local geom = package.loaded["ui/geometry"]
        local function gesture(name)
            return input_container.onGesture(ui, { ges = name, pos = geom:new{ x = 100, y = 100 } })
        end
        eq(gesture("spread"), true)
        eq(grid.expanded_cell, 0)
        eq(builtin_calls, 0)
        eq(gesture("tap"), true)
        eq(grid.expanded_cell, nil)
        eq(gesture("two_finger_tap"), true)
        eq(grid.expanded_cell, 1)
        eq(gesture("pinch"), true)
        eq(grid.expanded_cell, nil)
        eq(builtin_calls, 0)
        grid.enabled, grid.page_zoom_enabled = false, false
        gesture("spread"); gesture("two_finger_tap"); gesture("tap"); gesture("pinch")
        eq(builtin_calls, 4)
    end)

    test("real KOReader dispatch: quadrant swipes yield to menu swipes", function()
        local input_container = dofile(koreader .. "/frontend/ui/widget/container/inputcontainer.lua")
        local geom = package.loaded["ui/geometry"]
        local grid, ui = navReader(false)
        ui._zones, ui._ordered_touch_zones, ui.ges_events, ui.touch_zone_dg = {}, {}, {}, nil
        ui.registerTouchZones = input_container.registerTouchZones
        local calls = {}
        local function builtin(id, zone, overrides)
            ui:registerTouchZones({ {
                id = id, ges = "swipe", screen_zone = zone, overrides = overrides,
                handler = function() calls[#calls + 1] = id; return true end,
            } })
        end
        builtin("paging_swipe", { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 })
        builtin("readermenu_swipe", { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 / 8 },
            { "paging_swipe" })
        grid:setupTouchZones(function() return true end)
        local function swipe_at(y)
            return input_container.onGesture(ui, {
                ges = "swipe", direction = "west", pos = geom:new{ x = 300, y = y },
            })
        end
        eq(swipe_at(400), true)
        eq(calls[1], "paging_swipe", "unzoomed swipes still turn pages")
        grid:expand(1)
        eq(swipe_at(400), true)
        eq(grid.expanded_cell, 2)
        eq(#calls, 1)
        eq(swipe_at(20), true)
        eq(calls[2], "readermenu_swipe")
        eq(grid.expanded_cell, 2)
        grid:reset()
    end)
    test("real KOReader dispatch: diagonal swipes pan before the Gestures short diagonal swipe", function()
        local input_container = dofile(koreader .. "/frontend/ui/widget/container/inputcontainer.lua")
        local geom = package.loaded["ui/geometry"]
        local grid, ui = gridReader()
        ui._zones, ui._ordered_touch_zones, ui.ges_events, ui.touch_zone_dg = {}, {}, {}, nil
        ui.registerTouchZones = input_container.registerTouchZones
        local calls = {}
        for _, spec in ipairs({
            { "paging_swipe" }, { "short_diagonal_swipe", { "paging_swipe" } },
        }) do
            ui:registerTouchZones({ {
                id = spec[1], ges = "swipe", overrides = spec[2],
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
                handler = function() calls[#calls + 1] = spec[1]; return true end,
            } })
        end
        grid:setupTouchZones(function() return true end)
        local function swipe()
            return input_container.onGesture(ui, {
                ges = "swipe", direction = "northeast",
                pos = geom:new{ x = 300, y = 400 }, end_pos = geom:new{ x = 400, y = 300 },
            })
        end
        eq(swipe(), true)
        eq(calls[1], "short_diagonal_swipe", "unzoomed diagonal swipes keep their action")
        grid:expandPage({ pos = { x = 300, y = 400 } })
        local x, y = ui.view.visible_area.x, ui.view.visible_area.y
        eq(swipe(), true)
        eq(#calls, 1)
        eq(ui.view.visible_area.x, x - 100)
        eq(ui.view.visible_area.y, y + 100)
        grid:reset()
    end)
    test("real KOReader dispatch: quadrant swipes go before ReaderLink's swipe", function()
        local input_container = dofile(koreader .. "/frontend/ui/widget/container/inputcontainer.lua")
        local geom = package.loaded["ui/geometry"]
        local grid, ui = navReader(false)
        ui._zones, ui._ordered_touch_zones, ui.ges_events, ui.touch_zone_dg = {}, {}, {}, nil
        ui.registerTouchZones = input_container.registerTouchZones
        local calls = {}
        for _, spec in ipairs({ { "paging_swipe" }, { "swipe_link", { "paging_swipe", "rolling_swipe" } } }) do
            ui:registerTouchZones({ {
                id = spec[1], ges = "swipe", overrides = spec[2],
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
                -- Like swipe-to-go-back with a non-empty location history.
                handler = function() calls[#calls + 1] = spec[1]; return true end,
            } })
        end
        grid:setupTouchZones(function() return true end)
        local function swipe_dir(direction)
            return input_container.onGesture(ui, {
                ges = "swipe", direction = direction, pos = geom:new{ x = 300, y = 400 },
            })
        end
        eq(swipe_dir("east"), true)
        eq(calls[1], "swipe_link", "unzoomed swipes keep link navigation")
        grid:expand(2)
        eq(swipe_dir("east"), true)
        eq(grid.expanded_cell, 1)
        eq(#calls, 1)
        grid:reset()
    end)
    test("real KOReader key matching: Ctrl + = / + / - / 0, not plain or Alt", function()
        local Key = dofile(koreader .. "/frontend/device/key.lua")
        package.loaded.device.hasKeyboard = function() return true end
        local plugin = setmetatable({ ui = reader({ portrait }) }, dofile(root .. "main.lua"))
        plugin:init()
        package.loaded.device.hasKeyboard = nil
        local function which(key, mods)
            local all = { Alt = false, AltGr = false, Ctrl = false, Shift = false, Super = false, Sym = false, Meta = false, ScreenKB = false }
            for k, v in pairs(mods) do all[k] = v end
            local pressed = Key:new(key, all)
            for name, seq in pairs(plugin.key_events) do
                for _, one in ipairs(seq) do
                    if pressed:match(one) then return seq.args end
                end
            end
        end
        eq(which("=", { Ctrl = true }), "in")
        eq(which("=", { Ctrl = true, Shift = true }), "in")
        eq(which("+", { Ctrl = true }), "in")
        eq(which("-", { Ctrl = true }), "out")
        eq(which("0", { Ctrl = true }), "reset")
        eq(which("=", {}), nil)
        eq(which("-", { Ctrl = true, Alt = true }), nil)
    end)

    test("real KOReader dispatch: double tap goes before the Gestures plugin, only when on", function()
        local input_container = dofile(koreader .. "/frontend/ui/widget/container/inputcontainer.lua")
        local geom = package.loaded["ui/geometry"]
        local grid, ui = gridReader()
        ui._zones, ui._ordered_touch_zones, ui.ges_events, ui.touch_zone_dg = {}, {}, {}, nil
        ui.registerTouchZones = input_container.registerTouchZones
        local calls = {}
        for _, id in ipairs({ "double_tap_left_side", "double_tap_right_side", "double_tap_top_left_corner" }) do
            local zone = id == "double_tap_left_side" and { ratio_x = 0, ratio_y = 0, ratio_w = 0.5, ratio_h = 1 }
                or id == "double_tap_right_side" and { ratio_x = 0.5, ratio_y = 0, ratio_w = 0.5, ratio_h = 1 }
                or { ratio_x = 0, ratio_y = 0, ratio_w = 0.125, ratio_h = 0.125 }
            ui:registerTouchZones({ {
                id = id, ges = "double_tap", screen_zone = zone,
                handler = function() calls[#calls + 1] = id; return true end,
            } })
        end
        grid:setupTouchZones(function() return true end)
        local function double_tap(x, y)
            return input_container.onGesture(ui, { ges = "double_tap", pos = geom:new{ x = x, y = y } })
        end
        eq(double_tap(100, 400), true)
        eq(calls[1], "double_tap_left_side", "off: the user's double-tap actions run")
        grid.double_tap_enabled = true
        eq(double_tap(500, 400), true)
        eq(grid.expanded_cell, 0)
        eq(double_tap(20, 20), true)
        eq(grid.expanded_cell, nil)
        eq(#calls, 1, "on: the plugin goes first, corners included")
        grid:reset()
    end)
end

    local base = os.getenv("KOREADER_BASE")
    local zip_ok = base and os.execute("command -v zip >/dev/null 2>&1")
    if base and (zip_ok == true or zip_ok == 0) then
        test("real libarchive: update unpacks over the plugin; bad zips leave it alone", function()
            local ffi = require("ffi")
            ffi.libc = ffi.libc or "gnu"
            ffi.loadlib = ffi.loadlib or function(name, ver)
                return ffi.load("lib" .. name .. ".so." .. ver)
            end
            local saved_path = package.path
            package.path = base .. "/?.lua;" .. package.path
            package.loaded["ffi/archiver"] = dofile(base .. "/ffi/archiver.lua")
            package.path = saved_path
            local tmp = os.tmpname(); os.remove(tmp); os.execute("mkdir -p " .. tmp)
            local function sh(cmd) local r = os.execute(cmd); assert(r == true or r == 0, cmd) end
            local function write(path, text) local f = assert(io.open(path, "w")); f:write(text); f:close() end
            local function read(path) local f = io.open(path); if not f then return nil end local t = f:read("*a"); f:close(); return t end
            -- Installed plugin: old version plus a file of the user's.
            sh("mkdir -p " .. tmp .. "/plugins/leadingmangazoom.koplugin " .. tmp .. "/data/cache " .. tmp .. "/build/leadingmangazoom.koplugin/docs")
            local plugin = tmp .. "/plugins/leadingmangazoom.koplugin"
            write(plugin .. "/_meta.lua", 'return { version = "1.0.0" }')
            write(plugin .. "/main.lua", "old main")
            write(plugin .. "/grid.lua", "old grid")
            write(plugin .. "/keep.txt", "mine")
            -- New release zip.
            local build = tmp .. "/build/leadingmangazoom.koplugin"
            write(build .. "/_meta.lua", 'return { version = "2.0.0" }')
            write(build .. "/main.lua", "new main")
            write(build .. "/grid.lua", "new grid")
            write(build .. "/docs/help.txt", "help")
            sh("cd " .. tmp .. "/build && zip -qr ../good.zip leadingmangazoom.koplugin")
            sh("cd " .. tmp .. "/build && mv leadingmangazoom.koplugin wrong.koplugin && zip -qr ../wrong.zip wrong.koplugin")
            write(tmp .. "/broken.zip", "this is not a zip")
            package.loaded.datastorage = { getSettingsDir = function() return "." end,
                getDataDir = function() return tmp .. "/data" end }
            package.loaded["libs/libkoreader-lfs"] = {
                attributes = function(p, what)
                    local ok = os.execute("test -d '" .. p .. "'")
                    if ok == true or ok == 0 then return what and "directory" or { mode = "directory" } end
                end,
                mkdir = function(p) return os.execute("mkdir -p '" .. p .. "'") end,
            }
            local u = dofile(root .. "updater.lua")
            u:init(plugin, nil)
            eq(u:installedVersion(), "1.0.0")
            -- Damaged or wrong archives change nothing.
            local v, why = u:unpack(tmp .. "/broken.zip", "2.0.0")
            eq(v, nil); assert(why:find("damaged", 1, true), why)
            v, why = u:unpack(tmp .. "/wrong.zip", "2.0.0")
            eq(v, nil); assert(why:find("not a plugin release", 1, true), why)
            v, why = u:unpack(tmp .. "/good.zip", "3.0.0")
            eq(v, nil); assert(why:find("wrong version", 1, true), why)
            eq(read(plugin .. "/main.lua"), "old main")
            -- The real thing.
            eq(u:unpack(tmp .. "/good.zip", "2.0.0"), "2.0.0")
            eq(u:installedVersion(), "2.0.0")
            eq(read(plugin .. "/main.lua"), "new main")
            eq(read(plugin .. "/grid.lua"), "new grid")
            eq(read(plugin .. "/docs/help.txt"), "help", "new sub-folders are created")
            eq(read(plugin .. "/keep.txt"), "mine", "other files are left alone")
            os.execute("rm -rf '" .. tmp .. "'")
            package.loaded.datastorage = { getSettingsDir = function() return "." end }
        end)
    end

print("1.." .. count)
