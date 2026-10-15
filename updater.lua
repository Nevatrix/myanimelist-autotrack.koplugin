-- self-update from github releases
-- grabs the zip from the latest release and overwrites the plugin's .lua files (.env is left alone)

local HttpGet = require("httpget")
local JSON = require("json")
local logger = require("logger")

local Updater = {
    repo = "Nevatrix/myanimelist-autotrack.koplugin",
    asset = "myanimelist-autotrack.koplugin.zip",
}

-- "v0.1.2" -> {0, 1, 2}
local function parseVersion(v)
    local parts = {}
    for n in tostring(v or ""):gmatch("%d+") do table.insert(parts, tonumber(n)) end
    return parts
end

function Updater.isNewer(remote, current)
    local a, b = parseVersion(remote), parseVersion(current)
    for i = 1, math.max(#a, #b) do
        local x, y = a[i] or 0, b[i] or 0
        if x ~= y then return x > y end
    end
    return false
end

-- github redirects downloads to another domain, httpget follows them.
-- the zip is tiny, everything just goes to memory
local get = HttpGet.get

function Updater:latest()
    local body, err = get("https://api.github.com/repos/" .. self.repo .. "/releases/latest", "application/vnd.github+json")
    if not body then return nil, err end
    local ok, data = pcall(JSON.decode, body)
    if not ok or type(data) ~= "table" then return nil, "json" end
    local url
    for _, a in ipairs(data.assets or {}) do
        if a.name == self.asset then url = a.browser_download_url end
    end
    if not url then return nil, "release has no " .. self.asset end
    return { version = data.tag_name, url = url, notes = data.body }
end

local function writeFile(path, content)
    local f, err = io.open(path, "wb")
    if not f then return nil, err end
    f:write(content)
    f:close()
    return true
end

-- download the zip and copy the .lua files into plugin_dir
function Updater:install(release, plugin_dir, tmp_dir)
    local data, err = get(release.url, "application/octet-stream")
    if not data then return nil, err end
    local zip = tmp_dir .. "/malautotrack-update.zip"
    local ok, werr = writeFile(zip, data)
    if not ok then return nil, werr end

    local ok_arch, Archiver = pcall(require, "ffi/archiver")
    if not ok_arch then os.remove(zip) return nil, "this koreader has no ffi/archiver" end
    local reader = Archiver.Reader:new()
    if not reader:open(zip) then os.remove(zip) return nil, "invalid zip" end

    -- only top level .lua files; .env and everything else stays as is
    local paths = {}
    for entry in reader:iterate() do
        if entry.mode == "file" then
            local name = entry.path:match("^[^/]+/([^/]+%.lua)$") or entry.path:match("^([^/]+%.lua)$")
            if name then paths[name] = entry.path end
        end
    end
    -- read everything first so a failure doesn't leave the plugin half-updated
    local contents = {}
    for name, path in pairs(paths) do
        contents[name] = reader:extractToMemory(path)
        if not contents[name] then reader:close() os.remove(zip) return nil, "couldn't read " .. name end
    end
    reader:close()
    os.remove(zip)
    if not contents["main.lua"] or not contents["_meta.lua"] then
        return nil, "zip doesn't look like the plugin"
    end

    for name, content in pairs(contents) do
        local wok, e = writeFile(plugin_dir .. "/" .. name .. ".new", content)
        if not wok then return nil, e end
    end
    for name in pairs(contents) do
        os.remove(plugin_dir .. "/" .. name)
        os.rename(plugin_dir .. "/" .. name .. ".new", plugin_dir .. "/" .. name)
    end
    logger.info("MAL Autotrack: updated to", release.version)
    return true
end

return Updater
