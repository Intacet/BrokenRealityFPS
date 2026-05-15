# PERSISTENT_ZONE_ROADMAP.md

Staged implementation plan for Broken Reality's persistent PvPvE zone shooter direction.

**This document is planning-only.** No stage represents completed work unless explicitly noted. Build one stage at a time. Do not start the next stage until the current stage passes Studio play-mode verification with MCP available. Each stage lists what is **not** allowed so scope does not creep forward.

Reference: `docs/PROJECT_MAP.md` — New Target Architecture section for the full service list.

---

## How to use this roadmap

1. Read the current stage's **Goal** and **Files likely affected**.
2. Write only what is listed. Stop at the **Not in this stage** boundary.
3. Verify in Studio (play mode, MCP required) before moving on.
4. Update `docs/CHANGELOG.md` and `docs/TECHNICAL_DEBT.md` when the stage is done.
5. Do not batch multiple stages into one prompt.

---

## Stage 0 — Reusable FPS foundation

**Status:** Partially complete. AR15 path built; some items below still need Studio verification.

### Goal

Establish a reliable single-weapon FPS foundation that the persistent zone systems can build on. Every subsequent stage depends on this being stable.

### Checklist

- [ ] AR15 identity uses `Constants.DEFAULT_WEAPON` on both server and client (done — see CHANGELOG 2026-05-15)
- [ ] AmmoChanged payload includes `weaponName` and HUD displays it (done — see CHANGELOG 2026-05-15)
- [ ] Ammo, reload, and HUD sync verified in Studio play mode (needs Studio verification)
- [ ] Server damage and death flow verified: shot lands → health decrements → ragdoll → kill feed (needs Studio verification)
- [ ] Basic viewmodel stable: model appears, fire animation plays, muzzle flash shows (needs Studio verification)
- [ ] Friendly-fire guard verified: same-team shots blocked, cross-team shots land (needs Studio verification)
- [ ] Shot origin/direction validation verified: fake origins rejected, normal shots pass (needs Studio verification)

### Files likely affected later

| File | Why |
|---|---|
| `src/server/GunService.server.lua` | clientTick validation (DEBT-014) when combat is stable |
| `src/client/MovementController.lua` | Stage 1 movement only after this stage passes |
| `src/server/DamageService.lua` | No changes expected |

### Not in this stage

- Recoil, spread, ADS, or weapon sway
- Slide, vault, or advanced movement
- Multiple weapons
- Animations beyond the fire snap
- Any persistent zone systems

### Studio / MCP verification required

Yes — every checklist item above must pass in live play mode before Stage 1 begins.

### Maintenance risks

- `SHOT_ORIGIN_MAX_DISTANCE = 12` studs may produce false rejections at high ping or during jump landings. Tune the value in Studio with simulated latency before locking it in.
- The `getTeamName()` fallback to `Player.Team.Name` protects late-joiners but has never been tested with a real late-join scenario. Include a mid-round join test in Stage 0 verification.

---

## Stage 1 — Zone / base state foundation

**Status:** Not started.

### Goal

Introduce the fundamental zone/base distinction. The server must know whether each player is in the safe base area or in the dangerous zone. This state gates everything in later stages — economy, death loss, shops, events all depend on knowing where the player is.

### Checklist

- [ ] `ZoneService` created (`src/server/ZoneService.lua`)
- [ ] Server tracks `playerZone: { [Player]: "Base" | "Zone" }` table
- [ ] Zone entrance trigger sets player to "Zone"
- [ ] Base entrance trigger (or extraction exit) sets player to "Base"
- [ ] Safe base spawn works (no damage, no PvP) — server enforces, not just client label
- [ ] Zone entrance spawn works
- [ ] Client controller (`ZoneController.lua`) displays current zone to player (optional HUD badge)
- [ ] `ZoneStateChanged` remote registered in `docs/PROJECT_MAP.md` before firing it
- [ ] Stage 0 still passes after Stage 1 is added

