# PERSISTENT_ZONE_ROADMAP.md

Staged build order for the persistent-zone metro shooter (Milestone 1).
This is a planning document. It does not resolve any runtime debt entries.
Runtime behavior is only verified in Roblox Studio via MCP.

**Read this before starting any Milestone 1 system.**
See also: `CLAUDE.md` (product direction), `docs/PROJECT_RULES.md` (design rules), `docs/PROJECT_MAP.md` (system architecture).

---

## Principles

- Build one stage at a time. Server before client. Do not start the next stage until the current is verified in Studio.
- Each stage produces a playable, testable result — not just scaffolding.
- No stage should add multiple large systems simultaneously unless they are trivially coupled.
- If a stage is blocked waiting for a dependency, document it here and work on something else rather than combining stages.
- Deferred systems (flea market, advanced AI, attachments, base decoration) must not be started until their prerequisites are explicitly met. See Stage 10.

---

## Stage 0 — Reusable FPS Foundation

**Status:** Largely complete via Milestone 0 legacy systems.

**Goal:** Confirm that the FPS basics work before building the persistent zone on top.

**What is included:**
- AR15 weapon with GunService/GunController, shot validation, ammo system
- Basic damage/death/ragdoll flow (DamageService, RagdollService)
- R6 movement foundation (MovementController Stages 1 + 2A–2E)
- HUD (health, ammo, kill feed)
- First-person viewmodel (ViewModelController, FORCE_FIRST_PERSON = true before shipping)

**What is NOT needed at this stage:**
- Round-based MatchService/TeamService/ObjectiveService expansion
- Train cinematics
- Zone events
- Monster AI

**Stage complete when:** A player can spawn, move, shoot another player, die, and respawn cleanly in Studio with no unexpected errors in Output.

---

## Stage 1 — Metro Base + Zone Transition Foundation

**Status:** Not started.

**Goal:** Establish the physical metro base hub and one working zone entrance/exit so the spatial layout of the loop exists before economy systems are added.

**What is included:**
- Safe metro base area in Workspace (a physical space — not a menu)
  - No PvP, no monsters inside the metro base boundary
  - Deposit terminal placeholder (non-functional until Stage 3)
  - Base armory placeholder (non-functional until Stage 9)
- One physical zone entrance (gate, train stop, or sewer entry)
  - Collider trigger that updates the player's zone-state (in-zone vs. in-base)
  - ZoneService owns zone-state tracking per player
- One physical extraction/deposit exit (a different point from the entrance if possible)
  - Non-functional for economy until Stage 3 (ExtractionService); for now just a physical marker
- ZoneStateChanged RemoteEvent fired to client on entry/exit (client displays "IN ZONE" / "IN BASE" status only)

**What is NOT needed at this stage:**
- Train cinematics or animated transitions (a simple collider trigger is sufficient)
- Multiple entrances or exits
- Economy logic (no cash yet)
- Shops, missions, events

**Stage complete when:** A player can walk from the metro base into the zone through the entrance collider. ZoneService correctly tracks them as in-zone. Walking back through the exit collider correctly marks them as in-base. No errors in Output.

---

## Stage 2 — Economy Foundation

**Status:** Not started.

**Goal:** Establish server-authoritative carried cash and secured funds balances. No spending or loss yet — just earning and display.

**What is included:**
- EconomyService (server) owns:
  - `carriedCash[player]` — starts at 0; never trusted from client
  - `securedFunds[player]` — starts at 0
  - `addCarriedCash(player, amount)` — called by kill credit, loot pickup
  - `getCarriedCash(player)` / `getSecuredFunds(player)` — read by other services
- EconomyChanged RemoteEvent fires to the affected client with `{ carriedCash, securedFunds }`
- HUD updated to display carried cash (wallet counter) and secured funds
- Basic kill credit: killing a player in the zone adds a small amount of carried cash (tunable constant)

**What is NOT needed at this stage:**
- Deposit logic (Stage 3)
- Death loss (Stage 4)
- Shop purchases (Stage 5)
- Player-to-player transfers (deferred indefinitely — see Stage 10)

**Stage complete when:** Killing a player in the zone increases the killer's carried cash display in the HUD. EconomyService logs the change to Output. No client-side cash manipulation is possible.

---

## Stage 3 — Deposit / Extraction

**Status:** Not started.

**Goal:** Prove the core risk loop. A player can physically extract from the zone and convert carried cash to secured funds.

