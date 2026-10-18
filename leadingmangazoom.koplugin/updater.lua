--[[--
Self-updater for LeadingMangaZoom.

KOReader has no plugin store, so the plugin updates itself from its GitHub
releases: it reads the latest release, downloads the attached
leadingmangazoom.koplugin.zip, checks it, unpacks it over its own folder and
offers to restart KOReader.

Only KOReader's own building blocks are used: LuaSocket (through socketutil's
timeouts) for HTTP, ffi/archiver (libarchive) to unpack, NetworkMgr to bring
Wi-Fi up, and UIManager to restart.
@module leadingmangazoom.updater
]]--

local Updater = {
    REPO = "Auri3l/leadingmangazoom.koplugin",
    ASSET_NAME = "leadingmangazoom.koplugin.zip",
    -- Folder name inside the release zip.
    ROOT = "leadingmangazoom.koplugin",
    -- Files a release must contain before anything is unpacked.
    REQUIRED = { "_meta.lua", "main.lua", "grid.lua" },
    -- Automatic checks happen at most this often.
    AUTO_CHECK_INTERVAL = 24 * 60 * 60,
}

local function releasesPage()
    return "https://github.com/" .. Updater.REPO .. "/releases"
end

---------------------------------------------------------------------------
-- Pure helpers (unit tested)
---------------------------------------------------------------------------

