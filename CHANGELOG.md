# Changelog

Generated from the commit history by `tools/changelog.py`.

## v0.2.0 (2026-10-15)

### Features
- **folders:** only sync books inside chosen manga folders ([b9888dc](https://github.com/Nevatrix/myanimelist-autotrack.koplugin/commit/b9888dc6f9a6551c537d4b4b4fe937769daccb33))
- **onhold:** suggest On hold for series not read in a while ([dab6c30](https://github.com/Nevatrix/myanimelist-autotrack.koplugin/commit/dab6c30e2f362a85f8220bffc93ce1a3aac7aaef))
- **score:** ask for a score when a series is completed ([5b6c0c0](https://github.com/Nevatrix/myanimelist-autotrack.koplugin/commit/5b6c0c0658ec17cbc684a79d1956f4aa931a325b))

### Fixes
- **queue:** resolve the open book's series before older leftovers ([1c81ecd](https://github.com/Nevatrix/myanimelist-autotrack.koplugin/commit/1c81ecde45c20fcd70ab9bd34ec53e351e85b19c))

### CI
- **release:** build release notes from conventional commits ([5df0057](https://github.com/Nevatrix/myanimelist-autotrack.koplugin/commit/5df005799ad9b089c5da417155db0ea21cea0442))

**Full diff:** [v0.1.1...v0.2.0](https://github.com/Nevatrix/myanimelist-autotrack.koplugin/compare/v0.1.1...v0.2.0)

## v0.1.1 (2026-10-15)

### Fixes
- **matching:** clean calibre/KCC suffixes and retry MAL search with shorter titles ([a3da6b7](https://github.com/Nevatrix/myanimelist-autotrack.koplugin/commit/a3da6b702d4b1b8043bafa8cf742e9f057875c25))

**Full diff:** [v0.1...v0.1.1](https://github.com/Nevatrix/myanimelist-autotrack.koplugin/compare/v0.1...v0.1.1)

## v0.1 (2026-10-14)

### Features
- sync manga reading progress to MyAnimeList ([4ba2070](https://github.com/Nevatrix/myanimelist-autotrack.koplugin/commit/4ba20700f9c29938671a6695d0c65c5602f45456))
- **i18n:** add English and Spanish UI strings ([c33bdda](https://github.com/Nevatrix/myanimelist-autotrack.koplugin/commit/c33bddabaafd083b91e6d173f23f62daa8a5fd58))
- **updater:** self-update from GitHub releases ([3a5b547](https://github.com/Nevatrix/myanimelist-autotrack.koplugin/commit/3a5b54782a177bb42089f84b3f373948bf8deda2))
- **wikipedia:** look up volume to chapter tables ([f136408](https://github.com/Nevatrix/myanimelist-autotrack.koplugin/commit/f1364086be12e0f25b3537b845baa350f0295976))
- **api:** add MyAnimeList v2 client with token refresh ([6914ecd](https://github.com/Nevatrix/myanimelist-autotrack.koplugin/commit/6914ecd573b38c5cb53b31bfc7b57956c5dc1dcd))
- **parser:** read series, volume and chapters from file names ([b6b28b6](https://github.com/Nevatrix/myanimelist-autotrack.koplugin/commit/b6b28b694c637e19a1791a33547cb82017269c18))

### Docs
- write README ([b65cf4b](https://github.com/Nevatrix/myanimelist-autotrack.koplugin/commit/b65cf4b07433d6c7f9e75d9669992edca1f2c3fe))

### CI
- build the plugin zip and publish a release on version tags ([97ac8c4](https://github.com/Nevatrix/myanimelist-autotrack.koplugin/commit/97ac8c4f40b18a44e88d7314c76fab3304daa2f7))
- lint and run tests on push and pull requests ([8e146a3](https://github.com/Nevatrix/myanimelist-autotrack.koplugin/commit/8e146a304c347f51d749a38ae774aa506e96149c))

### Chores
- **tools:** add script to build the .env from token notes ([6d56d1e](https://github.com/Nevatrix/myanimelist-autotrack.koplugin/commit/6d56d1ec8c5fc8646b2331516c7d7ec4fc11c672))
- ignore secrets and add luacheck config ([58fd334](https://github.com/Nevatrix/myanimelist-autotrack.koplugin/commit/58fd334b8407d1a554231d8626dc1e91f8faf274))