**What is included:**
- ExtractionService (server) owns:
  - Extraction trigger validation: player must physically reach the exit collider in Workspace
  - On successful extraction: calls `EconomyService:depositCarriedCash(player)`
  - ExtractionSuccess RemoteEvent fires to the client with final balances
- `depositCarriedCash(player)` in EconomyService: moves carriedCash → securedFunds, fires EconomyChanged
- Deposit terminal (in metro base) as an alternative deposit path:
  - Player walks up to the terminal in the metro base (not the zone)
  - Server validates player is in metro base (ZoneService: not in-zone)
  - Moves carriedCash → securedFunds; fires EconomyChanged

**What is NOT needed at this stage:**
- Instant banking from inside the zone (explicitly forbidden — see PROJECT_RULES.md)
- Multiple extraction exits (one is sufficient to prove the loop)

**Stage complete when:** A player enters the zone, earns carried cash from a kill, extracts through the physical exit, and sees their secured funds increase in the HUD. A player can also walk to the metro base deposit terminal and manually deposit. Both paths transfer correctly. Firing the extraction remote from inside the zone without reaching the exit is rejected.

---

## Stage 4 — Death Loss

**Status:** Not started.

**Goal:** Make the risk real. Death in the zone costs the player their carried cash.

**What is included:**
- On player death inside the zone (confirmed by DamageService / RagdollService + ZoneService zone-check):
  - EconomyService zeros `carriedCash[player]`
  - DeathDropService spawns a pickup bag (Part/Model) at the death location containing the lost cash amount
  - EconomyChanged fires to the dead player showing 0 carried cash
- DeathDropService (server) owns:
  - Bag creation at death position
  - Bag contents (cash amount — weapon drop is future scope; cash drop is Stage 4)
  - Bag pickup validation (another player touches bag; server validates proximity and awards carried cash)
  - Bags persist until picked up or until session end
- Death screen updated to show "Carried cash lost: X"

**What is NOT needed at this stage:**
- Weapon drops (complex to drop and recover — defer)
- Multiple bag types or bag timers

**Stage complete when:** Dying in the zone zeros the player's carried cash display and spawns a bag at the death location. Another player can pick up the bag and receive the cash. Dying in the metro base does NOT lose carried cash (zone-check in DeathDropService).

---

## Stage 5 — Risky Zone Shop + Loot Objects

**Status:** Not started.

**Goal:** Give players something to spend carried cash on inside the zone, and something to pick up from the environment.

**What is included:**
- ShopService (server):
  - One in-zone trader/cache (a Part or NPC marker in Workspace)
  - Sells 1–3 items: emergency basic pistol, ammo pack, heal item
  - Prices are higher than base armory equivalents (tunable constants)
  - Accepts carried cash only (no secured funds in zone)
  - Server validates: player is in zone, sufficient carriedCash, item is in stock
  - On success: deducts carriedCash, gives item, fires PurchaseResult to client
- LootService (server):
  - Loot objects (cash bags, ammo drops) at fixed spawn positions in the zone
  - Server owns spawn state and remaining contents
  - On pickup: server validates proximity, awards carried cash, fires LootPickedUp
- Client proximity prompts and purchase/pickup requests (ShopController / LootController)

**What is NOT needed at this stage:**
- Multiple shop locations
- Dynamic pricing or rotating stock
- Full inventory UI
- Player-to-player item transfer (deferred — see Stage 10)

**Stage complete when:** A player can pick up a loot bag in the zone (earning carried cash). A player can approach the zone shop and buy an emergency pistol for carried cash. ShopService rejects purchases with insufficient cash. All transactions visible in Output logs.

---

## Stage 6 — Simple Missions / Faction Traders

**Status:** Not started.

**Goal:** Give players short optional objectives that add direction to a run without mandatory participation.

**What is included:**
- MissionService (server):
  - One faction trader in the metro base (NPC marker or Part)
  - 1–3 mission types: kill N monsters, extract with at least X carried cash, visit a zone location
  - Player accepts a mission (one active at a time)
  - Server tracks progress and validates completion
  - On completion: awards carried cash bonus
  - MissionUpdated / MissionComplete RemoteEvents fire to the client
- MissionUI: active mission + progress display in HUD

**What is NOT needed at this stage:**
- Complex multi-step missions
- Faction reputation / standing system
- Multiple traders
- Player-to-player mission sharing