local function versionParts(v)
    local parts = {}
    for n in tostring(v or ""):gsub("^v", ""):gmatch("(%d+)") do
        parts[#parts + 1] = tonumber(n)
    end
    return parts
end

--- True if version `a` is newer than version `b` ("1.10.0" > "1.9.2").
function Updater.isNewer(a, b)
    local x, y = versionParts(a), versionParts(b)
    for i = 1, math.max(#x, #y) do
        local p, q = x[i] or 0, y[i] or 0
        if p ~= q then return p > q end
    end
    return false
end

--- Reads `version = "x.y.z"` from the text of a _meta.lua.
function Updater.metaVersion(text)
    return text and text:match('version%s*=%s*"([^"]+)"') or nil
end

--- From a GitHub release (decoded JSON), returns version, zip URL and notes,
-- or nil and a reason when it can't be installed.
function Updater.parseRelease(release)
    if type(release) ~= "table" or type(release.tag_name) ~= "string" then
        return nil, "no release found"
    end
    if release.draft or release.prerelease then
        return nil, "the latest release is not final"
    end
    local url
    for _, asset in ipairs(release.assets or {}) do
        if asset.name == Updater.ASSET_NAME and type(asset.browser_download_url) == "string" then
            url = asset.browser_download_url
            break
        end
    end
    if not url then return nil, "the latest release has no " .. Updater.ASSET_NAME end
    return {
        version = release.tag_name:gsub("^v", ""),
        url = url,
        notes = type(release.body) == "string" and release.body or "",
        page = release.html_url or releasesPage(),
    }
end

--- Release notes shortened for a dialog: Markdown markers removed, at most
-- `limit` characters.
function Updater.shortNotes(notes, limit)
    limit = limit or 500
    local text = (notes or "")
        :gsub("\r", "")
        :gsub("%*%*", "")
        :gsub("`", "")
        :gsub("%[([^%]]+)%]%([^%)]+%)", "%1")
        :gsub("\n[ \t]*#+[ \t]*", "\n")
        :gsub("^[ \t]*#+[ \t]*", "")
        :gsub("\n[ \t]*>[ \t]*", "\n")
        :gsub("\n\n\n+", "\n\n")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if #text > limit then
        -- Cut on a line or word boundary, never inside a UTF-8 character.
        -- Back up while the next byte continues a UTF-8 character.
        local n = limit
        while n > 0 and (text:byte(n + 1) or 0) >= 0x80 and (text:byte(n + 1) or 0) < 0xC0 do
            n = n - 1
        end
        local cut = text:sub(1, n)
        cut = cut:match("^(.*)\n") or cut:match("^(.*)%s") or cut
        text = cut .. " …"
    end
    return text
end

--- Checks the list of archive entries before unpacking. Every entry must be
-- a plain file or folder inside the single plugin folder, with no "..", and
-- the required files must be there. Returns true, or nil and a reason.
function Updater.validateEntries(entries)
    local found = {}
    for _, entry in ipairs(entries) do
        local path = entry.path or ""
        local mode = entry.mode
        if mode ~= nil and mode ~= "file" and mode ~= "directory" then
            return nil, "unexpected entry " .. path
        end
        if path:find("%.%.") or path:sub(1, 1) == "/" or path:find("\\", 1, true) then
            return nil, "unsafe path " .. path
        end
        local root, rest = path:match("^([^/]+)/?(.*)$")
        if root ~= Updater.ROOT then
            return nil, "unexpected folder " .. path
        end
        if rest ~= "" then found[rest] = true end
    end
    for _, name in ipairs(Updater.REQUIRED) do
        if not found[name] then return nil, "missing " .. name end
    end
    return true
end

---------------------------------------------------------------------------
-- KOReader side
---------------------------------------------------------------------------

function Updater:init(plugin_dir, Settings)
    self.plugin_dir = (plugin_dir or ""):gsub("/$", "")
    self.settings = Settings
end

function Updater:installedVersion()
    local f = io.open(self.plugin_dir .. "/_meta.lua", "r")
    if not f then return "0" end
    local text = f:read("*a")
    f:close()
    return Updater.metaVersion(text) or "0"
end

function Updater:userAgent()
    return "KOReader-LeadingMangaZoom/" .. self:installedVersion()
end

-- GET a URL into a sink. Returns true, or nil and a reason a person can read.
function Updater:httpGet(url, sink, accept, total_timeout)
    local ok_req, http, socket, socketutil = pcall(function()
        return require("socket.http"), require("socket"), require("socketutil")
    end)
    if not ok_req then return nil, "networking is unavailable" end
    local ok, code, headers, status = pcall(function()
        socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, total_timeout or socketutil.LARGE_TOTAL_TIMEOUT)
        local c, h, s = socket.skip(1, http.request({
            url = url,
            method = "GET",
            headers = { ["User-Agent"] = self:userAgent(), ["Accept"] = accept },
            sink = sink(socketutil),
            redirect = true,
        }))
        socketutil:reset_timeout()
        return c, h, s
    end)
    if not ok then
        pcall(function() socketutil:reset_timeout() end)
        return nil, "the connection failed"
    end
    if code == socketutil.TIMEOUT_CODE or code == socketutil.SINK_TIMEOUT_CODE then
        return nil, "the connection timed out"
    end
    if code == socketutil.SSL_HANDSHAKE_CODE then return nil, "the secure connection failed" end
    if not headers then return nil, "there was no response" end
    if tonumber(code) ~= 200 then return nil, status or ("HTTP " .. tostring(code)) end
    return true
end

function Updater:fetchLatest()
    local chunks = {}
    local ok, err = self:httpGet(
        "https://api.github.com/repos/" .. Updater.REPO .. "/releases/latest",
        function(socketutil) return socketutil.table_sink(chunks) end,
        "application/vnd.github+json")
    if not ok then return nil, err end
    local ok_json, release = pcall(function() return require("json").decode(table.concat(chunks)) end)
    if not ok_json then return nil, "GitHub sent an unreadable answer" end
    return Updater.parseRelease(release)
end

function Updater:cacheDir()
    local DataStorage = require("datastorage")
    local dir = DataStorage:getDataDir() .. "/cache"
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(dir, "mode") ~= "directory" then lfs.mkdir(dir) end
    return dir
end

-- Downloads the release zip. Returns its path, or nil and a reason.
function Updater:download(url)
    local path = self:cacheDir() .. "/" .. Updater.ASSET_NAME
    local tmp = path .. ".part"
    pcall(os.remove, tmp)
    local file = io.open(tmp, "wb")
    if not file then return nil, "the file could not be saved" end
    -- The zip is small; allow a slow e-reader connection 5 minutes in total.
    local ok, err = self:httpGet(url, function(socketutil)
        return socketutil.file_sink(file)
    end, "application/octet-stream", 300)
    pcall(function() file:close() end)
    if not ok then
        pcall(os.remove, tmp)
        return nil, err
    end
    pcall(os.remove, path)
    if not os.rename(tmp, path) then
        pcall(os.remove, tmp)
        return nil, "the file could not be saved"
    end
    return path
end

-- Checks and unpacks a downloaded zip over the plugin folder.
-- Returns the unpacked version, or nil and a reason.
function Updater:unpack(zip_path, expected_version)
    local ok_req, Archiver = pcall(require, "ffi/archiver")
    if not (ok_req and Archiver and Archiver.Reader) then
        return nil, "this KOReader cannot unpack archives"
    end
    local archive = Archiver.Reader:new()
    if not archive:open(zip_path) then
        local err = archive.err
        archive:close()
        return nil, "the download is damaged (" .. tostring(err or "unreadable") .. ")"
    end
    local entries = {}
    for entry in archive:iterate() do entries[#entries + 1] = entry end
    local valid, why = Updater.validateEntries(entries)
    if not valid then
        archive:close()
        return nil, "the download is not a plugin release (" .. why .. ")"
    end
    local meta = archive:extractToMemory(Updater.ROOT .. "/_meta.lua")
    local version = Updater.metaVersion(meta)
    if not version or (expected_version and version ~= expected_version) then
        archive:close()
        return nil, "the download has the wrong version (" .. tostring(version) .. ")"
    end
    -- Unpack into a staging folder first, so a damaged archive never leaves
    -- the plugin half old, half new. Only then copy over the plugin.
    local lfs = require("libs/libkoreader-lfs")
    local stage = self:cacheDir() .. "/lmz-update"
    local files = {}
    for _, entry in ipairs(entries) do
        local rest = entry.path:match("^[^/]+/(.+)$")
        if rest and entry.mode ~= "directory" then
            if not archive:extractToPath(entry.path, stage .. "/" .. rest) then
                local err = archive.err
                archive:close()
                return nil, "unpacking failed (" .. tostring(err) .. ")"
            end
            files[#files + 1] = rest
        end
    end
    archive:close()
    for _, rest in ipairs(files) do
        -- Create any sub-folders the release adds.
        local dir = self.plugin_dir
        for part in rest:gmatch("([^/]+)/") do
            dir = dir .. "/" .. part
            if lfs.attributes(dir, "mode") ~= "directory" then lfs.mkdir(dir) end
        end
        local src, dst = stage .. "/" .. rest, self.plugin_dir .. "/" .. rest
        local i = io.open(src, "rb")
        local data = i and i:read("*a")
        if i then i:close() end
        local o = data and io.open(dst, "wb")
        if not (o and o:write(data)) then
            if o then o:close() end
            return nil, "could not write " .. rest
        end
        o:close()
        os.remove(src)
    end
    return version
end

---------------------------------------------------------------------------
-- Dialogs
---------------------------------------------------------------------------

local function show(text, timeout)
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    UIManager:show(InfoMessage:new{ text = text, timeout = timeout })
end

-- Runs `action` once a network connection is up, asking to turn Wi-Fi on
-- if needed. Gated on isConnected, not isOnline: isOnline is a DNS lookup of
-- a Microsoft host that ad blockers and captive portals often fail.
local function whenConnected(action)
    local NetworkMgr = require("ui/network/manager")
    if NetworkMgr:isConnected() then return action() end
    NetworkMgr:runWhenConnected(function()
        if NetworkMgr:isConnected() then action() end
    end)
end

function Updater:failed(what, reason)
    show(what .. "\n" .. tostring(reason) .. ".\n\n" ..
        "You can also download it from\n" .. releasesPage())
end

--- Menu entry: check now and offer the update.
function Updater:check()
    whenConnected(function()
        local UIManager = require("ui/uimanager")
        show("Checking for updates…", 1)
        UIManager:scheduleIn(0.2, function()
            local release, err = self:fetchLatest()
            self:noteChecked()
            if not release then return self:failed("Couldn't check for updates:", err) end
            local installed = self:installedVersion()
            if not Updater.isNewer(release.version, installed) then
                return show("Leading Manga Zoom is up to date (v" .. installed .. ").", 3)
            end
            self:offer(release, installed)
        end)
    end)
end

function Updater:offer(release, installed)
    local UIManager = require("ui/uimanager")
    local ConfirmBox = require("ui/widget/confirmbox")
    local notes = Updater.shortNotes(release.notes)
    UIManager:show(ConfirmBox:new{
        text = "Leading Manga Zoom v" .. release.version .. " is available.\n" ..
            "You have v" .. installed .. ".\n\n" .. notes,
        ok_text = "Update",
        cancel_text = "Later",
        ok_callback = function() self:install(release) end,
    })
end

function Updater:install(release)
    whenConnected(function()
        local UIManager = require("ui/uimanager")
        show("Downloading v" .. release.version .. "…", 1)
        UIManager:scheduleIn(0.2, function()
            local zip, err = self:download(release.url)
            if not zip then return self:failed("Download failed:", err) end
            local version, why = self:unpack(zip, release.version)
            pcall(os.remove, zip)
            if not version then return self:failed("Update failed:", why) end
            self:offerRestart(version)
        end)
    end)
end

function Updater:offerRestart(version)
    local UIManager = require("ui/uimanager")
    local Device = require("device")
    local text = "Leading Manga Zoom updated to v" .. version .. "."
    if Device.canRestart and Device:canRestart() then
        local ConfirmBox = require("ui/widget/confirmbox")
        UIManager:show(ConfirmBox:new{
            text = text .. "\n\nRestart KOReader now to use it?",
            ok_text = "Restart",
            cancel_text = "Later",
            ok_callback = function() UIManager:restartKOReader() end,
        })
    else
        show(text .. "\n\nRestart KOReader to use it.")
    end
end

---------------------------------------------------------------------------
-- Automatic checks (opt-in)
---------------------------------------------------------------------------

function Updater:autoCheckEnabled()
    return self.settings and self.settings:get("auto_update_check") or false
end

function Updater:setAutoCheck(enabled)
    if self.settings then self.settings:set("auto_update_check", enabled and true or false) end
end

function Updater:noteChecked()
    if self.settings then self.settings:set("last_update_check", os.time()) end
end

--- At most once a day, and only when already connected (never turns Wi-Fi
-- on by itself), quietly checks and mentions a new version.
function Updater:maybeAutoCheck()
    if not self:autoCheckEnabled() then return end
    local last = self.settings and self.settings:get("last_update_check") or 0
    if type(last) ~= "number" or os.time() - last < Updater.AUTO_CHECK_INTERVAL then return end
    local ok, NetworkMgr = pcall(require, "ui/network/manager")
    if not ok or not NetworkMgr:isConnected() then return end
    local UIManager = require("ui/uimanager")
    UIManager:scheduleIn(5, function()
        local release = self:fetchLatest()
        self:noteChecked()
        if release and Updater.isNewer(release.version, self:installedVersion()) then
            self:offer(release, self:installedVersion())
        end
    end)
end

return Updater
