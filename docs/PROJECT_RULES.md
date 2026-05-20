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

## Studio / MCP verification (added 2026-05-19)

**When Roblox Studio MCP is accessible, always use it. Do not skip MCP verification just because static checks (`selene`, `rojo build`, formatting) pass.** Static checks catch structural errors; they do not verify runtime behavior, animation playback, input handling, physics, remote timing, UI layout, or server–client data flow.

### What requires MCP/Studio verification before committing

Any change touching the systems below must be verified in Roblox Studio through the MCP tool before the commit is made — when MCP is accessible.

| Category | Examples |
|---|---|
| Server services (`src/server/`) | MatchService, GunService, DamageService, EconomyService, ZoneService, TeamService, and any future service |
| Client controllers (`src/client/`) | MovementController, GunController, ViewModelController, SoundController, and all UI controllers |
| Shared modules (`src/shared/`) | Constants, WeaponData, WeaponFeel, Types, Logger — any change that affects runtime reads |
| Remotes | Any new or modified RemoteEvent / RemoteFunction |
| Rojo config (`default.project.json`) | Property overrides that affect StarterPlayer, character spawning, or rig type |
| Player spawning / character lifecycle | CharacterAdded, CharacterAutoLoads, spawn part selection, health initialization |
| Camera / mouse behavior | CameraType, UserInputService.MouseBehavior, FieldOfView, MouseBehavior.LockCenter |
| Viewmodel / weapon attachments | PivotTo, barrel tip, eject port, ADS offsets |
| Movement input | Key bindings (LeftShift, LeftAlt, C, any new key), WalkSpeed, sprint/crouch/slide logic |
| Combat | Damage, hit validation, ammo, reload, rate limiting |
| UI | HUD, MatchUI, DeathScreen, KillFeedUI, CrosshairUI, ObjectiveUI — any controller that creates ScreenGui |
| Economy / inventory / zone systems | Carried cash, secured funds, zone entry/exit, shop, extraction, death drop (when built) |
| Character rig | R6/R15 target, StarterPlayer.CharacterRigType, Motor6D iteration |
| Animation | Animation IDs, AnimationTrack loading/playback, AdjustSpeed, Animator |

### Verification workflow (MCP accessible)

1. Edit the code.
2. Run `rojo serve default.project.json` to sync changes into Studio.
3. Use MCP to launch or connect to a live Studio session.
4. Play in Studio. Check Output (no unexpected errors or warns). Observe the specific behavior the task specifies.
5. Confirm observed behavior matches the task spec.
6. Then commit and push.

### When MCP is unavailable

- Clearly state "MCP unavailable — Studio verification was not performed" in the task response.
- Restrict scope to documentation, configuration, and static-validation tasks unless the user explicitly accepts unverified changes.
- For any gameplay-affecting change made without MCP: add a "needs Studio verification" note to `docs/TECHNICAL_DEBT.md` and the task response.
- Do not mark runtime debt entries resolved without Studio confirmation.
- **Never claim a behavior was tested in Studio unless it was actually verified through MCP or a confirmed manual Studio test.** Stating "this should work" or "static checks pass" is not Studio verification for runtime systems.

### Systems that especially must not skip MCP

Even for "small" or "low-risk" changes, MCP verification is required before committing when MCP is accessible for:
- Movement input and MouseBehavior (LeftAlt, LeftShift, mouse lock — timing and CoreScript interaction are only visible at runtime)
- Camera (any CameraType change breaks input silently unless tested in play mode)
- Animation playback (LoadAnimation failures, Animator missing, Animate override conflicts are runtime-only)
- Remote data flow (payload format mismatches, missing listener connections, timing between fire and receipt)
- Character spawn lifecycle (CharacterAdded timing, WalkSpeed init, health reset on respawn)
- Economy correctness (carried cash / secured funds must be server-authoritative; client-side reads are presentation-only)

---

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

---

---

## Refined persistent-zone design rules (added 2026-05-20)

These rules define what gets built and in what order for the metro-base persistent-zone direction. They complement the existing persistent zone design rules above.

### First playable version discipline

