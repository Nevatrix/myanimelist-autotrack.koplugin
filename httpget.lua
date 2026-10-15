-- plain GET with manual redirects (luasocket won't follow https -> other host)
-- returns body or nil, err

local http = require("socket.http")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")

local M = {}

M.user_agent = "myanimelist-autotrack.koplugin (https://github.com/Nevatrix/myanimelist-autotrack.koplugin)"

function M.urlencode(s)
    return (tostring(s):gsub("[^%w%-%._~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

function M.get(url, accept)
    for _ = 1, 5 do
        local buf = {}
        socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
        local code, resp_headers, status = socket.skip(1, http.request{
            url = url,
            method = "GET",
            headers = { ["User-Agent"] = M.user_agent, ["Accept"] = accept or "*/*" },
            sink = ltn12.sink.table(buf),
            redirect = false,
        })
        socketutil:reset_timeout()
        if resp_headers == nil then return nil, "network_error: " .. tostring(status or code) end
        local location = resp_headers.location or resp_headers.Location
        if code >= 300 and code < 400 and location then
            url = location
        elseif code == 200 then
            return table.concat(buf)
        else
            return nil, "http_" .. tostring(code)
        end
    end
    return nil, "too_many_redirects"
end

return M
