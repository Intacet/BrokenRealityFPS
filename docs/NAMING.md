# NAMING.md

Naming conventions for every layer of the project.

---

## Scripts and modules

| Type | Convention | Example |
|------|-----------|---------|
| Server service | `PascalCase` + `Service` suffix | `MatchService`, `GunService` |
| Client controller | `PascalCase` + `Controller` suffix | `GunController`, `MovementController` |
| Shared utility module | `PascalCase`, no suffix | `Types`, `Constants`, `WeaponData` |
| Shared data table module | `PascalCase` + `Data` suffix | `WeaponData`, `ZoneData`, `MonsterData` |

Every service has exactly one matching controller. Their base names must match (`GunService` ↔ `GunController`).

---

## Luau identifiers

| Kind | Convention | Example |
|------|-----------|---------|
| Module-level constant | `SCREAMING_SNAKE_CASE` | `MAX_ROUNDS`, `ANCHOR_PLANT_TIME` |
| Local variable | `camelCase` | `roundTimer`, `currentPhase` |
| Module table | `PascalCase` | `MatchService`, `WeaponData` |
| Public method | `PascalCase` after colon | `MatchService:StartRound()` |
| Private helper (local function) | `camelCase` | `local function resetTimers()` |
| Type alias | `PascalCase` | `type RoundState = ...` |
| Enum-style string literal table | `PascalCase` table, `SCREAMING_SNAKE_CASE` keys | `Phase.LOBBY`, `Phase.ACTIVE` |

---

## RemoteEvents and RemoteFunctions

All remotes live in `ReplicatedStorage/Remotes` and are listed in `docs/PROJECT_MAP.md`.

| Type | Convention | Example |
|------|-----------|---------|
| RemoteEvent | `PascalCase`, verb-first | `WeaponFired`, `RoundStateChanged`, `PartDestroyed` |
| RemoteFunction | `PascalCase`, question-phrased | `GetMatchConfig`, `GetTeamData` |

---

## Roblox instances (Workspace, Studio)

| Instance type | Convention | Example |
|--------------|-----------|---------|
| Folder | `PascalCase` | `CorpseFolder`, `MonsterSpawns` |
| Part used as a marker | `PascalCase` + purpose noun | `AttackerSpawn`, `AnchorPoint` |
| Model | `PascalCase` | `SuburbanHouse`, `BrokenRifle` |
| ScreenGui | `PascalCase` + `UI` or full role | `HUD`, `MatchUI`, `ObjectiveUI` |
| Frame inside a Gui | `PascalCase`, role-first | `HealthBar`, `RoundTimer`, `KillFeed` |
| StringValue / IntValue attributes | `camelCase` | `teamName`, `roundsPlayed` |

---

## Files on disk (Rojo tree)

Rojo uses file extensions to decide the Roblox instance type. The filename (minus extension) becomes the instance name.

| Extension | Roblox instance | Used for |
|-----------|----------------|---------|
| `.server.lua` | Script | Files in `src/server/` |
| `.client.lua` | LocalScript | Files in `src/client/` |
| `.lua` | ModuleScript | Files in `src/shared/` and `src/ui/` |

```
src/server/MatchService.server.lua  → ServerScriptService/Services/MatchService  (Script)
src/client/GunController.client.lua → StarterPlayerScripts/Controllers/GunController  (LocalScript)
src/shared/WeaponData.lua           → ReplicatedStorage/Modules/WeaponData  (ModuleScript)
```

No abbreviations in file names. `GunController`, not `GunCtrl`.

---

## Teams

Internal team identifiers used in code:

| Role | Identifier string |
|------|------------------|
| Spec ops attackers | `"Attackers"` |
| Map-specific defenders | `"Defenders"` |
| AI monsters (not a Roblox Team) | `"Monsters"` |

The display name shown in UI may differ per map (e.g. `"Militia"`, `"Scientists"`). The internal identifier stays constant.

---

## Phases

Round phases used in `MatchService` and `RoundStateChanged` payloads:

```lua
Phase.LOBBY    -- waiting for players
Phase.PREP     -- brief countdown before the round starts
Phase.ACTIVE   -- round in progress
Phase.RESULTS  -- round ended, scores shown
```

Do not use raw strings like `"lobby"` or `"active"` in logic. Always use the `Phase` table from `ReplicatedStorage/Modules/Constants`.
