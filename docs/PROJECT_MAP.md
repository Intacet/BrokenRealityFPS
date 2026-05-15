# PROJECT_MAP.md

How the systems connect. Read this before adding a new system or remote.

---

## Data flow overview

```
Player input
  └─ Controller (client)
       └─ RemoteEvent fired to server
            └─ Service (server) validates + acts
                 ├─ Mutates server state
                 └─ RemoteEvent fired to all relevant clients
                      └─ Controller/UI updates presentation
```

The client never mutates authoritative state directly. Every gameplay action is a request to the server.

---

## System map

### Match lifecycle

```
MatchService
  │  owns: round number, match phase (Lobby / Active / Results), timers
  │  fires: RoundStateChanged → all clients
  │
  ├─ TeamService
  │    owns: team assignments, spawn selection
  │    fires: TeamAssigned → individual client
  │
  └─ ObjectiveService
       owns: anchor plant state, capture progress
       fires: ObjectiveUpdated → all clients
            ObjectiveComplete → all clients (triggers round end via MatchService)
```

### Combat

```
GunController (client)
  │  owns: input, client-side raycast (unverified), viewmodel, recoil visual
  │  fires: WeaponFired {origin, direction, tick} → server
  │
  └─ GunService (server)
       validates: raycast, timing, ammo state
       calls: DamageService:Apply()
       fires: HitConfirmed → firing client (hitmarker)

GunService (server)
  │  owns: weapon identity for this stage — Constants.DEFAULT_WEAPON is the single source
  │    of truth; the client never decides which weapon is equipped
  │  AmmoChanged payload: weaponName (Constants.DEFAULT_WEAPON), mag, reserve
  │    GunController receives weaponName but ignores it; HUD displays it
  │
DamageService (server)
  │  owns: all health mutation
  │  blocks same-team damage when Constants.FRIENDLY_FIRE_ENABLED == false (server-side only;
  │    the client never decides whether a shot is friendly fire)
  │  calls: CorpseService:Spawn() on kill
  └─ fires: HealthChanged → affected client
```

### World state

```
DestructionService (server)
  │  owns: destruction state of all parts in Workspace/Destructibles
  │  fires: PartDestroyed → all clients (visual FX trigger)
  │
CorpseService (server)
  │  owns: corpse models in Workspace/CorpseFolder
  │  persists corpses across rounds, clears on match end
  │
ZoneService (server)
  │  owns: per-map physics overrides (gravity, walkspeed, fog density)
  └─ fires: ZoneEffectApplied → all clients (visual overlay trigger)
```

### AI

```
MonsterService (server)
  │  owns: individual monster agents, pathfinding, attack logic
  │  targets: both attacker and defender teams
  │
HordeService (server)
  │  owns: wave timing, spawn budget, escalation across rounds
  └─ calls: MonsterService:SpawnMonster()
```

### Presentation (client only, no server impact)

```
MovementController      -- camera, character feel, footsteps
CutsceneController      -- intro/outro sequences, triggered by RoundStateChanged
HUD                     -- driven by HealthChanged, TeamStatusUpdate, AmmoChanged, RoundStateChanged
ObjectiveUI             -- driven by ObjectiveUpdated, ObjectiveComplete
MatchUI                 -- driven by RoundStateChanged
CrosshairUI             -- driven by RoundStateChanged; exposes ShowHitmarker()
ViewModelController     -- driven by RoundStateChanged; exposes PlayFireAnimation(), GetBarrelTipCFrame()
DeathScreen             -- driven by RagdollApplied (death trigger), RoundStateChanged (PREP cleanup)
KillFeedUI              -- driven by KillFeed; top-right scrolling kill entries, max 5, fade after display time
```

### StarterGui / UI source mapping

**Current stage:** UI is created entirely at runtime by client controllers. There is no static `StarterGui` content in the Rojo source tree.

