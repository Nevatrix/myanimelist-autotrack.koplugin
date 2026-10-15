-- myanimelist-autotrack: keeps my MAL list in sync with whatever I open in koreader
-- https://github.com/Nevatrix/myanimelist-autotrack.koplugin

local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local T = require("ffi/util").template

local MalApi = require("malapi")
local Parser = require("malparser")
local Updater = require("updater")
local Wiki = require("wikivolumes")
local I18n = require("i18n")
local _ = I18n.t

local FINISH_THRESHOLD = 0.95 -- past this, the volume counts as read
local PROGRESS_DELAY = 15 -- seconds after a chapter change before sending it
local WIKI_TTL = 14 * 24 * 3600
local WIKI_MISS_TTL = 7 * 24 * 3600
local NOVEL_TYPES = { light_novel = true, novel = true }

local MALSync = WidgetContainer:extend{
    name = "malautotrack",
    is_doc_only = true,
}

function MALSync:init()
    local dir = DataStorage:getSettingsDir()
    self.settings = LuaSettings:open(dir .. "/malautotrack.lua")
    -- this used to be called malsync, carry over the old settings
    if not self.settings:has("mappings") then
        local old = LuaSettings:open(dir .. "/malsync.lua")
        for _, k in ipairs({ "mappings", "queue", "credentials", "enabled", "confirm_new" }) do
            if old:has(k) then self.settings:saveSetting(k, old:readSetting(k)) end
        end
    end
    self.mappings = self.settings:readSetting("mappings", {})
    self.queue = self.settings:readSetting("queue", {})
    if self.settings:readSetting("enabled") == nil then self.settings:saveSetting("enabled", true) end
    if self.settings:readSetting("confirm_new") == nil then self.settings:saveSetting("confirm_new", true) end
    if self.settings:readSetting("auto_update") == nil then self.settings:saveSetting("auto_update", true) end
    if self.settings:readSetting("use_wikipedia") == nil then self.settings:saveSetting("use_wikipedia", true) end
    I18n.set(self.settings:readSetting("language", "auto"))
    self:loadCredentials()
    self.ui.menu:registerToMainMenu(self)
end

