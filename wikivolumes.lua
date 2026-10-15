-- volume -> chapters table from english wikipedia ("List of X chapters" pages)
-- goes through the official mediawiki api, one lookup per series, cached by main.lua
--
-- the pages use {{Graphic novel list | VolumeNumber = 5 | ChapterList = ... }}
-- and the chapter list comes in a few flavors:
--   * 032. "Title"            numbered bullets
--   * {{nihongo|"Title"|..}}  plain bullets, count them
--   {{Numbered list|start=32|..}} / <ol start="32">

local Wiki = {}

local API = "https://en.wikipedia.org/w/api.php"

-- splits template args at depth 1, ignoring | inside {{ }} and [[ ]]
local function splitArgs(s)
    local args, depth, last = {}, 0, 1
    local i, n = 1, #s
    while i <= n do
        local two = s:sub(i, i + 1)
        if two == "{{" or two == "[[" then
            depth = depth + 1
            i = i + 2
        elseif two == "}}" or two == "]]" then
            depth = depth - 1
            i = i + 2
        else
            if s:sub(i, i) == "|" and depth == 0 then
                table.insert(args, s:sub(last, i - 1))
                last = i + 1
            end
            i = i + 1
        end
    end
    table.insert(args, s:sub(last))
    return args
end

-- finds every {{name ...}} block (balanced), returns the inner text
local function findTemplates(text, name)
    local out = {}
    local pos = 1
    while true do
        local s, e = text:find("{{%s*" .. name, pos)
        if not s then break end
        local nextc = text:sub(e + 1, e + 1)
        -- skip {{Graphic novel list/header}} and friends
        if nextc == "/" or nextc:match("[%w]") then
            pos = e + 1
        else
            local depth, i = 0, s
            while i <= #text do
                local two = text:sub(i, i + 1)
                if two == "{{" then
                    depth = depth + 1
                    i = i + 2
                elseif two == "}}" then
                    depth = depth - 1
                    i = i + 2
                    if depth == 0 then break end
                else
                    i = i + 1
                end
            end
            table.insert(out, text:sub(e + 1, i - 3))
            pos = i
        end
    end
    return out
end

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function params(inner)
    local p = {}
    for _, arg in ipairs(splitArgs(inner)) do
        local k, v = arg:match("^%s*([%w_]+)%s*=(.*)$")
        if k then p[k] = v end
    end
    return p
end