**Stage complete when:** A player accepts a mission from the trader, completes it in the zone, and receives the cash reward. Mission progress is visible in the HUD.

---

## Stage 7 — First Zone Event (Reality Breakdown)

**Status:** Not started.

**Goal:** Add periodic pressure that creates urgency without locking players into mandatory participation.

**What is included:**
- ZoneEventService (server):
  - Reality Breakdown countdown: recurring timer (e.g. every 10–15 minutes, tunable constant)
  - On event start: fires ZoneEventStarted → all clients (client shows warning countdown)
  - During event: one of — lethal zone spread, monster escalation, or loot surge (choose one)
  - Safe extraction must remain possible during the event
  - On event end: zone resets; fires ZoneEventEnded → all clients
- ZoneEventUI (client): countdown timer, event name, extract prompt

**What is NOT needed at this stage:**
- Multiple event types
- Event-locked zones (a player who ignores the event must still be able to extract)

**Stage complete when:** Breakdown countdown fires on schedule, client shows the warning timer, the event effect is visible, and the event ends cleanly. A player who reaches the extraction exit during the event is successfully extracted.

---

## Stage 8 — Simple Monsters

**Status:** Not started.

**Goal:** Add ambient monster AI to the zone to create PvE pressure alongside PvP.

**What is included:**
- MonsterService (server):
  - Basic monster agents at fixed spawn nodes in the zone
  - Simple pathfinding and attack logic (approach + melee or ranged)
  - Targets all players equally (no team distinction)
  - Drops small carried cash bonus on kill (via EconomyService:addCarriedCash)
  - Respawns on a timer

**What is NOT needed at this stage:**
- Advanced AI death squads (deferred — see Stage 10)
- Monster faction allegiance, aggro radius tuning, or special abilities
- Monster loot drops beyond basic cash

**Stage complete when:** Monsters spawn in the zone, pathfind toward players, deal damage, and die when shot. Killing a monster awards carried cash. No pathfinding errors in Output.

---

## Stage 9 — Base Storage and Upgrades

**Status:** Not started.

**Goal:** Give players something to work toward with secured funds. Make the metro base feel like it grows.

**What is included:**
- StashService (server):
  - Per-player locker/crate storage (in-memory for prototype; persistent across sessions later)
  - Deposit/withdraw validation (server owns contents)
  - StashChanged RemoteEvent
- BaseService (server):
  - Base upgrade tiers: armory tier, storage tier, medical tier
  - Upgrade purchase validated by server (secured funds only)
  - BaseStateChanged RemoteEvent
- Upgrade UI: interact with upgrade station in metro base

**What is NOT needed at this stage:**
- Full base decoration (deferred — see Stage 10)
- Train cinematic polish (deferred — see Stage 10)
- Faction reputation or unlock trees

**Stage complete when:** A player spends secured funds to upgrade the base armory, sees the upgrade reflected in available weapons, and can store items in a locker.

---

## Stage 10 — Deferred Polish and Expansion

These features are **explicitly deferred** and must not be started until:
1. The core loop (Stages 1–9) is proven in Studio.
2. The listed prerequisite systems are stable.
3. For the flea market specifically: economy, stash, item ownership, anti-duplication, and moderation/abuse risks have been **intentionally designed and addressed** — not just considered.

| Feature | Prerequisite before starting |
|---|---|
| **Player flea market / global marketplace** | Stable economy + stash + item ownership + anti-duplication system + moderation/abuse plan. **Long-term only. Do not include in any first playable version.** |
| **Advanced AI death squads** | MonsterService (Stage 8) + zone events (Stage 7) proven |
| **Full gun attachment system** | Weapon inventory + shop + stash loop stable |
| **Complex melee system** | Core FPS loop + movement proven |
| **Complex faction warfare** | MissionService (Stage 6) proven |
| **Complex visor / enemy detection** | Basic AI (Stage 8) + combat loop proven |
| **Full base decoration system** | Core loop + stash (Stage 9) proven |
| **Train arrival/departure cinematics** | Core loop proven; train transition functional; skip mechanism designed |
| **Free drawing on signs / custom paintings** | Dedicated content moderation + abuse risk review complete |

> **Flea market / player marketplace:** Deferred until after stable economy, stash, item ownership, anti-duplication, and moderation/abuse controls exist. Do not prototype, scaffold, or begin design work on the marketplace until all prerequisites are confirmed stable in Studio and a moderation plan is in place.