### Files likely affected later

| File | Why |
|---|---|
| `src/server/ZoneService.lua` | New file |
| `src/client/ZoneController.lua` | New file |
| `src/server/RemoteSetup.server.lua` | New `ZoneStateChanged` remote |
| `docs/PROJECT_MAP.md` | Remote registry row |
| `src/shared/Constants.lua` | Zone state constants |

### Not in this stage

- Carried cash or secured funds
- Economy of any kind
- Shops
- Death drops
- Zone events
- Monsters
- Inventory

### Studio / MCP verification required

Yes — zone transition triggers, safe base enforcement, and spawn selection must be verified in live play mode.

### Maintenance risks

- Zone entry/exit detection will use `BasePart.Touched`/`TouchEnded` or a region check. `Touched`/`TouchEnded` can fire multiple times per frame; debounce carefully.
- The "Base" state must be server-authoritative — a client that spoofs being in Base to avoid death-loss checks in Stage 2 is the primary attack vector. Never trust the client's claimed zone.

---

## Stage 2 — Economy foundation

**Status:** Not started.

### Goal

Introduce carried cash and secured funds as two separate server-authoritative currency tables. No spending yet — just earning, tracking, displaying, and the hard invariant that carried cash is at risk while secured funds are safe.

### Checklist

- [ ] `EconomyService` created (`src/server/EconomyService.lua`)
- [ ] `carriedCash: { [Player]: number }` table on server
- [ ] `securedFunds: { [Player]: number }` table on server
- [ ] Kills in zone grant carried cash (amount in `Constants.lua`)
- [ ] Loot pickups grant carried cash (amount in `Constants.lua`)
- [ ] HUD displays carried cash and secured funds (server-sent values only)
- [ ] Both tables cleared properly on `PlayerRemoving`
- [ ] Stage 0–1 still pass after Stage 2 is added

### Files likely affected later

| File | Why |
|---|---|
| `src/server/EconomyService.lua` | New file |
| `src/client/EconomyController.lua` | New file (HUD display) |
| `src/server/DamageService.lua` | Call `EconomyService:OnKill()` on kill for cash reward |
| `src/shared/Constants.lua` | Cash reward amounts |
| `docs/PROJECT_MAP.md` | New remotes (CashChanged) |

### Not in this stage

- Depositing or extracting (Stage 3)
- Spending carried cash (Stage 5)
- Death loss (Stage 4)
- Shops
- Inventory

### Studio / MCP verification required

Yes — cash values must be verified to update correctly after kills and loot pickups. HUD display must update without lag.

### Maintenance risks

- `EconomyService` will need to be called from `DamageService` (on kill). This is a new cross-service dependency. If both are ModuleScripts, the call direction must be one-way only. If there is a circular-require risk, use `MatchEvents`-style BindableEvents instead.
- Cash amounts in `Constants.lua` must be tuned in Studio. Placeholder values that feel wrong at first play will be hard to tune later if they are buried in logic rather than Constants.

---

## Stage 3 — Deposit / extraction point

**Status:** Not started.

### Goal

Add one extraction/deposit trigger in the zone. When a player reaches it, their carried cash is transferred to secured funds. This is the first moment the core loop closes: earn → extract → secure.

### Checklist

- [ ] `ExtractionService` created (`src/server/ExtractionService.lua`)
- [ ] One extraction trigger part in Workspace (e.g. `Workspace/Exits/ExitA`)
- [ ] On trigger, `EconomyService:Deposit(player)` transfers carried cash → secured funds
- [ ] Transfer is atomic (no partial credit on disconnect mid-transfer)
- [ ] Client receives confirmation and HUD updates
- [ ] Extraction is server-validated — client cannot claim extraction without touching the trigger
- [ ] Stage 0–2 still pass after Stage 3 is added

### Files likely affected later