-- returns first, last, count (any of them can be nil)
local function chapterSpan(list)
    if not list or trim(list) == "" then return nil end
    local nums, count, start = {}, 0, nil

    local tpl = (list:match("{{%s*[Nn]umbered list") and "[Nn]umbered list") or (list:match("{{%s*[Oo]rdered list") and "[Oo]rdered list")
    if tpl then
        local inner = findTemplates(list, tpl)[1] or ""
        for _, a in ipairs(splitArgs(inner)) do
            local st = a:match("^%s*start%s*=%s*(%d+)")
            if st then
                start = tonumber(st)
            elseif trim(a) ~= "" and not a:match("^%s*[%w_]+%s*=") then
                count = count + 1
            end
        end
    else
        start = tonumber(list:match('<ol[^>]-start%s*=%s*"?(%d+)'))
        for line in (list .. "\n"):gmatch("([^\n]*)\n") do
            local item = line:match("^%s*[%*#]%s*(.*)$")
            if item and not item:match("^[%*#]") then
                count = count + 1
                local n = item:match("^(%d+)%s*[%.:%)%-]") or item:match("^[Cc]hapter%s+(%d+)")
                if n then table.insert(nums, tonumber(n)) end
            end
        end
        for _ in list:gmatch("<li[%s>]") do count = count + 1 end
    end

    if #nums > 0 and #nums >= count / 2 then
        table.sort(nums)
        return nums[1], nums[#nums], count
    end
    if start and count > 0 then return start, start + count - 1, count end
    if count > 0 then return nil, nil, count end
    return nil
end

local function parseEntries(text)
    local entries = {}
    for _, inner in ipairs(findTemplates(text, "Graphic novel list")) do
        local p = params(inner)
        local vol = tonumber(p.VolumeNumber and p.VolumeNumber:match("%d+"))
        if vol then
            local list = (p.ChapterList or "") .. "\n" .. (p.ChapterListCol1 or "") .. "\n" .. (p.ChapterListCol2 or "")
            if trim(list) == "" then list = p.LicensedChapterList end
            local first, last, count = chapterSpan(list)
            table.insert(entries, { vol = vol, first = first, last = last, count = count })
        end
    end
    return entries
end

--- wikitext -> { [vol] = { first, last } }
-- some pages also list a spin-off further down (blue lock has episode nagi),
-- each table starts with its own /header. keep going while volume numbers keep
-- going up, stop at the first table that starts over
function Wiki.parse(text)
    local tables = {}
    local pos = 1
    while true do
        local s = text:find("{{%s*Graphic novel list/header", pos + 1)
        table.insert(tables, text:sub(pos, (s or #text + 1) - 1))
        if not s then break end
        pos = s
    end
    local entries, max_vol = {}, 0
    for _, chunk in ipairs(tables) do
        local es = parseEntries(chunk)
        if #es > 0 then
            local min_vol = math.huge
            for _, e in ipairs(es) do min_vol = math.min(min_vol, e.vol) end
            if min_vol <= max_vol then break end
            for _, e in ipairs(es) do
                table.insert(entries, e)
                max_vol = math.max(max_vol, e.vol)
            end
        end
    end
    table.sort(entries, function(a, b) return a.vol < b.vol end)

    -- fill volumes that only had unnumbered bullets, counting from the previous one
    local vols, prev_last = {}, 0
    for _, e in ipairs(entries) do
        local first, last = e.first, e.last
        if not first and e.count and e.count > 0 then
            first = prev_last + 1
            last = first + e.count - 1
        end
        if first and last and last >= first then
            vols[e.vol] = { first, last }
            prev_last = last
        end
    end
    return vols
end

--- "List of One Piece chapters (1–186)" style sub pages linked or transcluded from the main list
function Wiki.subPages(text)
    local pages, seen = {}, {}
    for title in text:gmatch("%[%[%s*(List of [^%]|]- chapters %b())") do
        if not seen[title] then seen[title] = true; table.insert(pages, title) end
    end
    for title in text:gmatch("{{%s*:%s*(List of [^}|]- chapters %b())") do
        if not seen[title] then seen[title] = true; table.insert(pages, title) end
    end
    return pages
end

-- which volume holds this chapter
function Wiki.volumeOf(vols, chapter)
    for v, r in pairs(vols) do
        if chapter >= r[1] and chapter <= r[2] then return v end
    end
end

-- highest volume fully covered by `chapters_read`
function Wiki.volumesDone(vols, chapters_read)
    local best = 0
    for v, r in pairs(vols) do
        if r[2] <= chapters_read and v > best then best = v end
    end
    return best
end

-- network part --------------------------------------------------------------

local function api(params_str)
    local HttpGet = require("httpget")
    local JSON = require("json")
    local body, err = HttpGet.get(API .. "?format=json&formatversion=2&" .. params_str, "application/json")
    if not body then return nil, err end
    local ok, data = pcall(JSON.decode, body)
    if not ok or type(data) ~= "table" then return nil, "json" end
    return data
end

local function wikitext(page)
    local enc = require("httpget").urlencode
    local data, err = api("action=parse&prop=wikitext&redirects=1&page=" .. enc(page))
    if not data then return nil, err end
    if not data.parse then return nil, "missing" end
    return data.parse.wikitext, data.parse.title
end

local function search(title)
    local enc = require("httpget").urlencode
    local data = api("action=query&list=search&srlimit=5&srsearch=" .. enc('intitle:"' .. title .. '" chapters'))
    local out = {}
    for _, r in ipairs(data and data.query and data.query.search or {}) do
        if r.title:match("^List of .+ chapters") then table.insert(out, r.title) end
    end
    return out
end

--- tries each title ("Blue Lock", "Burū Rokku"...), returns vols, page title
-- or nil, "network" when wikipedia couldn't be reached (so it isn't cached as a miss)
function Wiki.lookup(titles)
    local net_fail = false
    local candidates, seen = {}, {}
    local function add(t) if t and not seen[t] then seen[t] = true; table.insert(candidates, t) end end
    for _, t in ipairs(titles) do add("List of " .. t .. " chapters") end
    for _, t in ipairs(titles) do
        for _, found in ipairs(search(t)) do add(found) end
    end

    for _, page in ipairs(candidates) do
        local text, real_title = wikitext(page)
        if not text and real_title ~= "missing" and tostring(real_title):match("network") then net_fail = true end
        if text then
            local vols = Wiki.parse(text)
            if next(vols) == nil then
                -- long series split the list across sub pages
                for i, sub in ipairs(Wiki.subPages(text)) do
                    if i > 12 then break end
                    local st = wikitext(sub)
                    if st then
                        for v, r in pairs(Wiki.parse(st)) do vols[v] = r end
                    end
                end
            end
            if next(vols) ~= nil then return vols, real_title or page end
        end
    end
    return nil, net_fail and "network" or "not_found"
end

return Wiki
