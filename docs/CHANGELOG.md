# CHANGELOG.md

All notable changes to this project, newest first.

Format: `## [version or date] — description`
Under each entry: bullet points for what was added, changed, or removed.

---

## [2026-05-06] — Stage 1 infrastructure + MatchService

- Added `default.project.json` (Rojo project), `wally.toml`, `selene.toml`, `stylua.toml`
- Added `src/shared/Constants.lua` — Phase enum (LOBBY, PREP, ACTIVE, RESULTS), all timing values, MAX_ROUNDS, MIN_PLAYERS
- Added `src/shared/Types.lua` — `Phase` and `RoundStatePayload` type exports
- Added `src/shared/WeaponData.lua` — stub, populated when GunService is built
- Added `src/shared/ZoneData.lua` — stub, populated when ZoneService is built
- Added `src/server/RemoteSetup.server.lua` — creates all RemoteEvents and RemoteFunctions in ReplicatedStorage/Remotes at server start
- Added `src/server/MatchService.server.lua` — full match loop: Lobby → (Prep → Active → Results) × 5, fires RoundStateChanged every second, handles GetMatchConfig for late-joining clients, exposes RoundEndedEarly BindableEvent for ObjectiveService
- Updated `docs/NAMING.md` — added PREP phase, corrected file extension table (`.server.lua`, `.client.lua`, `.lua`)
- Updated `docs/ROADMAP.md` — checked off Stage 1 items and MatchService

---

## [2026-05-06] — Project initialized

- Created `CLAUDE.md` with game concept, toolchain, folder structure, server/client rules, build order, and Claude behavior guidelines
- Created `docs/PROJECT_RULES.md`
- Created `docs/PROJECT_MAP.md`
- Created `docs/NAMING.md`
- Created `docs/ROADMAP.md`
- Created `docs/CHANGELOG.md`

No game code written yet. Infrastructure and documentation only.