- The first playable version must prove the **zone money/extraction loop** before adding large secondary systems. The loop is: enter zone → earn carried cash → extract → deposit → return. Nothing else is required to validate this.
- Do not build a **player-to-player marketplace or flea market** until the economy, stash, item ownership, and anti-duplication systems are stable and the moderation/abuse risks have been intentionally addressed.
- Do not build **advanced AI death squads** before simple monsters and basic event pressure are proven in Studio.
- Do not build **full gun attachments** before the basic weapon/shop/economy loop works.
- Do not build **free drawing or custom signage** until content moderation and abuse risks are intentionally addressed with a plan.
- Do not build **complex melee**, **complex faction warfare**, or **full base decoration** during the FPS foundation phase.

### Physical extraction/deposit rule

- Physical extraction and deposit must **matter**. Do not allow instant banking from anywhere in the zone. Value is only secured by physically reaching a deposit terminal (in the metro base) or an extraction exit (a physical point in the zone). There is no "deposit remotely" path.
- Zone entrance and exit must be **physical transitions** — gate, train route, sewer, tunnel, or checkpoint. Not a menu or teleport button.
- Multiple extraction exits should exist eventually to reduce camping. Until then, the single exit must be well-placed.

### Zone shop and pricing rule

- Zone shops **may** sell emergency guns, ammo, and consumables to players who have lost their gear in the zone, at prices **higher than the base armory**. This is the trade-off: convenience in-zone costs more.
- Zone shops must not replace base armory progression. A player should still want to extract, deposit, and buy from the base armory for better gear. In-zone shops are a fallback, not the primary gear source.
- Zone shop prices are server-validated. The client requests a purchase; the server checks price, deducts carried cash, and fulfills the item. The client never decides the price.

### Base progression rule

- Base progression (armory tiers, storage upgrades, medical supplies) should be **visible and rewarding** but not grindy. A new player should reach first-tier upgrades within a few successful extractions.
- Base upgrades are server-owned. The client displays upgrade state and requests purchases. The server validates secured funds, deducts, and applies the upgrade.

### Server authority — refined zone systems

In addition to the existing server authority rules above, the following rules apply to all new persistent-zone systems:

**Server owns:**
- Carried cash balance per player
- Secured funds balance per player
- Loot object spawn positions and remaining contents
- Shop purchase validation and item fulfillment (both zone shops and base armory)
- Death drop bag creation, position, and contents
- Extraction trigger validation (a player cannot declare their own extraction valid)
- Base upgrade state and purchase validation
- Mission progress and completion validation
- Zone event state (timers, loot surge triggers, monster escalation)

**Client may:**
- Display carried cash, secured funds, and stash state as sent by the server
- Fire RemoteEvents to request zone entry, extraction, shop purchase, loot pickup, mission accept, respawn, or deposit
- Show local-only visual prediction (e.g. wallet counter ticking up), but always treat the server's next broadcast as authoritative

**Never trust the client with:**
- Cash amounts (carried or secured)
- Inventory state or stash contents
- Extraction success
- Death drop spawning or contents
- Shop prices or purchase results
- Mission state

---

## Character rig target

**All new code targets R6.**

The project's character rig is R6. Every new system — animations, hitbox lookups, ragdoll filters, weapon attachments — must reference R6 body-part names only.

**R6 canonical part names:**

| Name | Role |
|---|---|
| `HumanoidRootPart` | Physics root |
| `Torso` | Central torso |
| `Head` | Head |
| `Left Arm` | Left arm |
| `Right Arm` | Right arm |
| `Left Leg` | Left leg |
| `Right Leg` | Right leg |

**Rules:**

1. Never write code that strings-matches or iterates by R15 part names (`UpperTorso`, `LowerTorso`, `LeftUpperArm`, `RightUpperArm`, `LeftLowerArm`, `RightLowerArm`, etc.) in any new service or controller.
2. Animation asset IDs must be recorded against an R6 rig. R15 animation IDs will play incorrectly on an R6 character.
3. Hitbox or region checks that name specific body parts must use R6 names.
4. Weapon viewmodel attachment points (barrel tip, eject port) must be aligned to R6 arm geometry.
5. The `StarterPlayer.CharacterRigType` is set to `Enum.HumanoidRigType.R6` (value 0) in `default.project.json`. Do not change this without a dedicated rig-migration task.
6. Before adding any third-party rig or animation pack, confirm the asset targets R6. If it targets R15, do not import it without a dedicated rig-migration task and explicit approval.

**Existing legacy code** (e.g. `RagdollService` iterating all `Motor6D` joints by type rather than by name) is acceptable because rig-agnostic iteration works for both R6 and R15. The rule above applies to all new code going forward.
