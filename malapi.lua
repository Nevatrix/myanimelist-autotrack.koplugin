-- tiny client for the MAL v2 api
-- doc: https://myanimelist.net/apiconfig/references/api/v2

local JSON = require("json")
local http = require("socket.http")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local logger = require("logger")

local API_BASE = "https://api.myanimelist.net/v2"
local TOKEN_URL = "https://myanimelist.net/v1/oauth2/token"

local MalApi = {}
MalApi.__index = MalApi

-- on_tokens gets called after a refresh so the new tokens can be saved
function MalApi:new(creds, on_tokens)
    return setmetatable({ creds = creds, on_tokens = on_tokens }, self)
end

local function urlencode(s)
    s = tostring(s)
    return (s:gsub("[^%w%-%._~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function form(params)
    local parts = {}
    for k, v in pairs(params) do
        table.insert(parts, urlencode(k) .. "=" .. urlencode(v))
    end
    table.sort(parts)
    return table.concat(parts, "&")
end
MalApi.form = form

-- returns (status, json or raw text)
local function request(method, url, headers, body)
    local sink = {}
    local req = {
        method = method,
        url = url,
        headers = headers or {},
        sink = ltn12.sink.table(sink),
    }
    if body then
        req.source = ltn12.source.string(body)
        req.headers["Content-Type"] = "application/x-www-form-urlencoded"
        req.headers["Content-Length"] = tostring(#body)
    end
    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    local code, resp_headers, status = socket.skip(1, http.request(req))
    socketutil:reset_timeout()

    if resp_headers == nil then
        logger.warn("MAL Autotrack: network error", status or code)
        return nil, "network_error"
    end
    local content = table.concat(sink)
    local ok, data = pcall(JSON.decode, content)
    if ok and type(data) == "table" then
        return code, data
    end
    return code, content
end

function MalApi:refresh()
    logger.info("MAL Autotrack: refreshing access token")
    local code, data = request("POST", TOKEN_URL, {}, form{
        client_id = self.creds.client_id,
        grant_type = "refresh_token",
        refresh_token = self.creds.refresh_token,
    })
    if code == 200 and type(data) == "table" and data.access_token then
        self.creds.access_token = data.access_token
        self.creds.refresh_token = data.refresh_token or self.creds.refresh_token
        self.creds.expires_at = os.time() + (tonumber(data.expires_in) or 2592000) - 3600
        if self.on_tokens then self.on_tokens(self.creds) end
        return true
    end
    logger.err("MAL Autotrack: token refresh failed", code, type(data) == "table" and data.error or data)
    return false, "auth_error"
end

-- on 401, refresh the token and retry once
function MalApi:call(method, path, params, body_params)
    if self.creds.expires_at and os.time() >= self.creds.expires_at then
        local ok, err = self:refresh()
        if not ok then return nil, err end
    end
    local url = API_BASE .. path
    if params then url = url .. "?" .. form(params) end
    local body = body_params and form(body_params) or nil

    for attempt = 1, 2 do
        local headers = {
            ["Authorization"] = "Bearer " .. tostring(self.creds.access_token),
            ["X-MAL-CLIENT-ID"] = self.creds.client_id,
        }
        local code, data = request(method, url, headers, body)
        if code == nil then return nil, data end
        if code == 401 and attempt == 1 then
            local ok, err = self:refresh()
            if not ok then return nil, err end
        elseif code >= 200 and code < 300 then
            return data
        else
            logger.err("MAL Autotrack:", method, path, "->", code, type(data) == "table" and data.error or data)
            return nil, "http_" .. tostring(code)
        end
    end
    return nil, "auth_error"
end

local SEARCH_FIELDS = "media_type,num_volumes,num_chapters,alternative_titles,my_list_status"

function MalApi:searchManga(query)
    -- MAL errors out on queries under 3 chars or really long ones
    query = query:sub(1, 60)
    if #query < 3 then return {} end
    local data, err = self:call("GET", "/manga", { q = query, limit = 10, fields = SEARCH_FIELDS, nsfw = "true" })
    if not data then return nil, err end
    local list = {}
    for _, item in ipairs(data.data or {}) do
        table.insert(list, item.node)
    end
    return list
end

function MalApi:getManga(id)
    return self:call("GET", "/manga/" .. tostring(id), { fields = "id,title," .. SEARCH_FIELDS })
end

function MalApi:updateMangaStatus(id, fields)
    return self:call("PATCH", "/manga/" .. tostring(id) .. "/my_list_status", nil, fields)
end

function MalApi:me()
    return self:call("GET", "/users/@me")
end

return MalApi
