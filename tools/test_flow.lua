-- runs the whole flow against fake koreader and fake MAL
-- luajit tools/test_flow.lua (from the repo root)
package.path = "./?.lua;" .. package.path

local shown = {}
local function stub(t) return function() return t end end
local Widget = {}
function Widget:extend(o) return setmetatable(o or {}, { __index = self }) end
package.preload["ui/widget/container/widgetcontainer"] = stub(Widget)
local new = { new = function(_, o) return o end }
package.preload["ui/widget/buttondialog"] = stub(new)
package.preload["ui/widget/confirmbox"] = stub(new)
package.preload["ui/widget/infomessage"] = stub(new)
package.preload["ui/widget/inputdialog"] = stub(new)
package.preload["datastorage"] = stub({ getSettingsDir = function() return "/tmp" end, getDataDir = function() return "/tmp" end })
local LS = {}
LS.__index = LS
function LS.open() return setmetatable({ data = {} }, LS) end
function LS:readSetting(k, d) if self.data[k] == nil and d ~= nil then self.data[k] = d end return self.data[k] end
function LS:saveSetting(k, v) self.data[k] = v end
function LS:has(k) return self.data[k] ~= nil end
function LS:isTrue(k) return self.data[k] == true end
function LS:toggle(k) self.data[k] = not self.data[k] end
function LS.flush() end
package.preload["luasettings"] = stub(LS)
package.preload["ui/network/manager"] = stub({ isOnline = function() return true end, runWhenOnline = function(_, f) f() end })
package.preload["ui/uimanager"] = stub({
    show = function(_, w) table.insert(shown, w) end, close = function() end,
    scheduleIn = function(_, _, f) f() end, nextTick = function(_, f) f() end, unschedule = function() end,
})
package.preload["logger"] = stub({ info = function() end, warn = function() end, err = function() end, dbg = function() end })
package.preload["gettext"] = stub(function(s) return s end)
package.preload["ffi/util"] = stub({ template = function(s, ...)
    local a = { ... }
    return (s:gsub("%%(%d)", function(i) return tostring(a[tonumber(i)]) end))
end })
for _, m in ipairs({ "json", "socket.http", "ltn12", "socket", "socketutil" }) do package.preload[m] = stub({}) end

local Plugin = require("main")
local Updater = require("updater")
local Wiki = require("wikivolumes")
local wiki_calls = 0
local wiki_answer = nil
Wiki.lookup = function() wiki_calls = wiki_calls + 1; return wiki_answer, wiki_answer and "List of Blue Lock chapters" or "not_found" end

local fails = 0
local function check(name, cond)
    print((cond and "OK    " or "FAIL  ") .. name)
    if not cond then fails = fails + 1 end
end

-- fake MAL
local list_status, patches = {}, {}
local fake_api = {
    searchManga = function() return {
        { id = 114745, title = "Blue Lock", media_type = "manga", num_volumes = 0, alternative_titles = { en = "Blue Lock" } },
        { id = 1, title = "Blue Lock: Episode Nagi", media_type = "manga" },
    } end,
    getManga = function(_, id) return { id = id, title = "Blue Lock", num_volumes = 0, num_chapters = 0, media_type = "manga", my_list_status = list_status } end,
    updateMangaStatus = function(_, _, f)
        table.insert(patches, f)
        for k, v in pairs(f) do list_status[k] = v end
        return {}
    end,
}

local function open(file, pct, settings)
    local p = setmetatable({
        path = ".",
        ui = { document = { file = file, info = { has_pages = true } },
               paging = { getLastPercent = function() return pct end },
               menu = { registerToMainMenu = function() end },
               toc = { toc = {}, fillToc = function() end, getTocTitleByPage = function() return "" end } },
    }, { __index = Plugin })
    p:init()
    if settings then
        p.settings = settings
        p.mappings = settings:readSetting("mappings")
        p.queue = settings:readSetting("queue")
        p.pending_scores = settings:readSetting("pending_scores", {})
    end
    p.api = fake_api
    return p
end

local p = open("/mnt/us/documents/Manga/Blue Lock - Tomo 02 (#005-013).mobi", 0.3)
p:onReaderReady()
check("on open: reading, 1 vol, 4 ch", patches[1] and patches[1].status == "reading"
    and patches[1].num_volumes_read == 1 and patches[1].num_chapters_read == 4)
check("remembers the series", p.mappings["blue lock"] and p.mappings["blue lock"].id == 114745)