- All ScreenGui instances (`HUD`, `MatchUI`, `DeathScreen`, `KillFeedUI`, `CrosshairUI`) are built programmatically in `init(playerGui)` methods inside `src/client/UI/*.lua` ModuleScripts.
- `ClientInit.client.lua` calls each `init(playerGui)` at startup, passing `Players.LocalPlayer.PlayerGui`.
- **`default.project.json` does not map StarterGui to any source folder.** Rojo leaves StarterGui unmanaged; the built-in service is populated at runtime by controllers, not by synced disk files.
- **No `src/ui/` folder is expected or used at this stage.** The empty `src/ui/` directory that exists on disk has no files and is not referenced by Rojo.

**When a `src/ui/` folder becomes necessary** (e.g. for static decal frames, pre-built ObjectiveUI assets, or map-specific loading screens):
1. Add files to `src/ui/` with the `.lua` or `.client.lua` extension as appropriate.
2. Restore the StarterGui mapping in `default.project.json`:
   ```json
   "StarterGui": {
     "$className": "StarterGui",
     "$path": "src/ui"
   }
   ```
3. Update this section and `docs/CHANGELOG.md`.

### Client initialization pattern

All client controllers are **ModuleScripts** (`.lua`). They do not run automatically.
`ClientInit.client.lua` is the only **LocalScript** in the Controllers folder. It:

1. `require()`s each controller in dependency order
2. Calls each controller's `:Start()` method in the same order
3. Wraps each step in `pcall` — one failed controller does not block the others

**Current initialization order:**
```
ClientInit.client.lua
  1. MatchController:Start()         -- must be first; owns GetPhase() which GunController reads
  2. MatchUI:init()+Start()          -- no controller deps; connects RoundStateChanged; needs PlayerGui
  3. HUD:init()+Start()              -- no controller deps; connects HealthChanged, TeamStatusUpdate, RoundStateChanged; needs PlayerGui
  4. DeathScreen:init()+Start()      -- no controller deps; connects RagdollApplied, RoundStateChanged; needs PlayerGui
  5. KillFeedUI:init()+Start()       -- no controller deps; connects KillFeed; needs PlayerGui
  6. CrosshairUI:init()+Start()      -- no controller deps; exposes ShowHitmarker(); needs PlayerGui
  7. ViewModelController:Start()     -- no controller deps; exposes PlayFireAnimation(), GetBarrelTipCFrame()
  8. SoundController:init()+Start()  -- no controller deps; no PlayerGui; must start before GunController
  9. GunController:Start()           -- reads MatchController:GetPhase(); calls ViewModelController, CrosshairUI, SoundController
```

**Three initialization helpers:**
- `loadAndStart(name, getModule)` — for controllers with no PlayerGui dependency: `require → Start()`
- `loadInitAndStart(name, getModule)` — for UI modules that create ScreenGui instances: `require → init(playerGui) → Start()`
- `loadInitNoGuiAndStart(name, getModule)` — for modules with `init()` (no PlayerGui arg) followed by `Start()`

**Adding a new controller:**
- Create the file as `src/client/NewController.lua` (ModuleScript, not `.client.lua`)
- Expose a `:Start()` method that connects all events and listeners
- Use `loadAndStart()` if no PlayerGui is needed; use `loadInitAndStart()` if the module creates ScreenGui elements
- Add the call in `ClientInit.client.lua` at the correct position
- Document the dependency order in a comment above the call

---

## Rojo-managed vs unmanaged Studio containers

The table below lists every top-level Studio container and whether Rojo tracks it via `default.project.json`. **Unmanaged containers are not synced — any script placed in them by a Marketplace import or manual Studio edit will not appear in git and will not be detected by Rojo.**

| Studio container | Rojo-managed? | Source path | Notes |
|---|---|---|---|
| `ReplicatedStorage/Remotes` | Partial — folder only | (no `$path`) | Folder exists in project tree; RemoteEvent instances are created at runtime by `RemoteSetup.server.lua`, not synced from disk |
| `ReplicatedStorage/Modules` | Yes | `src/shared/` | All shared ModuleScripts |
| `ServerScriptService/Services` | Yes | `src/server/` | All server Scripts and ModuleScripts |
| `StarterPlayer/StarterPlayerScripts/Controllers` | Yes | `src/client/` | All client LocalScripts and ModuleScripts |
| `StarterGui` | **No** | (none) | UI is created at runtime by client controller `init()` methods. No static disk source. See DEBT-035. |
| `StarterPlayer/StarterCharacterScripts` | **No** | (none) | Not mapped. Any script placed here by an asset import is invisible to Rojo and git. See DEBT-031. |
| `StarterPack` | **No** | (none) | Not mapped. |
| `ReplicatedFirst` | **No** | (none) | Not mapped. |
| `Lighting` | **No** | (none) | Not mapped. Effects (BlurEffect, EqualizerSoundEffect) created at runtime by DeathScreen. |
| `SoundService` | **No** | (none) | Not mapped. |
| `Workspace/Map` | Partial — folder only | (no `$path`) | Static geometry placed manually in Studio |
| `Workspace/Spawns`, `/Objectives`, `/Destructibles`, `/MonsterSpawns`, `/CorpseFolder` | Partial — folder only | (no `$path`) | Folders exist; content placed manually in Studio |

