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

DamageService (server)
  │  owns: all health mutation
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
MovementController  -- camera, character feel, footsteps
CutsceneController  -- intro/outro sequences, triggered by RoundStateChanged
HUD                 -- driven by HealthChanged, AmmoChanged, RoundStateChanged
ObjectiveUI         -- driven by ObjectiveUpdated
MatchUI             -- driven by RoundStateChanged
```

### Client initialization pattern

All client controllers are **ModuleScripts** (`.lua`). They do not run automatically.
`ClientInit.client.lua` is the only **LocalScript** in the Controllers folder. It:

1. `require()`s each controller in dependency order
2. Calls each controller's `:Start()` method in the same order
3. Wraps each step in `pcall` — one failed controller does not block the others

**Current initialization order:**
```
ClientInit.client.lua
  1. MatchController:Start()  -- must be first; owns GetPhase() which GunController reads
  2. GunController:Start()    -- reads MatchController:GetPhase() on every shot
```

**Adding a new controller:**
- Create the file as `src/client/NewController.lua` (ModuleScript, not `.client.lua`)
- Expose a `:Start()` method that connects all events and listeners
- Add a `loadAndStart()` call in `ClientInit.client.lua` at the correct position
- Document the dependency order in a comment above the call

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
| `WeaponFired` | RemoteEvent | `GunController.client.lua` | `GunService.server.lua` | Client requests hit validation |
| `HitConfirmed` | RemoteEvent | `GunService.server.lua` | `GunController.client.lua` | Server confirms hit for cosmetic hitmarker |
| `HealthChanged` | RemoteEvent | `DamageService.lua` | `GunController.client.lua` | Server sends updated health to affected client |
| `RoundStateChanged` | RemoteEvent | `MatchService.server.lua` | `MatchController.client.lua` | Phase, round, and timer updates every tick |
| `TeamAssigned` | RemoteEvent | `TeamService.server.lua` | pending | Tells each client their team for this round |
| `ObjectiveUpdated` | RemoteEvent | pending | pending | Anchor capture progress (0–1) |
| `ObjectiveComplete` | RemoteEvent | pending | pending | An objective was finished; triggers round end |
| `PartDestroyed` | RemoteEvent | pending | pending | Trigger destruction VFX on all clients |
| `ZoneEffectApplied` | RemoteEvent | pending | pending | Trigger visual overlay on all clients |
| `GetMatchConfig` | RemoteFunction | `MatchController.client.lua` | `MatchService.server.lua` | Client fetches current match state on join |