| File | Why |
|---|---|
| `src/server/ExtractionService.lua` | New file |
| `src/server/EconomyService.lua` | New `Deposit()` method |
| `docs/PROJECT_MAP.md` | New remote if extraction triggers a client notification |
| `src/shared/Constants.lua` | Extraction trigger cooldown |

### Not in this stage

- Multiple extraction points
- Extraction camping countermeasures (note map layout instead)
- Extraction timers or countdowns
- Death loss (Stage 4)
- Zone events

### Studio / MCP verification required

Yes — extraction trigger, cash-to-secured transfer, and HUD confirmation must all be verified in live play mode with multiple players.

### Maintenance risks

- Extraction trigger uses `BasePart.Touched`. If two players touch it at the same moment, both deposits must be processed independently without race conditions.
- The atomicity requirement (no partial credit on disconnect) is difficult to guarantee without a transaction model. For the prototype, accept the risk and document it as DEBT when built.

---

## Stage 4 — Death loss

**Status:** Not started.

### Goal

On death inside the zone, the player loses their carried cash. Secured funds are never touched. This closes the risk loop — earning cash in the zone now has real consequence.

### Checklist

- [ ] On `RagdollApplied` (or kill signal), if player is in Zone: `EconomyService:LoseCarriedCash(player)` zeroes the carried cash table
- [ ] Secured funds are unchanged on death
- [ ] Client HUD reflects the loss immediately (server-sent update)
- [ ] Free respawn is available: player can re-enter with a basic free loadout
- [ ] Re-entry is fast (no waiting screen longer than a few seconds)
- [ ] Stage 0–3 still pass after Stage 4 is added

### Files likely affected later

| File | Why |
|---|---|
| `src/server/EconomyService.lua` | New `LoseCarriedCash()` method |
| `src/server/DamageService.lua` | Call EconomyService on kill |
| `src/client/UI/DeathScreen.lua` | Adapt to show cash lost and respawn option (legacy PREP cleanup path may need adjustment — see DEBT-036) |
| `src/shared/Constants.lua` | Free respawn loadout definition |

### Not in this stage

- Death drops (Stage 6) — cash simply vanishes for now
- Consumable loss
- Weapon drop on death (Stage 6)

### Studio / MCP verification required

Yes — death loss must be verified: die in zone, confirm carried cash zeroed; die at base, confirm carried cash unchanged; secured funds unchanged in both cases.

### Maintenance risks

- `DeathScreen.lua` currently uses `RoundStateChanged` (PREP phase) for cleanup. In the persistent zone there is no PREP phase — the cleanup path must be replaced or patched. This is the DEBT-036 DeathScreen incompatibility.
- Free respawn must be guaranteed at all times. If `BaseService` fails to load, players must still be able to respawn. Add a fallback.

---

## Stage 5 — Zone shop

**Status:** Not started.

### Goal

Add one in-zone shop that accepts carried cash. Players can buy starter items or basic combat supplies without leaving the zone. This creates an incentive to stay and spend rather than always extracting.

### Checklist

- [ ] `ShopService` created (`src/server/ShopService.lua`)
- [ ] One shop trigger in the zone (e.g. a part or NPC marker)
- [ ] Shop inventory defined in a data module (not hardcoded in ShopService)
- [ ] Purchases deduct carried cash on the server — client never decides the price
- [ ] Purchased items are server-granted (ammo refill, health pack, simple weapon)
- [ ] Shop UI (client) displays available items and current carried cash balance
- [ ] Server rejects purchases if player does not have enough carried cash
- [ ] Stage 0–4 still pass after Stage 5 is added

### Files likely affected later

| File | Why |
|---|---|
| `src/server/ShopService.lua` | New file |
| `src/client/ShopController.lua` | New file |
| `src/shared/ShopData.lua` | New data module: item names, prices, effects |
| `src/server/EconomyService.lua` | Deduct carried cash on purchase |
| `docs/PROJECT_MAP.md` | New remotes (ShopPurchase, ShopOpened) |