> **Warning:** Any Script or LocalScript found in an unmanaged container after a Marketplace or `.rbxm` import will not appear in git and can silently alter runtime behavior — including camera, character movement, and game state. Follow the asset import safety checklist in `CLAUDE.md` and `docs/PROJECT_RULES.md` after every import.

---

## Workspace layout

```
Workspace
  Map/              static geometry, never modified at runtime
  Spawns/
    Attackers/      spawn parts referenced by TeamService
    Defenders/
  Objectives/       anchor parts referenced by ObjectiveService
  Destructibles/    parts owned by DestructionService
  MonsterSpawns/    spawn nodes referenced by HordeService
  CorpseFolder/     populated and cleared by CorpseService
```

---

## Remote registry

Add a row here **before** implementing any new remote. Every row must have exactly one entry in Fired by and Listened by. If the system is not yet built, write `pending`.

| Name | Type | Fired by | Listened by | Purpose |
|------|------|----------|-------------|---------|
| `WeaponFired` | RemoteEvent | `GunController.lua` | `GunService.server.lua` | Client requests hit validation |
| `HitConfirmed` | RemoteEvent | `GunService.server.lua` | `GunController.lua`, `SoundController.lua` | Server confirms hit for cosmetic hitmarker and hit sound |
| `HealthChanged` | RemoteEvent | `DamageService.lua` | `GunController.lua`, `HUD.lua` | Server sends updated health to affected client |
| `AmmoChanged` | RemoteEvent | `GunService.server.lua` | `GunController.lua`, `HUD.lua` | Server sends updated weapon name, magazine, and reserve ammo after each shot or reload; payload: `weaponName: string, mag: number, reserve: number` |
| `ReloadRequest` | RemoteEvent | `GunController.lua` | `GunService.server.lua` | Client requests a magazine reload |
| `RoundStateChanged` | RemoteEvent | `MatchService.server.lua` | `MatchController.lua`, `MatchUI.lua`, `HUD.lua`, `CrosshairUI.lua`, `ViewModelController.lua` | Phase, round, timer, winner, and win-count updates every tick |
| `TeamAssigned` | RemoteEvent | `TeamService.server.lua` | `MatchUI.lua` (pending) | Tells each client their team for this round |
| `TeamStatusUpdate` | RemoteEvent | `TeamService.server.lua` | `HUD.lua` | Alive count per team broadcast after each death |
| `RagdollApplied` | RemoteEvent | `RagdollService.lua` | `DeathScreen.lua`, `SoundController.lua` | Notifies all clients a player died; triggers death experience on the dying client |
| `KillFeed` | RemoteEvent | `DamageService.lua` | `KillFeedUI.lua` | Broadcasts killer and victim display names and team names to all clients for the kill feed |
| `ObjectiveUpdated` | RemoteEvent | `ObjectiveService.server.lua` | pending (ObjectiveUI) | Anchor capture progress (0–1) |
| `ObjectiveComplete` | RemoteEvent | `ObjectiveService.server.lua` | pending (ObjectiveUI) | An objective was finished |
| `PartDestroyed` | RemoteEvent | pending | pending | Trigger destruction VFX on all clients |
| `ZoneEffectApplied` | RemoteEvent | pending | pending | Trigger visual overlay on all clients |
| `GetMatchConfig` | RemoteFunction | `MatchController.lua` | `MatchService.server.lua` | Client fetches current match state on join |
