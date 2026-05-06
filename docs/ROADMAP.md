# ROADMAP.md

Planned build sequence. Work top to bottom. Do not skip ahead.

---

## Milestone 0 — First playable

A 5-round attackers vs defenders match on one small suburban map. Attackers plant reality anchors. Defenders try to stop them. No monsters yet. This proves the core loop works before anything else is added.

---

## Build order

### Stage 1 — Infrastructure

- [ ] **Folder structure** — create all instance folders in Workspace, ReplicatedStorage, ServerScriptService, StarterGui, StarterPlayer per the layout in `CLAUDE.md`
- [ ] **Config modules** — `Constants`, `Types`, `WeaponData`, `ZoneData` in `ReplicatedStorage/Modules`; stub entries only, fill data as systems need it
- [ ] **Remotes** — create all RemoteEvents and RemoteFunctions listed in `PROJECT_MAP.md` inside `ReplicatedStorage/Remotes`

### Stage 2 — Match loop

- [ ] **MatchService** — round counter, phase machine (Lobby → Active → Results), round timer, calls `RoundStateChanged`
- [ ] **MatchController** — listens to `RoundStateChanged`, drives `MatchUI` (countdown, results screen)
- [ ] **TeamService** — assigns players to Attackers or Defenders, selects spawn, fires `TeamAssigned`
- [ ] **ObjectiveService** — tracks anchor plant progress, fires `ObjectiveUpdated` and `ObjectiveComplete`; `ObjectiveComplete` triggers `MatchService` to end round

Test gate: two players can join, get teamed, a round starts and ends, teams reset.

### Stage 3 — UI basics

- [ ] **Basic UI** — `HUD` frame (health, ammo placeholders), `MatchUI` (round number, timer, phase label), `ObjectiveUI` (anchor progress bar)

Test gate: all UI updates correctly from remote events with no gameplay yet.

### Stage 4 — Combat

- [ ] **GunService** — receives `WeaponFired`, validates raycast and timing, calls `DamageService`
- [ ] **GunController** — input handling, client-side raycast, viewmodel placeholder, fires `WeaponFired`, listens for `HitConfirmed` to show hitmarker
- [ ] **DamageService** — applies health changes, fires `HealthChanged`, kills player if health reaches 0
- [ ] **MovementController** — character feel, camera, footstep sounds; no server component

Test gate: players can shoot and kill each other; health updates on the HUD; kills are server-authoritative.

### Stage 5 — World

- [ ] **DestructionService** — listens for explosions or trigger events, manages destruction state of parts in `Workspace/Destructibles`, fires `PartDestroyed`
- [ ] **CorpseService** — spawns a corpse model on kill, persists it through round transitions, clears on match end

Test gate: shooting a destructible breaks it; dead players leave a body; bodies clear after match ends.

### Stage 6 — AI

- [ ] **MonsterService** — individual monster agents with simple pathfinding, attack logic targeting both teams
- [ ] **HordeService** — wave timing and spawn budget, escalates over rounds, calls `MonsterService:SpawnMonster()`

Test gate: monsters spawn, chase players, deal damage, and die correctly.

### Stage 7 — Polish

- [ ] **CutsceneController** — intro/outro sequences driven by `RoundStateChanged`; client-only

---

## Milestone 1 — Second map

Once Milestone 0 is stable and fun on the suburban map:

- New map with different defender type (e.g. scientists)
- New zone effect (one broken-reality distortion)
- Defender character skin swap
- Any balance fixes from Milestone 0 playtesting

---

## Milestone 2 — Monsters in core loop

- Integrate monsters into standard match (not just test mode)
- Tune horde budget so monsters threaten both sides without dominating
- Add monster kill reward (small, server-validated)

---

## Milestone 3 — Expanded content

Items to add after the core loop is proven, in no fixed order:

- Additional maps
- Additional weapons with distinct stats
- Defender faction variety (militia, survivors)
- Extended broken-reality zone effects (gravity, time dilation)
- Spectator mode
- Round replay summary screen

---

## Not on the roadmap (yet)

Do not design or stub these until a milestone explicitly adds them:

- Ranked / matchmaking
- Cosmetics / shop
- Persistent progression
- Custom game modes
