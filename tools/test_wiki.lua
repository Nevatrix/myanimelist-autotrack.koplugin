-- wikitext parser against the formats wikipedia chapter lists use
-- luajit tools/test_wiki.lua (from the repo root)
package.path = "./?.lua;" .. package.path
local Wiki = require("wikivolumes")

local fails = 0
local function check(name, cond)
    print((cond and "OK    " or "FAIL  ") .. name)
    if not cond then fails = fails + 1 end
end
local function span(v) return v and (v[1] .. "-" .. v[2]) or "nil" end

-- unnumbered bullets with nihongo templates, ref tags and a header template
local bullets = [==[
{{Graphic novel list/header
 | Width = 100%
 | Language = Japanese
}}
{{Graphic novel list
 | VolumeNumber    = 1
 | OriginalRelDate = November 16, 2018<ref name="v1">{{cite web|url=https://example.com|title=a|date=x}}</ref>
 | OriginalISBN    = 978-4-06-513607-0
 | ChapterList     =
* {{nihongo|"Dream"|夢|Yume}}
* {{nihongo|"Blue Lock"|ブルーロック|Burū Rokku}}
* {{nihongo|"Monster"|怪物|Kaibutsu}}
* {{nihongo|"Who"|誰|Dare}}
 | Summary = Yoichi Isagi [[Striker (association football)|striker]] ...
 | LineColor = #1A4B9C
}}
{{Graphic novel list
 | VolumeNumber    = 2
 | ChapterList     =
* {{nihongo|"a"|a|a}}
* {{nihongo|"b"|b|b}}
* {{nihongo|"c"|c|c}}
* {{nihongo|"d"|d|d}}
* {{nihongo|"e"|e|e}}
* {{nihongo|"f"|f|f}}
* {{nihongo|"g"|g|g}}
* {{nihongo|"h"|h|h}}
* {{nihongo|"i"|i|i}}
 | Summary = ...
}}
{{Graphic novel list/footer}}
]==]
local v = Wiki.parse(bullets)
check("bullets: vol 1 = 1-4 (got " .. span(v[1]) .. ")", span(v[1]) == "1-4")
check("bullets: vol 2 = 5-13 (got " .. span(v[2]) .. ")", span(v[2]) == "5-13")

-- numbered bullets, two columns
local numbered = [==[
{{Graphic novel list
 | VolumeNumber = 5
 | ChapterListCol1 =
* 032. {{nihongo|"x"|x|x}}
* 033. "y"
* 034. "z"
* 035. "w"
* 036. "w"
 | ChapterListCol2 =
* 037. "w"
* 038. "w"
* 039. "w"
* 040. "w"
 | Summary = s
}}
]==]
v = Wiki.parse(numbered)
check("numbered columns: vol 5 = 32-40 (got " .. span(v[5]) .. ")", span(v[5]) == "32-40")

-- {{Numbered list|start=..}}
local nlist = [==[
{{Graphic novel list
 | VolumeNumber = 3
 | ChapterList = {{Numbered list|start=17
 | {{nihongo|"a"|a|a}}
 | {{nihongo|"b"|b|b}}
 | "c"
 }}
 | Summary = s
}}
]==]
v = Wiki.parse(nlist)
check("Numbered list: vol 3 = 17-19 (got " .. span(v[3]) .. ")", span(v[3]) == "17-19")

-- <ol start>
local ol = [==[
{{Graphic novel list
 | VolumeNumber = 4
 | ChapterList = <ol start="23"><li>a</li><li>b</li><li>{{nihongo|c|c|c}}</li></ol>
}}
]==]
v = Wiki.parse(ol)
check("ol start: vol 4 = 23-25 (got " .. span(v[4]) .. ")", span(v[4]) == "23-25")

-- spin-off table further down the page must not clobber the main series
local spinoff = bullets .. [==[
{{Graphic novel list/header
 | Language = Japanese
}}
{{Graphic novel list
 | VolumeNumber = 1
 | ChapterList = {{Ordered list|start=1
 | "nagi 1"
 | "nagi 2"
 }}
}}
{{Graphic novel list/footer}}
]==]
v = Wiki.parse(spinoff)
check("spin-off ignored: vol 1 still 1-4 (got " .. span(v[1]) .. ")", span(v[1]) == "1-4")
check("spin-off ignored: vol 2 still 5-13 (got " .. span(v[2]) .. ")", span(v[2]) == "5-13")

-- a list split in parts keeps counting
local parts = numbered .. [==[
{{Graphic novel list/header}}
{{Graphic novel list
 | VolumeNumber = 6
 | ChapterList = {{Ordered list|start=41|a|b|c}}
}}
]==]
v = Wiki.parse(parts)
check("second table continues: vol 6 = 41-43 (got " .. span(v[6]) .. ")", span(v[6]) == "41-43")

-- sub pages
local subs = Wiki.subPages([==[
* [[List of One Piece chapters (1–186)|Chapters 1 to 186]]
{{:List of One Piece chapters (187–388)}}
]==])
check("sub pages found: " .. #subs, #subs == 2)

-- helpers
local vols = { { 1, 4 }, { 5, 13 }, { 14, 22 } }
check("volumeOf(10) = 2", Wiki.volumeOf(vols, 10) == 2)
check("volumesDone(13) = 2", Wiki.volumesDone(vols, 13) == 2)
check("volumesDone(12) = 1", Wiki.volumesDone(vols, 12) == 1)

print(fails == 0 and "All good" or (fails .. " failed"))
if fails > 0 then os.exit(1) end
