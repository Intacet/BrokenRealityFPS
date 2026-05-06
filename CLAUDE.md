# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Game Concept

BrokenRealityFPS is a round-based multiplayer FPS on Roblox. Players compete inside "broken-reality zones" — maps where physical and visual rules are distorted (gravity shifts, mirrored geometry, time dilation, inverted color palettes). Each round cycles through: Lobby → Active (in-zone combat) → Results. Zone effects are scripted per-map and applied server-side, with client-side visual overlays synced via RemoteEvents.

## Toolchain

| Tool | Purpose |
|------|---------|
| [Rojo](https://rojo.space/) | Syncs the `src/` file tree into Roblox Studio |
| [Wally](https://wally.run/) | Luau package manager (`wally.toml`) |
| [Selene](https://kampfkarren.github.io/selene/) | Luau linter |
| [StyLua](https://github.com/JohnnyMorganz/StyLua) | Luau formatter |

## Commands

```bash
# Sync project into Roblox Studio (Studio must be open)
rojo serve default.project.json

# Build a place file without Studio
rojo build default.project.json -o BrokenRealityFPS.rbxlx

# Install/update Wally packages into Packages/
wally install

# Lint all Luau files
selene src/

# Format all Luau files in-place
stylua src/
```

## Folder Structure

```
src/
  server/          -- Scripts running in ServerScriptService (no client access)
    RoundManager   -- Authoritative round state machine (Lobby/Active/Results)
    ZoneManager    -- Loads zone maps, applies per-zone physics/effect configs
    HitDetection   -- Server-side raycast validation and damage application
    PlayerManager  -- Spawning, respawn, team assignment
  client/          -- LocalScripts in StarterPlayerScripts / StarterCharacterScripts
    WeaponController  -- Input, viewmodel animation, client-side raycast (unverified)
    ZoneOverlay       -- Visual distortion effects (blur, color correction, FOV)
    HUD               -- Round timer, kill feed, ammo, zone-effect indicator
    RoundUI           -- Lobby countdown, results screen
  shared/          -- ModuleScripts required by both sides via ReplicatedStorage
    Types            -- Luau type definitions (RoundState, ZoneConfig, WeaponConfig, etc.)
    Remotes          -- Single source of truth for all RemoteEvent/RemoteFunction names
    WeaponData       -- Stat tables for each weapon (damage, firerate, spread, etc.)
    ZoneData         -- Per-zone config (gravity multiplier, fog, effect list)
    Constants        -- Game-wide numeric constants (round duration, respawn time, etc.)
  ui/              -- ScreenGui trees built in code or via Rojo XML instances
Packages/          -- Wally-managed dependencies (committed, do not edit manually)
default.project.json
wally.toml
selene.toml
stylua.toml
```

## Server / Client Rules

**Server is authoritative for everything that affects game outcome:**
- Round state transitions live exclusively in `RoundManager`; clients receive state via a single `RoundStateChanged` RemoteEvent.
- Damage is never applied by the client. `WeaponController` fires a `WeaponFired` RemoteEvent carrying `{origin, direction, tick}`. `HitDetection` re-runs the raycast server-side, validates timing and position, then calls `PlayerManager:ApplyDamage()`.
- Zone effects that change physics (gravity, walkspeed) are set in `ZoneManager` on the server. Clients mirror cosmetic changes (fog, color grading) locally after receiving a `ZoneEffectApplied` event.

**Clients own their own visuals only:**
- `ZoneOverlay` and `HUD` are purely cosmetic and never gate gameplay logic.
- Viewmodel and muzzle flash are client-local; never replicate them.

**Remote conventions (defined in `shared/Remotes`):**
- `RemoteEvent` names: `PascalCase`, verb-first (`WeaponFired`, `RoundStateChanged`, `ZoneEffectApplied`).
- `RemoteFunction` names: `PascalCase`, question-phrased (`GetRoundConfig`).
- Never create a Remote outside `shared/Remotes`; require that module everywhere.

## Code Rules

- All files use **Luau strict mode**: `--!strict` at the top of every script.
- Types live in `shared/Types` and are imported, not redeclared locally.
- Module return shape: always a table (never a bare function). Service modules follow `Module:Method()` style; pure utility modules use `Module.method()`.
- No `wait()` — use `task.wait()`. No `spawn()` — use `task.spawn()`.
- Zone configs and weapon stats are **data, not code** — add new entries to `ZoneData`/`WeaponData` rather than branching logic on zone/weapon names.
- Server scripts never `require` anything under `src/client/`. Client scripts never `require` anything under `src/server/`.

## Development Order

When building a new feature from scratch, follow this sequence to avoid circular dependencies and untestable states:

1. **Shared types & constants** — define new types in `shared/Types`, add remotes in `shared/Remotes`, add stat tables in `WeaponData`/`ZoneData`.
2. **Server logic** — implement in the appropriate server module; keep it testable without a live client.
3. **RemoteEvent wiring** — server fires events; define the payload shape in `shared/Types`.
4. **Client receiver** — handle the event in the appropriate client module; update HUD or overlay.
5. **UI** — wire up `RoundUI`/`HUD` last, after the data flow is confirmed working.

When adding a new zone: add its config to `shared/ZoneData`, add the map model under `src/server/ZoneManager`, and add any new visual effects to `src/client/ZoneOverlay`. No other files should need to change.