p.ui.paging.getLastPercent = function() return 0.97 end
p:onCloseDocument()
check("on finish: 2 vols, 13 ch", patches[2] and patches[2].num_volumes_read == 2 and patches[2].num_chapters_read == 13)
check("queue is empty", #p.queue == 0)

local before = #patches
local b = open("/mnt/us/documents/Libros/El maestro y Margarita.epub", 0.99)
b:onReaderReady(); b:onCloseDocument()
check("skips books without numbers", #patches == before and #b.queue == 0)

local q = open("/mnt/us/documents/Manga/Blue Lock - Tomo 01 (#001-004).mobi", 0.99, p.settings)
q:onReaderReady(); q:onEndOfBook()
check("never lowers progress", #patches == before)

local I18n = require("i18n")
local function detected()
    for _, item in ipairs(p:getSubMenu()) do
        local s = item.text_func and item.text_func()
        if s and (s:find("^Detected") or s:find("^Detectado")) then return s end
    end
end
I18n.set("en")
check("menu shows the range (en)", detected() == "Detected: Blue Lock · vol. 2 · ch. 5–13")
I18n.set("es")
check("menu shows the range (es)", detected() == "Detectado: Blue Lock · vol. 2 · cap. 5–13")
_G.G_reader_settings = { readSetting = function() return "pt_BR" end }
I18n.set("auto")
check("auto falls back to english", I18n.lang == "en")
_G.G_reader_settings = { readSetting = function() return "es" end }
I18n.set("auto")
check("auto follows koreader", I18n.lang == "es")
_G.G_reader_settings = nil

check("version 0.2 > 0.1", Updater.isNewer("v0.2", "0.1"))
check("version 0.1.1 > 0.1", Updater.isNewer("v0.1.1", "0.1"))
check("version 0.1 = 0.1", not Updater.isNewer("v0.1", "0.1"))
check("version 0.10 > 0.9", Updater.isNewer("v0.10", "0.9"))

-- live chapters from the toc ---------------------------------------------
list_status.num_chapters_read, list_status.num_volumes_read, list_status.status = 0, 0, nil
patches = {}
local toc_titles = { [1] = "Blue Lock 32", [20] = "Blue Lock 33", [40] = "Blue Lock 34" }
local r = open("/mnt/us/documents/Manga/Blue Lock - Tomo 05.mobi", 0.1, p.settings)
r.ui.toc.toc = { { title = "Blue Lock 32" }, { title = "Blue Lock 33" }, { title = "Blue Lock 40" } }
r.ui.toc.getTocTitleByPage = function(_, pg)
    local best
    for page, tt in pairs(toc_titles) do if page <= pg and (not best or page > best) then best = page end end
    return best and toc_titles[best] or ""
end
wiki_answer = { { 1, 4 }, { 5, 13 }, { 14, 22 }, { 23, 31 }, { 32, 40 } }
p.settings:saveSetting("wiki_cache", nil) -- earlier tests cached a miss
r:onReaderReady()
check("toc gives the chapter range when the name doesn't", r.book_info.chapter_start == 32 and r.book_info.chapter == 40)
check("open uses toc: 4 vols, 31 ch", patches[1] and patches[1].num_volumes_read == 4 and patches[1].num_chapters_read == 31)
r:onPageUpdate(25)
check("entering ch 33 marks 32 read", patches[2] and patches[2].num_chapters_read == 32)
r:onPageUpdate(45)
check("entering ch 34 marks 33 read", patches[3] and patches[3].num_chapters_read == 33)
local n_before = #patches
r:onPageUpdate(22)
check("going back doesn't send anything", #patches == n_before)

-- wikipedia fills what the name is missing ---------------------------------
list_status.num_chapters_read, list_status.num_volumes_read = 0, 0
patches = {}
local w = open("/mnt/us/documents/Manga/Blue Lock v03.cbz", 0.99, p.settings)
w:onReaderReady()
check("vol only + wikipedia: open sets ch 13", patches[1] and patches[1].num_volumes_read == 2 and patches[1].num_chapters_read == 13)
w:onCloseDocument()
check("vol only + wikipedia: finish sets ch 22", patches[2] and patches[2].num_volumes_read == 3 and patches[2].num_chapters_read == 22)
local calls = wiki_calls
list_status.num_chapters_read, list_status.num_volumes_read = 0, 0
local w2 = open("/mnt/us/documents/Manga/Blue Lock - c020.cbz", 0.1, p.settings)
w2:onReaderReady()
check("chapter only + wikipedia: ch 20 is in vol 3, so 2 vols read", patches[3] and patches[3].num_volumes_read == 2 and patches[3].num_chapters_read == 19)
check("wikipedia is cached", wiki_calls == calls)

-- calibre/KCC style names and a title MAL can't find as-is ------------------
local queries = {}
local jojo4 = { id = 3008, title = "JoJo no Kimyou na Bouken Part 4: Diamond wa Kudakenai", media_type = "manga", num_volumes = 18,
    alternative_titles = { en = "JoJo's Bizarre Adventure Part 4: Diamond Is Unbreakable" } }
local jojo5 = { id = 1706, title = "JoJo no Kimyou na Bouken Part 5: Ougon no Kaze", media_type = "manga", num_volumes = 17,
    alternative_titles = { en = "JoJo's Bizarre Adventure Part 5: Golden Wind" } }
local jojo_api = setmetatable({
    searchManga = function(_, query)
        table.insert(queries, query)
        if query:find("Unbreakeable") or query:find("Diamond") then return {} end
        return { jojo5, jojo4 }
    end,
}, { __index = fake_api })
shown = {}
local j = open("/mnt/us/documents/KCC/Jojo's Bizarre Adventure P4 Diamond is Unbreakeable - Tomo 4 - KCC.mobi", 0.1, p.settings)
j.ui.doc_props = { authors = "KCC" }
j.api = jojo_api
j:onReaderReady()
check("drops the - KCC suffix", j.book_info.title == "Jojo's Bizarre Adventure P4 Diamond is Unbreakeable")
check("retries with shorter queries", #queries >= 2 and queries[1]:find("Part 4"))
local dlg = shown[#shown]
check("picker shows Part 4 first", dlg and dlg.buttons and dlg.buttons[1][1].text:find("Part 4: Diamond") ~= nil)

-- wikipedia table that doesn't fit the MAL entry gets ignored
local Plugin2 = j
p.settings:saveSetting("wiki_cache", { ["3008"] = { t = os.time(), vols = (function()
    local v = {}
    for i = 1, 129 do v[i] = { i * 9 - 8, i * 9 } end
    return v
end)() } })
check("wikipedia ignored when volumes don't fit", Plugin2:getVolumeTable({ id = 3008 }, jojo4) == nil)

-- score when a series gets completed -------------------------------------
local short = { id = 777, title = "Short Manga", media_type = "manga", num_volumes = 2, num_chapters = 10,
    alternative_titles = { en = "Short Manga" } }
local short_status = { status = "reading", num_volumes_read = 1, num_chapters_read = 5, score = 0 }
local short_api = setmetatable({
    searchManga = function() return { short } end,
    getManga = function() return setmetatable({ my_list_status = short_status }, { __index = short }) end,
    updateMangaStatus = function(_, _, f)
        table.insert(patches, f)
        for k, val in pairs(f) do short_status[k] = val end
        return {}
    end,
}, { __index = fake_api })
patches, shown = {}, {}
p.settings:saveSetting("queue", {}) -- leftovers from the jojo test
local s = open("/mnt/us/documents/Manga/Short Manga v02.cbz", 0.99, p.settings)
s.api = short_api
s:onReaderReady()
s:onEndOfBook()
local completed = false
for _, f in ipairs(patches) do if f.status == "completed" then completed = true end end
check("last volume completes the series", completed)
local dlg2 = shown[#shown]
check("asks for a score", dlg2 and dlg2.title and dlg2.title:find("What score") ~= nil)
dlg2.buttons[2][3].callback() -- 8
check("score 8 sent", patches[#patches].score == 8)
check("pending score cleared", next(s.pending_scores) == nil)

-- score asked at close waits for the next book
short_status.status, short_status.score = "reading", 0
patches, shown = {}, {}
local s2 = open("/mnt/us/documents/Manga/Short Manga v02.cbz", 0.99, p.settings)
s2.api = short_api
s2.settings.data.queue = {}
s2.queue = s2.settings.data.queue
s2.book_info = s2:getBookInfo()
s2:onCloseDocument()
check("no dialog while closing", #shown == 0 and next(s2.pending_scores) ~= nil)
local s3 = open("/mnt/us/documents/Libros/Some Novel.epub", 0.1, p.settings)
s3.api = short_api
s3:onReaderReady()
check("asked on the next open", shown[#shown] and shown[#shown].title:find("What score") ~= nil)

print(fails == 0 and "All good" or (fails .. " failed"))
if fails > 0 then os.exit(1) end