-- dead simple .env parser, that's all I need
local function readEnv(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local env = {}
    for line in f:lines() do
        line = line:gsub("\r$", "")
        if not line:match("^%s*#") then
            local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
            if k then
                v = v:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
                if v ~= "" then env[k] = v end
            end
        end
    end
    f:close()
    return env
end

-- tokens refresh themselves and live in settings/malautotrack.lua.
-- the .env is only read the first time (or when the refresh token changes)
function MALSync:loadCredentials()
    local creds = self.settings:readSetting("credentials")
    local file_creds
    local plugin_dir = self.path or (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$"))
    local env = readEnv(plugin_dir .. "/.env")
    if env and env.MAL_CLIENT_ID then
        file_creds = {
            client_id = env.MAL_CLIENT_ID,
            refresh_token = env.MAL_REFRESH_TOKEN,
            access_token = env.MAL_ACCESS_TOKEN,
            -- if empty, we just refresh when MAL returns 401
            expires_at = tonumber(env.MAL_TOKEN_EXPIRES_AT),
        }
    end

    -- new refresh token in the .env = I pasted it by hand, so it wins
    if file_creds and file_creds.refresh_token and
       (not creds or creds.source_refresh_token ~= file_creds.refresh_token) then
        creds = {
            client_id = file_creds.client_id,
            access_token = file_creds.access_token,
            refresh_token = file_creds.refresh_token,
            expires_at = file_creds.expires_at,
            source_refresh_token = file_creds.refresh_token,
        }
        self.settings:saveSetting("credentials", creds)
        self.settings:flush()
    end

    if creds and creds.client_id and creds.refresh_token then
        self.api = MalApi:new(creds, function(new_creds)
            self.settings:saveSetting("credentials", new_creds)
            self.settings:flush()
        end)
    else
        self.api = nil
        logger.warn("MAL Autotrack: missing credentials (.env)")
    end
end

function MALSync:save()
    self.settings:saveSetting("mappings", self.mappings)
    self.settings:saveSetting("queue", self.queue)
    self.settings:flush()
end

function MALSync:onFlushSettings()
    self:save()
end

local function notify(text, timeout)
    UIManager:show(InfoMessage:new{ text = text, timeout = timeout or 3 })
end

function MALSync:getBookInfo()
    local file = self.ui.document and self.ui.document.file
    if not file then return nil end
    local info = Parser.parse(file)
    -- files like "Vol 03.cbz": use the folder name instead
    if info.title == "" then
        local parent = Parser.parentdir(file)
        if parent then info.title = Parser.parse(parent).title end
    end
    if info.title == "" then
        local props = self.ui.doc_props or {}
        if props.title then info.title = Parser.parse(props.title).title end
    end
    if info.title == "" then return nil end
    -- no chapters in the name? the toc might have them ("Blue Lock 32" ... "Blue Lock 40")
    if not info.chapter then
        local first, last = self:getTocRange()
        if first then info.chapter_start, info.chapter, info.from_toc = first, last, true end
    end
    info.key = Parser.normalize(info.title)
    info.file = file
    return info
end

-- first and last chapter number found in the toc, cached per document
function MALSync:getTocRange()
    if self.toc_range == false then return nil end
    if self.toc_range then return self.toc_range[1], self.toc_range[2] end
    self.toc_range = false
    local ok, toc = pcall(function()
        self.ui.toc:fillToc()
        return self.ui.toc.toc
    end)
    if not ok or type(toc) ~= "table" then return nil end
    local nums = {}
    for _, entry in ipairs(toc) do
        local n = Parser.chapterFromTitle(entry.title)
        if n then table.insert(nums, n) end
    end
    -- one random number isn't a chapter list
    if #nums < 2 then return nil end
    table.sort(nums)
    self.toc_range = { nums[1], nums[#nums] }
    return nums[1], nums[#nums]
end

function MALSync:getPercent()
    local ok, pct = pcall(function()
        if self.ui.document.info.has_pages then
            return self.ui.paging:getLastPercent()
        else
            return self.ui.rolling:getLastPercent()
        end
    end)
    return ok and pct or 0
end

function MALSync:onReaderReady()
    if not self.settings:isTrue("enabled") or not self.api then return end
    local info = self:getBookInfo()
    -- no volume or chapter means it's probably a regular book, skip it
    -- (can still be sent by hand from the menu)
    if not info or (not info.volume and not info.chapter) then return end
    self.finished_sent = false
    self.book_info = info
    self.best_chapter = nil
    self:enqueue(info, "open")
    -- small delay so opening the book doesn't lag
    UIManager:scheduleIn(2, function() self:flushIfOnline(true) end)
end

function MALSync:markFinished()
    if self.finished_sent or not self.settings:isTrue("enabled") or not self.api then return end
    if self:getPercent() < FINISH_THRESHOLD then return end
    local info = self:getBookInfo()
    if not info or (not info.volume and not info.chapter) then return end
    self.finished_sent = true
    self:enqueue(info, "finish")
end

-- live chapter tracking from the toc
function MALSync:onPageUpdate(pageno)
    local info = self.book_info
    if not info or not pageno then return end
    local ok, title = pcall(function() return self.ui.toc:getTocTitleByPage(pageno) end)
    local n = ok and Parser.chapterFromTitle(title)
    if not n then return end
    -- toc entry outside the file's range is probably something else
    if info.chapter_start and (n < info.chapter_start or n > info.chapter) then return end
    if n <= (self.best_chapter or info.chapter_start or 0) then return end
    self.best_chapter = n
    -- wait until I stop flipping pages before sending anything
    if not self.progress_task then
        self.progress_task = function() self:pushProgress() end
    end
    UIManager:unschedule(self.progress_task)
    UIManager:scheduleIn(PROGRESS_DELAY, self.progress_task)
end

function MALSync:pushProgress(no_flush)
    if self.progress_task then UIManager:unschedule(self.progress_task) end
    local info = self.book_info
    if not info or not self.best_chapter or self.best_chapter == self.progress_sent then return end
    self.progress_sent = self.best_chapter
    -- only the latest progress per series matters
    for i = #self.queue, 1, -1 do
        if self.queue[i].key == info.key and self.queue[i].event == "progress" then table.remove(self.queue, i) end
    end
    table.insert(self.queue, {
        key = info.key, title = info.title,
        volume = info.volume, volume_start = info.volume_start,
        chapter = self.best_chapter, event = "progress", time = os.time(),
    })
    self:save()
    if not no_flush then self:flushIfOnline(true) end
end

function MALSync:onEndOfBook()
    self:markFinished()
    self:flushIfOnline(true)
end

function MALSync:onCloseDocument()
    self:pushProgress(true)
    self:markFinished()
    -- can't show dialogs here, only send what already has an id
    self:flushIfOnline(false)
    self:save()
end

function MALSync:onNetworkConnected()
    UIManager:scheduleIn(1, function() self:flushIfOnline(true) end)
    -- look for a new version at most once a day
    local last = self.settings:readSetting("last_update_check") or 0
    if self.settings:isTrue("auto_update") and os.time() - last > 24 * 3600 then
        UIManager:scheduleIn(5, function() self:checkUpdate(false) end)
    end
end

function MALSync:getVersion()
    local ok, meta = pcall(dofile, self.path .. "/_meta.lua")
    return ok and meta.version or "?"
end

function MALSync:checkUpdate(interactive)
    self.settings:saveSetting("last_update_check", os.time())
    self.settings:flush()
    local current = self:getVersion()
    local release, err = Updater:latest()
    if not release then
        logger.warn("MAL Autotrack: update check failed", err)
        if interactive then notify(T(_("Couldn't check for updates: %1"), tostring(err)), 4) end
        return
    end
    if not Updater.isNewer(release.version, current) then
        if interactive then notify(T(_("You're on the latest version (%1)."), current)) end
        return
    end
    UIManager:show(ConfirmBox:new{
        text = T(_("There's a new version of MyAnimeList Autotrack: %1 (you have %2).\n\nUpdate now?"), release.version, current),
        ok_text = _("Update"),
        ok_callback = function()
            local ok, ierr = Updater:install(release, self.path, DataStorage:getDataDir() .. "/cache")
            if ok then
                UIManager:askForRestart(T(_("MyAnimeList Autotrack was updated to %1. Restart KOReader to use it."), release.version))
            else
                notify(T(_("Update failed: %1"), tostring(ierr)), 5)
            end
        end,
    })
end

function MALSync:enqueue(info, event)
    for _, item in ipairs(self.queue) do
        if item.key == info.key and item.event == event and item.volume == info.volume and item.chapter == info.chapter then
            return
        end
    end
    table.insert(self.queue, {
        key = info.key, title = info.title,
        volume = info.volume, volume_start = info.volume_start,
        chapter = info.chapter, chapter_start = info.chapter_start,
        event = event, time = os.time(),
    })
    self:save()
end

function MALSync:flushIfOnline(interactive)
    if #self.queue == 0 or not self.api then return end
    if NetworkMgr:isOnline() then
        self:flushQueue(interactive)
    end
end

function MALSync:flushQueue(interactive)
    if self.flushing then return end
    self.flushing = true
    local remaining = {}
    local sent = 0
    for _, item in ipairs(self.queue) do
        local mapping = self.mappings[item.key]
        if not mapping and interactive and not self.dialog_open then
            -- without an exact match this opens the picker and returns nil
            mapping = self:resolveMapping(item)
        end
        if mapping and mapping.ignore then -- luacheck: ignore 542
            -- ignored series, drop it
        elseif mapping and mapping.id then
            local ok, err = self:applyUpdate(mapping, item)
            if ok then
                sent = sent + 1
            elseif err == "network_error" then
                table.insert(remaining, item)
            else
                logger.warn("MAL Autotrack: dropped update", item.title, err)
            end
        else
            -- still waiting for me to pick the series
            table.insert(remaining, item)
        end
    end
    self.queue = remaining
    self.flushing = false
    self:save()
    if sent > 0 then logger.info("MAL Autotrack: sent", sent, "updates") end
end

-- volume -> chapters table from wikipedia, cached per series
function MALSync:getVolumeTable(mapping, manga)
    if not self.settings:isTrue("use_wikipedia") then return nil end
    local cache = self.settings:readSetting("wiki_cache", {})
    local id = tostring(mapping.id)
    local c = cache[id]
    local now = os.time()
    if c and ((c.vols and now - c.t < WIKI_TTL) or (not c.vols and now - c.t < WIKI_MISS_TTL)) then
        return c.vols
    end
    local alt = manga.alternative_titles or {}
    local titles = {}
    for _, tt in ipairs({ mapping.title_en, alt.en, manga.title, mapping.title }) do
        if tt and tt ~= "" then table.insert(titles, tt) end
    end
    local ok, vols, page = pcall(Wiki.lookup, titles)
    if not ok then
        logger.warn("MAL Autotrack: wikipedia lookup crashed", vols)
        return c and c.vols
    end
    if not vols and page == "network" then return c and c.vols end -- try again next time
    cache[id] = { t = now, vols = vols, page = vols and page or nil }
    self.settings:saveSetting("wiki_cache", cache)
    return vols
end

-- figures out what to send for one queued item
function MALSync:applyUpdate(mapping, item)
    local manga, err = self.api:getManga(mapping.id)
    if not manga then return nil, err end
    local cur = manga.my_list_status or {}
    local cur_status = cur.status
    local cur_vol = tonumber(cur.num_volumes_read) or 0
    local cur_ch = tonumber(cur.num_chapters_read) or 0
    local total_vol = tonumber(manga.num_volumes) or 0
    local total_ch = tonumber(manga.num_chapters) or 0
    local vols = self:getVolumeTable(mapping, manga)

    -- how far I've read, as far as this item can tell
    local vol_read, ch_read
    local v = item.volume_start or item.volume
    local c = item.chapter_start or item.chapter
    if item.event == "open" then
        -- opening volume 5 means I already read up to 4 (same for chapters)
        if v then vol_read = v - 1 end
        if c then ch_read = c - 1 end
        if vols and v and not c and vols[v] then ch_read = vols[v][1] - 1 end
        if vols and c and not v then
            local vv = Wiki.volumeOf(vols, c)
            if vv then vol_read = vv - 1 end
        end
    elseif item.event == "progress" then
        -- item.chapter is the chapter I'm in right now
        ch_read = item.chapter - 1
        if v then vol_read = v - 1 end
        if vols then vol_read = math.max(vol_read or 0, Wiki.volumesDone(vols, ch_read)) end
    else
        vol_read, ch_read = item.volume, item.chapter
        if vols and vol_read and not ch_read and vols[vol_read] then ch_read = vols[vol_read][2] end
        if vols and ch_read and not vol_read then vol_read = Wiki.volumesDone(vols, ch_read) end
    end

    local fields = {}
    if vol_read and vol_read > cur_vol then fields.num_volumes_read = vol_read end
    if ch_read and ch_read > cur_ch then fields.num_chapters_read = ch_read end

    local done = item.event == "finish" and (
        (total_vol > 0 and vol_read and vol_read >= total_vol)
        or (total_ch > 0 and ch_read and ch_read >= total_ch)
        or (not item.volume and not item.chapter and (manga.media_type == "one_shot" or total_vol == 1)))
    if done and cur_status ~= "completed" then
        fields.status = "completed"
        if total_vol > 0 then fields.num_volumes_read = total_vol end
        if total_ch > 0 then fields.num_chapters_read = total_ch end
    elseif cur_status ~= "completed" and cur_status ~= "reading" then
        fields.status = "reading"
    end

    if next(fields) == nil then return true end
    local res, uerr = self.api:updateMangaStatus(mapping.id, fields)
    if not res then return nil, uerr end
    local parts = {}
    if fields.status then table.insert(parts, fields.status) end
    if fields.num_volumes_read then table.insert(parts, T(_("vol. %1"), fields.num_volumes_read)) end
    if fields.num_chapters_read then table.insert(parts, T(_("ch. %1"), fields.num_chapters_read)) end
    if self.ui and self.ui.document then
        notify(T(_("MAL: %1 → %2"), manga.title, table.concat(parts, ", ")), 2)
    end
    return true
end

local function titlesOf(node)
    local t = { node.title }
    local alt = node.alternative_titles or {}
    if alt.en then table.insert(t, alt.en) end
    if alt.ja then table.insert(t, alt.ja) end
    for _, s in ipairs(alt.synonyms or {}) do table.insert(t, s) end
    return t
end

function MALSync:pickBest(key, results)
    local candidates = {}
    for _, node in ipairs(results) do
        if not NOVEL_TYPES[node.media_type] then table.insert(candidates, node) end
    end
    if #candidates == 0 then candidates = results end
    for _, node in ipairs(candidates) do
        for _, t in ipairs(titlesOf(node)) do
            if Parser.normalize(t) == key then return node, true, candidates end
        end
    end
    return candidates[1], false, candidates
end

function MALSync:setMapping(key, node)
    local alt = node.alternative_titles or {}
    self.mappings[key] = { id = node.id, title = node.title, title_en = alt.en ~= "" and alt.en or nil }
    self:save()
end

function MALSync:resolveMapping(item)
    local results, err = self.api:searchManga(item.title)
    if not results then
        logger.warn("MAL Autotrack: search failed", err)
        return
    end
    if #results == 0 then
        if self.ui and self.ui.document then
            notify(T(_("MAL: couldn't find \"%1\". Use the menu to search for it by hand."), item.title), 4)
        end
        return
    end
    local best, exact, candidates = self:pickBest(item.key, results)
    if exact or not self.settings:isTrue("confirm_new") then
        self:setMapping(item.key, best)
        return self.mappings[item.key]
    else
        self:showCandidates(item.key, item.title, candidates)
    end
end

function MALSync:showCandidates(key, title, candidates)
    local dialog
    local buttons = {}
    for i = 1, math.min(#candidates, 6) do
        local node = candidates[i]
        local label = node.title
        if node.media_type and node.media_type ~= "manga" then
            label = label .. " (" .. node.media_type .. ")"
        end
        if node.num_volumes and node.num_volumes > 0 then
            label = label .. T(_(" · %1 vols."), node.num_volumes)
        end
        table.insert(buttons, {{
            text = label,
            callback = function()
                UIManager:close(dialog)
                self.dialog_open = false
                self:setMapping(key, node)
                self:flushQueue(true)
            end,
        }})
    end
    table.insert(buttons, {
        {
            text = _("Search again…"),
            callback = function()
                UIManager:close(dialog)
                self.dialog_open = false
                self:manualSearch(key, title)
            end,
        },
        {
            text = _("Ignore series"),
            callback = function()
                UIManager:close(dialog)
                self.dialog_open = false
                self.mappings[key] = { ignore = true, title = title }
                self:flushQueue(false)
            end,
        },
        {
            text = _("Not now"),
            callback = function()
                UIManager:close(dialog)
                self.dialog_open = false
            end,
        },
    })
    dialog = ButtonDialog:new{
        title = T(_("MAL: which one is \"%1\"?"), title),
        buttons = buttons,
    }
    self.dialog_open = true
    UIManager:show(dialog)
end

function MALSync:manualSearch(key, title)
    local dialog
    dialog = InputDialog:new{
        title = _("Search MyAnimeList (or type the ID)"),
        input = title,
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function() UIManager:close(dialog) end,
            },
            {
                text = _("Search"),
                is_enter_default = true,
                callback = function()
                    local q = dialog:getInputText()
                    UIManager:close(dialog)
                    if not NetworkMgr:isOnline() then
                        notify(_("You need an internet connection."))
                        return
                    end
                    if q:match("^%s*%d+%s*$") then
                        local manga = self.api:getManga(tonumber(q))
                        if manga then
                            self:setMapping(key, manga)
                            notify(T(_("Linked to: %1"), manga.title))
                            self:flushQueue(true)
                        else
                            notify(_("Couldn't find that ID."))
                        end
                        return
                    end
                    local results = self.api:searchManga(q)
                    if results and #results > 0 then
                        self:showCandidates(key, title, results)
                    else
                        notify(_("No results."))
                    end
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function MALSync:addToMainMenu(menu_items)
    menu_items.malautotrack = {
        text = _("MyAnimeList Autotrack"),
        sorting_hint = "tools",
        sub_item_table_func = function() return self:getSubMenu() end,
    }
end

function MALSync:getSubMenu()
    local info = self:getBookInfo()
    local mapping = info and self.mappings[info.key]
    return {
        {
            text_func = function() return _("Language") .. ": " .. self:languageName() end,
            sub_item_table_func = function() return self:getLanguageMenu() end,
            separator = true,
        },
        {
            text = _("Enabled"),
            checked_func = function() return self.settings:isTrue("enabled") end,
            callback = function() self.settings:toggle("enabled"); self.settings:flush() end,
        },
        {
            text = _("Confirm new series before linking them"),
            checked_func = function() return self.settings:isTrue("confirm_new") end,
            callback = function() self.settings:toggle("confirm_new"); self.settings:flush() end,
            separator = true,
        },
        {
            text = _("Use Wikipedia for volume/chapter info"),
            checked_func = function() return self.settings:isTrue("use_wikipedia") end,
            callback = function() self.settings:toggle("use_wikipedia"); self.settings:flush() end,
            separator = true,
        },
        {
            text_func = function()
                if not info then return _("Current book: not recognized") end
                local function range(a, b)
                    if a and b and a ~= b then return a .. "–" .. b end
                    return tostring(b)
                end
                local vol = info.volume and T(_(" · vol. %1"), range(info.volume_start, info.volume)) or ""
                local ch = info.chapter and T(_(" · ch. %1"), range(info.chapter_start, info.chapter)) or ""
                return T(_("Detected: %1%2%3"), info.title, vol, ch)
            end,
            enabled_func = function() return false end,
        },
        {
            text_func = function()
                if not mapping then return _("MAL series: not linked") end
                if mapping.ignore then return _("MAL series: ignored") end
                return T(_("MAL series: %1 (#%2)"), mapping.title, mapping.id)
            end,
            enabled_func = function() return false end,
        },
        {
            text_func = function()
                local c = mapping and mapping.id and (self.settings:readSetting("wiki_cache") or {})[tostring(mapping.id)]
                if not c then return _("Wikipedia: not checked yet") end
                if not c.vols then return _("Wikipedia: no chapter list found") end
                local n = 0
                for _ in pairs(c.vols) do n = n + 1 end
                return T(_("Wikipedia: %1 (%2 vols)"), c.page or "?", n)
            end,
            enabled_func = function() return false end,
        },
        {
            text = _("Change / search series on MAL…"),
            enabled_func = function() return info ~= nil and self.api ~= nil end,
            callback = function() self:manualSearch(info.key, info.title) end,
        },
        {
            text = _("Ignore this series"),
            enabled_func = function() return info ~= nil end,
            callback = function()
                self.mappings[info.key] = { ignore = true, title = info.title }
                self:save()
                notify(_("This series won't be synced."))
            end,
        },
        {
            text = _("Forget the link for this series"),
            enabled_func = function() return mapping ~= nil end,
            callback = function()
                self.mappings[info.key] = nil
                self:save()
                notify(_("Done. It'll be searched again next time."))
            end,
            separator = true,
        },
        {
            text = _("Sync now"),
            enabled_func = function() return info ~= nil and self.api ~= nil end,
            callback = function()
                self:enqueue(info, self:getPercent() >= FINISH_THRESHOLD and "finish" or "open")
                NetworkMgr:runWhenOnline(function() self:flushQueue(true) end)
            end,
        },
        {
            text_func = function() return T(_("Queued updates: %1"), #self.queue) end,
            keep_menu_open = true,
            callback = function()
                if #self.queue == 0 then return notify(_("Nothing queued.")) end
                local lines = {}
                for _, it in ipairs(self.queue) do
                    table.insert(lines, string.format("%s  %s v%s c%s", it.event, it.title, tostring(it.volume or "-"), tostring(it.chapter or "-")))
                end
                UIManager:show(InfoMessage:new{ text = table.concat(lines, "\n") })
            end,
        },
        {
            text = _("Clear queue"),
            callback = function() self.queue = {}; self:save() end,
        },
        {
            text = _("Check for updates automatically (once a day)"),
            checked_func = function() return self.settings:isTrue("auto_update") end,
            callback = function() self.settings:toggle("auto_update"); self.settings:flush() end,
        },
        {
            text_func = function() return T(_("Check for updates now (you have %1)"), self:getVersion()) end,
            callback = function()
                NetworkMgr:runWhenOnline(function() self:checkUpdate(true) end)
            end,
            separator = true,
        },
        {
            text = _("Test MAL connection"),
            callback = function()
                if not self.api then
                    return notify(_("The .env file is missing from the plugin folder."))
                end
                NetworkMgr:runWhenOnline(function()
                    local me, err = self.api:me()
                    if me then
                        notify(T(_("Connected as %1"), me.name), 4)
                    else
                        notify(T(_("Error: %1"), tostring(err)), 4)
                    end
                end)
            end,
        },
    }
end

function MALSync:languageName()
    local choice = self.settings:readSetting("language", "auto")
    for _, l in ipairs(I18n.languages) do
        if l.code == choice then return l.name end
    end
    return T(_("Automatic (KOReader: %1)"), I18n.koreaderLang())
end

function MALSync:getLanguageMenu()
    local items = {}
    local function add(code, label)
        table.insert(items, {
            text = label,
            radio = true,
            checked_func = function() return self.settings:readSetting("language", "auto") == code end,
            callback = function()
                self.settings:saveSetting("language", code)
                self.settings:flush()
                I18n.set(code)
            end,
        })
    end
    add("auto", T(_("Automatic (KOReader: %1)"), I18n.koreaderLang()))
    for _, l in ipairs(I18n.languages) do add(l.code, l.name) end
    return items
end

return MALSync
