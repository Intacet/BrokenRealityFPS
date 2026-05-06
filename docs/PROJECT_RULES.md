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
