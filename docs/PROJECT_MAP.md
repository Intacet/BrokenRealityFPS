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

## Remote registry (planned)

| Name | Type | Fired by | Purpose |
|------|------|----------|---------|
| `WeaponFired` | RemoteEvent | Client | Request hit validation |
| `HitConfirmed` | RemoteEvent | Server | Cosmetic hitmarker confirm |
| `HealthChanged` | RemoteEvent | Server | Update client health display |
| `RoundStateChanged` | RemoteEvent | Server | Drive all UI and phase transitions |
| `TeamAssigned` | RemoteEvent | Server | Tell client their team |
| `ObjectiveUpdated` | RemoteEvent | Server | Update capture progress UI |
| `ObjectiveComplete` | RemoteEvent | Server | Signal round end |
| `PartDestroyed` | RemoteEvent | Server | Trigger destruction VFX on client |
| `ZoneEffectApplied` | RemoteEvent | Server | Trigger visual overlay on client |
| `GetMatchConfig` | RemoteFunction | Client | Fetch config on join |

Add new remotes to this table before implementing them.
