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
end

print("1.." .. count)
