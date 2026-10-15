-- luajit tools/test_parser.lua (from the repo root)
package.path = "./?.lua;" .. package.path
local P = require("malparser")
local cases = {
    { "Chainsaw Man v03 (2021) (Digital) (1r0n).cbz", "Chainsaw Man", 3, nil },
    { "[Group] One Piece - c1100 [en].cbz", "One Piece", nil, 1100 },
    { "Frieren_Vol.05.epub", "Frieren", 5, nil },
    { "Berserk Tomo 12.cbr", "Berserk", 12, nil },
    { "/mnt/us/manga/Vinland Saga/Vinland Saga 07.cbz", "Vinland Saga", 7, nil },
    { "Captain Tsubasa Volume 2.cbz", "Captain Tsubasa", 2, nil },
    { "Dandadan Capitulo 150.cbz", "Dandadan", nil, 150 },
    { "Spy x Family v01 c005.cbz", "Spy x Family", 1, 5 },
    { "One.Piece.v01.cbz", "One Piece", 1, nil },
    { "Oyasumi Punpun.epub", "Oyasumi Punpun", nil, nil },
    { "Kaiju No. 8 v04.cbz", "Kaiju No. 8", 4, nil },
    { "/mnt/base-us/documents/Manga/Blue Lock - Tomo 02 (#005-013).mobi", "Blue Lock", 2, 13, 5 },
    { "Blue Lock - Tomo 01 (#001-004).mobi", "Blue Lock", 1, 4, 1 },
    { "El maestro y Margarita - Mijaíl Bulgákov.epub", "El maestro y Margarita - Mijaíl Bulgákov", nil, nil },
}
local fails = 0
for _, c in ipairs(cases) do
    local r = P.parse(c[1])
    local ok = r.title == c[2] and r.volume == c[3] and r.chapter == c[4] and (c[5] == nil or r.chapter_start == c[5])
    if not ok then fails = fails + 1 end
    print((ok and "OK  " or "FAIL") .. "  " .. c[1] .. "  ->  [" .. r.title .. "] vol=" .. tostring(r.volume) .. " cap=" .. tostring(r.chapter_start) .. "-" .. tostring(r.chapter))
end
local toc = {
    { "Blue Lock 34", 34 }, { "Chapter 12: The Plan", 12 }, { "Capitulo 5", 5 },
    { "c045", 45 }, { "Cover", nil }, { "Vol. 3", nil }, { "#101 - Return", 101 },
}
for _, c in ipairs(toc) do
    local got = P.chapterFromTitle(c[1])
    local ok = got == c[2]
    if not ok then fails = fails + 1 end
    print((ok and "OK  " or "FAIL") .. "  toc \"" .. c[1] .. "\" -> " .. tostring(got))
end
print(fails == 0 and "All good" or (fails .. " failed"))
if fails > 0 then os.exit(1) end
