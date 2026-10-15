# myanimelist-autotrack.koplugin

KOReader plugin that keeps your MyAnimeList manga list updated while you read. No marking things as read by hand.

It figures out the series, volume and chapters from the file name:

```
Blue Lock - Tomo 02 (#005-013).mobi   ->  Blue Lock, vol 2, ch 5 to 13
Chainsaw Man v03 (Digital).cbz        ->  Chainsaw Man, vol 3
One Piece - c1100.cbz                 ->  One Piece, ch 1100
```

- When you **open** a volume it gets set to *Reading*, and everything before it counts as read (opening vol 2 = vol 1 and ch 1-4 read).
- While you **read**, it follows the book's table of contents. Moving from "Blue Lock 33" to "Blue Lock 34" marks chapter 33 as read (sent ~15 s after you stop flipping, so skimming doesn't spam MAL).
- When you **finish** it (95% or more) that volume gets added. If it was the last one, the series goes to *Completed* and you get asked for a score (1-10, or skip).
- The first time it sees a series it searches MAL. If the name isn't an exact match it asks you which one it is, and remembers it after that.
- No WiFi? Updates get queued and sent once you're back online.
- It never lowers your progress and never touches anything already *Completed*.
- Files with no volume or chapter number (novels, regular books) are skipped.
- Updates itself from this repo's releases.

Volume/chapter detection understands `v03`, `Vol. 3`, `Volume 3`, `Tomo 3`, `c012`, `ch. 12`, `Chapter 12`, `Capitulo 12` and `#005-013` style ranges.

### Where the numbers come from

| | Source |
|---|---|
| Series | File name (or folder name), linked to MAL once and remembered |
| Volume | File name |
| Chapters | File name, otherwise the table of contents (KCC conversions have one entry per chapter) |
| Live chapter | Table of contents while you read |
| Missing pieces | Wikipedia's "List of X chapters" page: volume → chapter table |

The Wikipedia part only kicks in when something is missing, e.g. `Chainsaw Man v03.cbz` (no chapters) or `One Piece - c1100.cbz` (no volume). It uses the official MediaWiki API, does one lookup per series and caches the result for two weeks. Volume numbers there follow the original Japanese release, which is what most translated editions use too. You can turn it off in the menu. Chapter list data comes from [Wikipedia](https://en.wikipedia.org/), CC BY-SA 4.0.

## Install

1. Download `myanimelist-autotrack.koplugin.zip` from the [latest release](https://github.com/Nevatrix/myanimelist-autotrack.koplugin/releases/latest).
2. Unzip it into `koreader/plugins/` on your e-reader. You should end up with `koreader/plugins/myanimelist-autotrack.koplugin/main.lua`.
3. Create the `.env` (see below) inside that folder.
4. Restart KOReader, open some manga and go to **Tools → MyAnimeList Autotrack → Test MAL connection**.

### Credentials (.env)

You need your own MAL client ID:

1. Go to <https://myanimelist.net/apiconfig> and create one. App type: `other`, redirect URL: `http://localhost`.
2. Get an access token and refresh token through OAuth2 + PKCE (`plain` method). It's covered in the [API docs](https://myanimelist.net/apiconfig/references/api/v2).
3. Copy `.env.example` to `.env` and fill it in:

```
MAL_CLIENT_ID=...
MAL_ACCESS_TOKEN=...
MAL_REFRESH_TOKEN=...
```

If you keep your tokens in a notes file (with `CLIENT` and the token JSON), `python tools/make_env.py path/to/notes` builds the `.env` for you.

After the first run the tokens are stored in `koreader/settings/malautotrack.lua` and refresh on their own.

On Windows, files starting with a dot are sometimes hidden. Double check the `.env` actually got copied.

## Menu

Under **Tools → MyAnimeList Autotrack**:

- **Language**: English or Español. By default it follows KOReader's language (and falls back to English).
- **Enabled**: turns everything on/off.
- **Confirm new series**: ask before linking a series that isn't an exact match.
- **Use Wikipedia**: fill in missing volume/chapter info from Wikipedia.
- **Ask for a score**: show the 1-10 score dialog when a series gets completed.
- **Detected / MAL series / Wikipedia**: what it parsed, which MAL entry it's linked to, and which Wikipedia list it found.
- **Change / search series**: search by hand or paste a MAL ID.
- **Ignore this series**: never sync this one.
- **Sync now**: send progress right away, even for files without numbers.
- **Queued updates**: what's waiting for WiFi.
- **Check for updates**: look for a new release. It also does this by itself once a day when it gets online.

Adding a language is just adding a table to `i18n.lua`.

## Updates

The plugin checks this repo's `releases/latest`. If there's something newer it asks first, downloads the zip, replaces the `.lua` files (your `.env` stays) and asks you to restart KOReader.

## Development

```
luajit tools/test_parser.lua   # file name parsing
luajit tools/test_wiki.lua     # wikipedia chapter list parsing
luajit tools/test_flow.lua     # full flow against a fake MAL
luacheck .
```

CI runs all of that on every push and PR.

To cut a release:

1. Bump `version` in `_meta.lua` (e.g. `"0.2"`).
2. Commit and push.
3. `git tag v0.2 && git push origin v0.2`

The release workflow checks the tag matches `_meta.lua`, builds the zip and publishes the release. Installed copies pick it up on their own.

## License

MIT