### Not in this stage

- Base armory purchases (separate system, uses secured funds)
- Weapon attachments
- Full inventory UI
- Multiple shop locations

### Studio / MCP verification required

Yes — purchase flow, cash deduction, item grant, and rejection on insufficient funds all require live play-mode testing with multiple concurrent buyers.

### Maintenance risks

- Shop data must be in `ShopData.lua`, not `ShopService.lua`. If prices are hardcoded in service logic, tuning requires reading service code.
- Two concurrent purchase requests from the same player must not double-deduct. Use a per-player purchase lock or validate balance before and after.

---

## Stage 6 — Simple death drops

**Status:** Not started.

### Goal

When a player dies in the zone with carried cash, drop a loot bag at the death location. Other players can pick it up. This makes death meaningful for nearby players and creates hot-drop scenarios.

### Checklist

- [ ] `DeathDropService` created (`src/server/DeathDropService.lua`)
- [ ] On death in zone with `carriedCash > 0`: spawn a `DropBag` part at death position
- [ ] `DropBag` stores cash value on the server (not visible in the bag's properties to the client)
- [ ] Player walking over the bag picks it up — server grants carried cash, removes bag
- [ ] Bags have a decay timer (removed after N seconds if uncollected) — `Constants.DROP_DECAY_TIME`
- [ ] Bags are cleaned up on match/session end to avoid Workspace clutter
- [ ] Stage 0–5 still pass after Stage 6 is added

### Files likely affected later

| File | Why |
|---|---|
| `src/server/DeathDropService.lua` | New file |
| `src/server/EconomyService.lua` | Called on bag pickup to grant cash |
| `src/server/DamageService.lua` | Call DeathDropService on kill |
| `src/shared/Constants.lua` | `DROP_DECAY_TIME` |
| `docs/PROJECT_MAP.md` | New remote if bag pickup triggers client notification |

### Not in this stage

- Weapon drops (requires InventoryService)
- Full loot system (LootService is separate)
- Multiple drop types

### Studio / MCP verification required

Yes — bag spawn, pickup, decay cleanup, and concurrent multi-player pickup (two players race for the same bag) must be verified.

### Maintenance risks

- `Instance.new("Part")` per drop is acceptable at prototype scale. If the zone fills with deaths, pooling becomes necessary — add `ObjectPool.lua` when a second pooled object type is needed (per CLAUDE.md pooling rule).
- Bag decay uses `task.delay()`. If the server restarts or the bag's owning script errors, the delay is lost and bags accumulate. Consider a heartbeat cleanup sweep as a fallback.

---

## Stage 7 — First zone event: Reality Collapse

**Status:** Not started.

### Goal

Add the first periodic zone event: Reality Collapse. A countdown begins; players must extract/deposit or leave the zone before it ends, or they take lethal damage. After the collapse, simple loot refreshes. This creates a natural extraction deadline without a round timer.

### Checklist

- [ ] `ZoneEventService` created (`src/server/ZoneEventService.lua`)
- [ ] Collapse countdown fires a `ZoneEventStarted` remote to all clients (registered in PROJECT_MAP.md first)
- [ ] HUD shows countdown timer
- [ ] At T=0: all players still in zone take lethal damage (server-side, via `DamageService:Apply()`)
- [ ] Simple loot objects refresh in zone after collapse
- [ ] Collapse interval is a constant in `Constants.lua` (not hardcoded in ZoneEventService)
- [ ] Event does not block extraction — players can still reach exits during the countdown
- [ ] Stage 0–6 still pass after Stage 7 is added

### Files likely affected later

| File | Why |
|---|---|
| `src/server/ZoneEventService.lua` | New file |
| `src/client/ZoneEventController.lua` | New file (countdown UI) |
| `src/server/DamageService.lua` | Used to apply collapse lethal damage |
| `src/server/LootService.lua` | Called to refresh loot after collapse |
| `src/shared/Constants.lua` | `COLLAPSE_INTERVAL`, `COLLAPSE_WARNING_TIME` |
| `docs/PROJECT_MAP.md` | New remotes (`ZoneEventStarted`, `ZoneEventEnded`) |

### Not in this stage

- Complex monster AI
- Multiple event types
- Event rewards beyond loot refresh
- Faction-specific event outcomes

### Studio / MCP verification required

Yes — countdown display, lethal damage on T=0, loot refresh, and extraction during countdown must all be tested in live play mode.

### Maintenance risks

- The collapse kills all players in zone simultaneously. If `DamageService:Apply()` is called in a loop, the kill feed may flood. Batch the kill messages or add a "zone collapse" special kill type.
- Loot refresh calls `LootService` from `ZoneEventService`. Confirm no circular-require risk before implementing.

---

## Stage 8 — Simple monsters

**Status:** Not started.

### Goal

Add basic monster spawns in the zone. Monsters are dumb, slow, and easy to kill individually — they exist to create ambient pressure and provide an additional cash/loot source. No pathfinding AI beyond basic follow-and-attack.

### Checklist

- [ ] `MonsterService` created (`src/server/MonsterService.lua`)
- [ ] Monster spawns defined in `Workspace/MonsterSpawns` (already exists)
- [ ] Monsters have a simple attack: walk toward nearest player and deal contact damage via `DamageService:Apply()`
- [ ] Monsters have health; players can kill them
- [ ] Killing a monster grants a small amount of carried cash (server-side)
- [ ] Monster count is capped by a constant (`Constants.MAX_MONSTERS`)
- [ ] Monsters are cleaned up when the zone is empty
- [ ] Stage 0–7 still pass after Stage 8 is added

### Files likely affected later

| File | Why |
|---|---|
| `src/server/MonsterService.lua` | New file |
| `src/shared/MonsterData.lua` | New file: monster stats (health, speed, damage, cash drop) |
| `src/server/DamageService.lua` | Used to apply monster attack damage |
| `src/server/EconomyService.lua` | Called on monster kill for cash reward |
| `src/shared/Constants.lua` | `MAX_MONSTERS`, monster spawn interval |

### Not in this stage

- Complex pathfinding
- Monster types beyond one base variant
- Monster loot drops beyond flat cash
- `HordeService` escalation

### Studio / MCP verification required

Yes — monster spawn, basic follow/attack, player kill reward, and cap enforcement must be verified in live play mode.

### Maintenance risks

- Monster AI running on `RunService.Heartbeat` per monster is expensive. Cap monster count strictly and profile frame time before increasing.
- If monsters call `DamageService:Apply(nil, victim, amount)` (no attacker), the kill feed attacker name will be empty string. Define a convention for environment/monster kills before building the kill feed display.

---

## Stage 9 — Base progression

**Status:** Not started.

### Goal

Add the first base upgrades. Players spend secured funds at the base to improve their position. Start small — only three upgrade types. Avoid complex unlock trees or grindy costs at this stage.

### Checklist

- [ ] `BaseService` extended or `ProgressionService` created to track upgrade state
- [ ] Three initial upgrades: Armory (unlock better guns), Storage (increase carry weight/stash slots), Medical Station (cheaper health packs in zone)
- [ ] Upgrade state is server-owned and persists across sessions (or at minimum across the current server lifetime)
- [ ] Upgrade costs are in `Constants.lua` or a data module — never hardcoded in service logic
- [ ] Client displays current upgrade levels and costs
- [ ] Purchases deduct secured funds on the server — client never decides prices
- [ ] Stage 0–8 still pass after Stage 9 is added

### Files likely affected later

| File | Why |
|---|---|
| `src/server/BaseService.lua` | New or extended file |
| `src/server/ProgressionService.lua` | New file if separate from BaseService |
| `src/shared/UpgradeData.lua` | New file: upgrade names, costs, effects |
| `src/server/EconomyService.lua` | Deduct secured funds on upgrade purchase |
| `docs/PROJECT_MAP.md` | New remotes (UpgradePurchased, BaseStateChanged) |

### Not in this stage

- Full tech tree or unlock chains
- Faction-specific upgrades
- Persistent cross-session saving (datastores — deferred until StashService)
- Crafting

### Studio / MCP verification required

Yes — purchase deduction, upgrade state persistence (within session), and UI display must be tested with multiple players at the same base.

### Maintenance risks

- Upgrade state will eventually need DataStore persistence. Building without it now creates a hard migration later. Document the absence as a debt entry when Stage 9 is built.
- "Better guns from Armory upgrade" implies the base armory stock is dynamic. Design the armory data module to support this from the start (an array of items, some locked behind upgrade level) rather than retrofitting later.

---

## Stage 10 — Polish systems

**Status:** Not started. Only begin after Stage 0–9 are stable and fun in Studio.

### Goal

Layer polish on top of a working game loop. Do not start any polish item until the core loop (zone → loot/fight → extract → deposit → upgrade → zone) is verified and enjoyable.

### Checklist

- [ ] Recoil and spread added to GunService/GunController
- [ ] ADS (aim-down-sights) viewmodel state
- [ ] Camera bob and sway during movement
- [ ] Slide and vault movement additions
- [ ] Sound polish: footstep variation, ambient zone sounds, event sounds
- [ ] UI redesign: cash wallet, zone map, base dashboard
- [ ] More weapons added to WeaponData and base armory
- [ ] More zone event types (not just Reality Collapse)
- [ ] More monster variants

### Files likely affected later

| File | Why |
|---|---|
| `src/server/GunService.server.lua` | Recoil/spread values |
| `src/client/GunController.lua` | ADS input, spread feel |
| `src/client/ViewModelController.lua` | ADS animation state |
| `src/client/MovementController.lua` | Slide/vault/camera bob |
| `src/client/SoundController.lua` | Footstep variation, ambient |
| `src/shared/WeaponData.lua` | New weapons |
| `src/shared/Constants.lua` | New recoil/spread/ADS constants |

### Not in this stage

Nothing is blocked here — but each item should still be a separate task and verified in Studio individually.

### Studio / MCP verification required

Yes — every polish item must be verified in live play mode. Recoil/spread in particular changes weapon feel and must not break existing GunService shot validation.

### Maintenance risks

- Adding recoil client-side (visual) is safe; adding server-side spread (random miss chance) changes hit rates and balance. Decide the design intent before building.
- Slide and vault require character controller changes that may conflict with the existing `CharacterAutoLoads` / TeamService setup (DEBT-019/DEBT-036). Resolve the legacy character spawn path before adding movement complexity.

---

## Stage reference summary

| Stage | Name | Key new system | Gate condition |
|---|---|---|---|
| 0 | FPS foundation | — (existing) | All checklist items pass in Studio |
| 1 | Zone/base state | `ZoneService` | Stage 0 verified |
| 2 | Economy foundation | `EconomyService` | Stage 1 verified |
| 3 | Deposit / extraction | `ExtractionService` | Stage 2 verified |
| 4 | Death loss | — (EconomyService extension) | Stage 3 verified |
| 5 | Zone shop | `ShopService` | Stage 4 verified |
| 6 | Death drops | `DeathDropService` | Stage 5 verified |
| 7 | Reality Collapse event | `ZoneEventService` | Stage 6 verified |
| 8 | Simple monsters | `MonsterService` | Stage 7 verified |
| 9 | Base progression | `BaseService` / `ProgressionService` | Stage 8 verified |
| 10 | Polish | (many) | Stages 0–9 verified and fun |

---

*Last updated: 2026-05-15. Update this file when a stage is verified or its scope changes.*
