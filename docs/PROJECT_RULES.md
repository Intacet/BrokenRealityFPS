# PROJECT_RULES.md

Rules that apply to every file in this project. These do not change per-feature.

---

## Script size

Do not write one giant script. One script per system. If a script is doing two unrelated things, split it.

## Config modules

Any value that may need tuning later — timers, damage numbers, round counts, distances, speeds — belongs in a config or data module in `ReplicatedStorage/Modules`, not hardcoded inside a service or controller. If a designer or developer would ever want to change a number without reading through logic code, it must be in a module.

## Server / client boundary

The server owns anything that affects the game outcome. The client owns presentation only.

**Server is responsible for:**
- match state and round transitions
- team assignment
- objective completion and tracking
- all damage and health changes
- destruction state of parts
- monster AI and pathfinding
- corpse persistence between rounds
- rewards and stat saving

**Client is responsible for:**
- player input
- camera movement
- recoil animation and viewmodel
- sound playback
- all UI
- hitmarkers (cosmetic only, not authoritative)
- cutscenes

**Never trust the client with:**
- damage values
- reward amounts
- objective state
- inventory contents
- destruction triggers
- win condition evaluation

## Remotes

All RemoteEvents and RemoteFunctions are defined in `ReplicatedStorage/Remotes`. Never create a Remote outside that folder. Never fire a Remote whose name is not listed there.

The server fires events to notify the client. The client fires events to request server action. The server validates every incoming client request before acting.

## Module shape

Every ModuleScript returns a table. Never return a bare function.

Services (server) use colon syntax:
```lua
local MyService = {}

function MyService:Start()
end

return MyService
```

Controllers (client) use the same shape. Utility modules in `ReplicatedStorage/Modules` use dot syntax.

## Luau

- `--!strict` at the top of every file, no exceptions.
- `task.wait()` not `wait()`. `task.spawn()` not `spawn()`. `task.delay()` not `delay()`.
- All types are defined in `ReplicatedStorage/Modules/Types` and imported where needed. Do not redefine types locally.

## Data over logic

Weapon stats, zone configs, monster configs, and map configs are data tables in `ReplicatedStorage/Modules`. Logic never branches on a weapon name or zone name directly — it reads from the data table.

## Cross-boundary requires

Server scripts (`src/server/`) never require client scripts (`src/client/`).
Client scripts (`src/client/`) never require server scripts (`src/server/`).
Both sides may require shared modules (`src/shared/`).

## Build discipline

Build one system at a time, server before client. Do not start the next system until the current one has been manually tested. See `ROADMAP.md` for the sequence.

## Explaining changes

Every time code is written or edited, explain:

1. **Every file that changes** — name each file and what specifically changed in it.
2. **How the new code connects** — describe how it fits into the existing system: which services call it, which remotes it uses, which modules it reads from.
3. **Maintenance risks** — call out anything that may become hard to change or debug later (tight coupling, assumptions about load order, growing conditionals, etc.).
4. **Test steps** — give concrete steps to verify the change works in Studio before moving on.

## Asset import safety checklist

Apply this checklist every time a Marketplace, Toolbox, `.rbxm`, or `.rbxmx` asset is imported into Studio.

**Before importing:**
- State which Studio containers the asset is expected to modify.

**After importing — inspect these unmanaged containers for new Scripts or LocalScripts:**
- `StarterPlayer.StarterCharacterScripts`
- `StarterGui`
- `StarterPack`
- `ReplicatedFirst`
- `Lighting`
- `SoundService`
- `Workspace` (and all descendants of any imported Model)

**For every Script or LocalScript found outside `src/`:**
- Delete it if it is a rig helper, camera controller, or other import artifact not needed by this project.
- Move it into the appropriate `src/` subfolder if it is intentionally part of the project, so Rojo tracks it and it appears in git.
- No Studio-only script may remain untracked unless it is explicitly approved and documented in `docs/TECHNICAL_DEBT.md`.

**Viewmodel and camera imports:**
- Delete or disable any LocalScript that touches `CameraType`, `camera.CFrame`, character movement, or `RenderStepped` camera logic. These override the project's first-person camera system.

**Verification:**
- If the import affects the camera, viewmodel, combat, or character controls, mark it as requiring Studio verification and do not claim it verified until tested in play mode.

---

## Persistent zone design rules (added 2026-05-15)

These rules apply to all new systems built for the persistent zone architecture. They do not override existing code quality rules.

**Loot and economy:**
- Do not instantly bank loot or cash from inside the zone. Securing value requires physically reaching a base terminal, deposit point, or extraction exit.
- Carried cash is always at risk. Secured funds are never lost on death. The system must maintain this distinction at all times — a server bug that accidentally secures undeposited cash violates the core loop.
- Death should hurt but never make the player quit. Always provide a weak free respawn option (free pistol or equivalent) so a player can re-enter immediately after dying with nothing.
- Keep re-entry fast. A player who dies should be able to return to the zone within a few seconds of choosing to respawn.

**Zone shops and base armory:**
- Zone shops accept carried cash only. They provide useful in-zone items (guns, ammo, consumables) but must not replace or shortcut base progression. A player should still need the base armory and secured funds for better loadouts and upgrades.
- Base armory purchases use secured funds only. The two economies must remain separate: spending carried cash in-zone is a tactical choice; spending secured funds at base is a progression choice.

**Periodic zone events:**
- Zone events (timed loot surges, monster waves, cash bounties) create pressure and reward aggression. They must not lock players into mandatory participation or turn the persistent zone into a round-based mode. A player who ignores an event should still be able to extract safely.

**Scope discipline:**
- Build persistent zone systems in small, testable stages. Do not build full inventory, base upgrade trees, shops, monsters, zone events, extraction, and death drops in one prompt.
- One new server-side system per task unless the systems are trivially coupled.
- Deferred systems (StashService, ProgressionService, InventoryService, ZoneEventService) must not be started until the core loop (zone → extract → deposit → armory → zone) is working in Studio.

**Legacy systems:**
- The round-based MatchService, TeamService, and ObjectiveService are legacy. Do not expand them or add round-specific features unless explicitly requested.
- If a legacy service conflicts with a new system, prefer building the new system alongside the legacy one and swapping later — do not delete legacy code without an explicit instruction.

---

## Server authority — persistent zone systems

The same server-owns-authoritative-state rule applies to all new systems. The client may display and request actions only.

**Server owns:**
- Carried cash balance per player
- Secured funds balance per player
- Inventory contents (equipped weapon, consumables held)
- Death drop bag creation, position, and contents
- Extraction success and secured-funds credit
- Shop and armory purchase validation and fulfillment
- Base upgrade state
- Loot object spawn positions and remaining contents
- Zone entry and exit gate state

**Client may:**
- Display balances sent by the server
- Fire RemoteEvents to request deposit, purchase, extraction, loot pickup, or respawn
- Show local-only prediction for visual feedback (e.g. wallet UI update on AmmoChanged), but treat server confirmation as authoritative

**Never trust the client with:**
- Cash amounts
- Inventory state
- Extraction success (a player cannot declare their own extraction valid)
- Death drop spawning or contents
- Shop prices or purchase results
