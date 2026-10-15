-- pulls title, volume and chapter out of the file name
--   "Chainsaw Man v03 (2021) (Digital).cbz" -> Chainsaw Man, vol 3
--   "[Group] One Piece - c1100 [en].cbz"    -> One Piece, ch 1100
-- no koreader deps so it can be tested on the pc (tools/test_parser.lua)

local Parser = {}

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local VOLUME_PATTERNS = {
    "[Vv][Oo][Ll][Uu][Mm][Ee][Nn]?%s*%.?%s*(%d+)",
    "[Vv][Oo][Ll]%s*%.?%s*(%d+)",
    "[Tt][Oo][Mm][Oo]%s*%.?%s*(%d+)",
    "%f[%w][Vv]%s?(%d+)%f[%D]",
    "%f[%w][Tt](%d+)%f[%D]",
}

local CHAPTER_PATTERNS = {
    "[Cc][Hh][Aa][Pp][Tt][Ee][Rr]%s*%.?%s*(%d+)",
    "[Cc][Aa][Pp][Ii][Tt][Uu][Ll][Oo]%s*%.?%s*(%d+)",
    "[Cc][Aa][Pp]%.?%s*(%d+)",
    "[Cc][Hh]%s*%.?%s*(%d+)",
    "%f[%w][Cc]%s?(%d+)%f[%D]",
    "#%s*(%d+)",
}

-- returns (last, first, text_without_it). for ranges like "#005-013" last=13, first=5
local function extract(text, patterns)
    for _, pat in ipairs(patterns) do
        local s, e, num = text:find(pat)
        if s then
            local first = tonumber(num)
            local last = first
            local _, e2, num2 = text:find("^%s*%-%s*#?%s*(%d+)", e + 1)
            if e2 and tonumber(num2) > first then
                last, e = tonumber(num2), e2
            end
            return last, first, trim(text:sub(1, s - 1) .. " " .. text:sub(e + 1))
        end
    end
    return nil, nil, text
end

function Parser.basename(path)
    local name = path:match("([^/\\]+)$") or path
    return (name:gsub("%.[%w]+$", ""))
end

function Parser.parentdir(path)
    return path:match("([^/\\]+)[/\\][^/\\]+$")
end

function Parser.parse(path)
    local raw = Parser.basename(path)
    local text = raw

    text = text:gsub("_", " ")
    -- "One.Piece.v01"
    if not text:find(" ") then
        text = text:gsub("%.", " ")
    end

    -- before stripping parens, sometimes the volume is in there
    local volume, volume_start, chapter, chapter_start
    volume, volume_start, text = extract(text, VOLUME_PATTERNS)
    chapter, chapter_start, text = extract(text, CHAPTER_PATTERNS)

    text = text:gsub("%b[]", " "):gsub("%b()", " "):gsub("%b{}", " ")

    -- "Vinland Saga 07" -> lone number at the end = volume
    if not volume and not chapter then
        local s, _, num = text:find("[%s%-]+(%d%d?%d?)%s*$")
        if s then
            volume = tonumber(num)
            volume_start = volume
            text = text:sub(1, s - 1)
        end
    end

    -- "KCC" shows up because calibre names files "{title} - {author}" and KCC sets itself as the author
    local junk = { "[Dd]igital", "[Ss]can", "[Rr]aw", "[Ee]nglish", "[Ss]panish", "[Ee]spañol", "KCC" }
    for _, j in ipairs(junk) do
        text = text:gsub("%f[%w]" .. j .. "%f[%W]", " ")
    end

    text = text:gsub("%s+", " ")
    text = trim(text)
    text = text:gsub("[%s%-%–:,%.]+$", ""):gsub("^[%s%-%–:,%.]+", "")
    text = trim(text)

    return {
        raw = raw,
        title = text,
        volume = volume,
        volume_start = volume_start,
        chapter = chapter,
        chapter_start = chapter_start,
    }
end

-- chapter number from a TOC entry: "Blue Lock 34", "Chapter 12: Foo", "Capitulo 5"
-- returns nil for things like "Cover" or "Extras"
function Parser.chapterFromTitle(title)
    if not title or title == "" then return nil end
    local n = extract(title, CHAPTER_PATTERNS)
    if n then return n end
    -- volume markers in a toc entry aren't chapters
    if extract(title, VOLUME_PATTERNS) then return nil end
    local last = title:match("(%d+)%D*$")
    return tonumber(last)
end

local function words(s)
    local out = {}
    for w in s:gmatch("%S+") do table.insert(out, w) end
    return out
end

-- "P4", "Pt. 4", "Part4" -> "Part 4" so it lines up with MAL's naming
function Parser.expandParts(title)
    return (title:gsub("%f[%w][Pp][Aa]?[Rr]?[Tt]?%.?%s*(%d+)%f[%D]", function(n) return "Part " .. n end))
end

-- what to send to MAL's search, most specific first.
-- MAL doesn't do fuzzy matching, so one typo at the end ("Unbreakeable") kills
-- the whole query; dropping words from the end gets around that
function Parser.searchQueries(title)
    local out, seen = {}, {}
    local function add(q)
        q = q:gsub("%s+", " "):gsub("^%s+", ""):gsub("[%s%-:]+$", "")
        if #q >= 3 and not seen[q:lower()] then
            seen[q:lower()] = true
            table.insert(out, q)
        end
    end
    local expanded = Parser.expandParts(title)
    add(expanded)
    add(title)
    -- "Series: Subtitle" / "Series - Subtitle"
    add(expanded:match("^(.-)%s*[:%-]%s") or "")
    local w = words(expanded)
    for n = #w - 1, 2, -1 do
        add(table.concat(w, " ", 1, n))
    end
    return out
end

-- rough similarity between two titles, 0..1 (shared words over the longer one)
function Parser.similarity(a, b)
    local wa = words(Parser.normalize(Parser.expandParts(a)))
    local wb = words(Parser.normalize(Parser.expandParts(b)))
    if #wa == 0 or #wb == 0 then return 0 end
    local set, shared = {}, 0
    for _, x in ipairs(wb) do set[x] = true end
    for _, x in ipairs(wa) do if set[x] then shared = shared + 1 end end
    return shared / math.max(#wa, #wb)
end

-- for comparing titles
function Parser.normalize(s)
    if not s then return "" end
    s = s:lower()
    s = s:gsub("[%p]", " ")
    s = s:gsub("%s+", " ")
    return trim(s)
end

return Parser
