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

### Match lifecycle (legacy/transitional)

> These services implement the original five-round attackers-vs-defenders loop. They are now **legacy/transitional**. Do not add new round-specific features to them. They will be replaced or retired when the persistent zone systems are built.

```
MatchService    [LEGACY] round number, match phase (Lobby / Active / Results), timers
  │  fires: RoundStateChanged → all clients
  │
  ├─ TeamService    [LEGACY] team assignments (Attackers/Defenders), spawn selection
  │    fires: TeamAssigned → individual client
  │
  └─ ObjectiveService    [LEGACY] anchor plant state, capture progress
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
       validates: payload types, direction magnitude (< SHOT_DIRECTION_MIN_MAGNITUDE rejected),
         origin proximity to shooter HumanoidRootPart (> SHOT_ORIGIN_MAX_DISTANCE rejected),
         rate limit, ammo state; direction is normalized before raycasting
       clientTick validation deferred — see DEBT-014
       calls: DamageService:Apply()
       fires: HitConfirmed → firing client (hitmarker)

GunService (server)
  │  owns: weapon identity for this stage — Constants.DEFAULT_WEAPON (src/shared/Constants.lua)
  │    is the single source of truth for both server and client; the client never decides
  │    which weapon is equipped
  │  GunService reads Constants.DEFAULT_WEAPON authoritatively for WeaponData lookup,
  │    ammo setup, rate-limit validation, and all AmmoChanged broadcasts
  │  GunController reads Constants.DEFAULT_WEAPON only for client-side prediction:
  │    dry-fire checks, WeaponData range for the cosmetic raycast, local rate limiting
  │  Renaming the default weapon requires changing Constants.DEFAULT_WEAPON only
  │  AmmoChanged payload: weaponName (Constants.DEFAULT_WEAPON), mag, reserve
  │    GunController receives weaponName but ignores it (uses Constants.DEFAULT_WEAPON directly);
  │    HUD displays it
  │  WeaponFired and ReloadRequest carry no weapon name by design — intentionally
  │    omitted until a full server-owned loadout/equipment system exists (see DEBT-013)
  │
DamageService (server)
  │  owns: all health mutation
  │  blocks same-team damage when Constants.FRIENDLY_FIRE_ENABLED == false (server-side only;
  │    the client never decides whether a shot is friendly fire)
  │  team lookup order: TeamAssigned cache (playerTeam[]) first → Player.Team.Name fallback;
  │    if both return nil the shot is allowed through (unknown team membership is not blocked)
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

### AI (planned — not yet built)

```
MonsterService (server)
  │  owns: individual monster agents, pathfinding, attack logic
  │  targets: all players (no team distinction in persistent zone mode)
  │
HordeService (server)   [LEGACY PLAN — replaces with zone ambient spawn budget]
  │  owns: wave timing, spawn budget, escalation across rounds
  └─ calls: MonsterService:SpawnMonster()
```

### Presentation (client only, no server impact)

```
MovementController      -- Stage 1 + 2A (Animate-disable bug fix + R6 detection): owns local movement
                        --   input (LeftShift=sprint, C=crouch toggle), movementState table,
                        --   Humanoid.WalkSpeed, R6 walk/run animation playback, and character.Animate
                        --   suppression (R6 characters only).
                        --   Reads workspace.CurrentCamera.CFrame for 8-directional camera-relative
                        --   direction detection; does NOT write camera.CFrame, CameraOffset, or FOV.
                        --   No new remotes. No slide, vault, or camera effects.
                        --
                        --   R6 rig detection (added 2026-05-18):
                        --     isR6Character(character, hum) — primary check: Humanoid.RigType == R6.
                        --       Structural fallback: hasR6BodyParts() checks all seven canonical R6
                        --       part names under character. If fallback fires, a one-time Logger.warn
                        --       is emitted (see DEBT-049 — verify CharacterRigType after rojo serve).
                        --     hasR6BodyParts(character) — returns true when all seven R6 parts are
                        --       direct children: HumanoidRootPart, Torso, Head, Left Arm, Right Arm,
                        --       Left Leg, Right Leg.
                        --     getRigDebugSummary(character, hum) — returns a formatted string with
                        --       RigType.Name, Torso/UpperTorso/LowerTorso/Left Arm/LeftUpperArm
                        --       presence, and character.Name. Logged when animations are skipped.
                        --
                        --   Animate script suppression (bug fix — 2026-05-18):
                        --     disableDefaultAnimate() is called inside loadMovementAnimations() AFTER
                        --     isR6Character() passes — NOT from setupCharacter() directly.
                        --     This ensures Animate is only disabled for confirmed R6 characters.
                        --     Sets character.Animate.Disabled = true; does NOT destroy Animate.
                        --     Side effect: idle, jump, fall, and climb animations are also suppressed
                        --     until custom replacements are added in a future stage.
                        --     Gated by two constants (both default true):
                        --       Constants.CUSTOM_MOVEMENT_ANIMATIONS_ENABLED — master switch
                        --       Constants.DISABLE_DEFAULT_ANIMATE_FOR_CUSTOM_MOVEMENT — animate gate
                        --     If DISABLE_DEFAULT_ANIMATE_FOR_CUSTOM_MOVEMENT = false, Animate is left
                        --     running and custom tracks may conflict with avatar pack locomotion.
                        --
                        --   Stage 2A animation support (R6 only, forward walk/run only):
                        --     Loads AnimationTrack objects per character via Humanoid.Animator.
                        --     Plays during ACTIVE phase only; stops on phase exit and when not moving.
                        --     Defaults to AR15 animation set (true armed/unarmed state deferred — DEBT-050).
                        --     WalkLeft/WalkRight played if tracks are present; falls back to WalkForward.
                        --     Animation diagnostics logged when Constants.MOVEMENT_ANIMATION_DEBUG = true.
                        --     Animation IDs (Constants.MOVEMENT_ANIMATION_IDS.R6):
                        --       Unarmed.WalkForward = rbxassetid://83927286289016
                        --       Unarmed.RunForward  = rbxassetid://98612697944606
                        --       AR15.WalkForward    = rbxassetid://110651810525086
                        --       AR15.RunForward     = rbxassetid://124640088553427
                        --     Not in Stage 2A: crouch anim, backward, diagonal, lower/upper-body
                        --       split, reload/fire/ADS weapon animations.
                        --     If character fails R6 detection, getRigDebugSummary is logged and
                        --       animation loading is skipped; Stage 1 speed logic remains active.
                        --     If animation IDs are private/not owned by the game, Roblox may refuse to
                        --     load them — check Output for permission errors.
                        --
                        --   Exposes: GetMovementState() → table; GetMoveState() → string (GunController
                        --   compat); IsADSBlocked() → bool; GetViewmodelAddCFrame() → identity (Stage 1/2A);
                        --   Start(); destroy()
CutsceneController      -- intro/outro sequences, triggered by RoundStateChanged
HUD                     -- driven by HealthChanged, TeamStatusUpdate, AmmoChanged, RoundStateChanged
ObjectiveUI             -- driven by ObjectiveUpdated, ObjectiveComplete
MatchUI                 -- driven by RoundStateChanged
CrosshairUI             -- driven by RoundStateChanged; exposes ShowHitmarker()
ViewModelController     -- driven by RoundStateChanged; exposes PlayFireAnimation(),
                        --   GetBarrelTipCFrame(), SetRecoilOffset(); reads MovementController.
                        --   Camera mode and viewmodel visibility are controlled by
                        --   Constants.FORCE_FIRST_PERSON (src/shared/Constants.lua):
                        --     true  = LockFirstPerson camera, AR15 viewmodel shown during ACTIVE.
                        --     false = Classic camera for testing, viewmodel permanently hidden.
                        --   Reads workspace.CurrentCamera.CFrame for PivotTo each RenderStepped.
                        --   Does NOT write camera.CFrame, CameraOffset, or FieldOfView.
DeathScreen             -- driven by RagdollApplied (death trigger), RoundStateChanged (PREP cleanup)
KillFeedUI              -- driven by KillFeed; top-right scrolling kill entries, max 5, fade after display time
```

### Shared modules (ReplicatedStorage/Modules)

```
Constants    -- single source of truth for all tunable numbers and phase enums.
             --   Constants.DEFAULT_WEAPON is the single weapon identity source for
             --   the one-weapon prototype. GunService reads it authoritatively
             --   (stat lookups, ammo init, rate-limit). GunController reads it for
             --   client-side prediction and cosmetics only (rate-limit mirror,
             --   WeaponFeel lookup, muzzle flash duration). When multiple weapons
             --   exist, replace with server-owned loadout state — see DEBT-013.
             --   Constants.FORCE_FIRST_PERSON (bool, default false) — controls
             --   ViewModelController's camera mode and viewmodel visibility.
             --     false = Classic camera + viewmodel hidden (development/testing).
             --     true  = LockFirstPerson + viewmodel shown during ACTIVE only.
             --   Set true before shipping the FPS experience. See DEBT-048.
             --   Movement animation control constants (all default true):
             --     CUSTOM_MOVEMENT_ANIMATIONS_ENABLED — master switch; false disables all
             --       custom movement track loading and playback; Animate runs as normal.
             --     DISABLE_DEFAULT_ANIMATE_FOR_CUSTOM_MOVEMENT — when true, MovementController
             --       sets character.Animate.Disabled = true before loading custom tracks;
             --       false leaves Animate running (may cause override/blend conflicts).
             --     MOVEMENT_ANIMATION_DEBUG — when true, logs animation load and switch
             --       events to Output for diagnostics; set false to silence in production.
WeaponData   -- per-weapon stat table (damage, range, fireRate, magazineSize, reserveAmmo)
WeaponFeel   -- per-weapon gunplay feel (recoil, spread, ADS time, muzzle flash duration)
Logger       -- debug/warn wrapper; suppressed in release via DEBUG_MODE flag
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
  1.  MatchController:Start()         -- must be first; owns GetPhase() which GunController reads
  2.  MatchUI:init()+Start()          -- no controller deps; connects RoundStateChanged; needs PlayerGui
  3.  HUD:init()+Start()              -- no controller deps; connects HealthChanged, TeamStatusUpdate, RoundStateChanged; needs PlayerGui
  4.  DeathScreen:init()+Start()      -- no controller deps; connects RagdollApplied, RoundStateChanged; needs PlayerGui
  5.  KillFeedUI:init()+Start()       -- no controller deps; connects KillFeed; needs PlayerGui
  6.  CrosshairUI:init()+Start()      -- no controller deps; exposes ShowHitmarker(); needs PlayerGui
  7.  ViewModelController:Start()     -- requires MovementController (no circular); exposes PlayFireAnimation(),
                                      --   GetBarrelTipCFrame(), SetRecoilOffset()
  8.  SoundController:init()+Start()  -- no controller deps; no PlayerGui; must start before GunController
  9.  MovementController:Start()      -- reads RoundStateChanged; reads MatchController:GetPhase(); owns
                                      --   movementState and Humanoid.WalkSpeed; reads camera.CFrame for
                                      --   direction detection (no camera.CFrame writes); must start before
                                      --   GunController so GetMoveState() / IsADSBlocked() return valid state
  10. GunController:Start()           -- reads MatchController:GetPhase(); calls ViewModelController, CrosshairUI,
                                      --   SoundController, MovementController
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

## Character Rig Target

**Current rig: R6** (set 2026-05-18)

`StarterPlayer.CharacterRigType` is set to `Enum.HumanoidRigType.R6` (ordinal 0) via `default.project.json`:

```json
"StarterPlayer": {
  "$className": "StarterPlayer",
  "$properties": {
    "CharacterRigType": { "Enum": 0 }
  }
}
```

**Also set manually in Studio:** `Game Settings → Avatar → Avatar Type → R6`. Studio does not always pick up the `CharacterRigType` property from Rojo on first sync — verify manually when setting up a new Studio session.

### R6 body-part reference

| Part | Role |
|---|---|
| `HumanoidRootPart` | Physics root |
| `Torso` | Central torso |
| `Head` | Head |
| `Left Arm` / `Right Arm` | Arms |
| `Left Leg` / `Right Leg` | Legs |

### Systems that must target R6

| System | R6 dependency |
|---|---|
| MovementController (Stage 2+) | Animation IDs must reference R6-rigged assets |
| RagdollService | Motor6D iteration is rig-agnostic; per-part name filtering (if added) must use R6 names |
| Future hitbox system | Part-name lookups must use R6 names |
| Future weapon alignment | Attachment points on `Right Arm` / `Torso` must match R6 geometry |

> **Note (legacy transitional):** `RagdollService` currently iterates all `Motor6D` descendants without filtering by part name — this is rig-agnostic and works correctly for both R6 and R15. No change required. The constraint above applies to new code only.

---

## New Target Architecture (persistent zone — planned 2026-05-15)

The project is pivoting to a persistent PvPvE zone shooter. The systems below are the planned target architecture. None are built yet unless explicitly noted. Build one at a time.

### Planned future services

| Service | Purpose | Status |
|---|---|---|
| `ZoneService` | Manages the persistent zone: player entry/exit, zone state, no round timer | Not started |
| `BaseService` | Owns the safe base area: spawn points, armory access, deposit terminal | Not started |
| `EconomyService` | Owns carried cash and secured funds per player; validates deposits | Not started |
| `LootService` | Spawns and tracks loot objects in the zone; respawns on pickup | Not started |
| `DeathDropService` | Creates a droppable bag at death position with player's weapon and carried cash | Not started |
| `ExtractionService` | Handles extraction exit triggers; credits secured funds on successful extract | Not started |
| `ShopService` | Validates and fulfills zone shop (carried cash) and base armory (secured funds) purchases | Not started |
| `ZoneEventService` | Owns periodic zone events (timed loot surges, cash bonuses, monster waves); creates pressure without breaking the core loop | Not started (deferred) |
| `InventoryService` | Tracks equipped weapon and held consumables per player | Not started (deferred) |
| `StashService` | Persistent stash across sessions (server-side storage) | Not started (deferred) |
| `ProgressionService` | Reputation, unlocks, faction standing | Not started (deferred) |
| `MonsterService` | Zone AI enemies; carried forward from legacy plan | Not started |

> **First persistent-zone code milestone:** Build `EconomyService` (carried cash + secured funds) and the deposit/extraction trigger before any other new system. The core carried-cash → deposit → secured-funds loop is the foundation everything else depends on.

> **Staged implementation plan:** See `docs/PERSISTENT_ZONE_ROADMAP.md` for the full 11-stage build order, per-stage scope gates, files affected, and Studio verification requirements.

### Legacy services and their fate

| Service | Legacy role | Target fate |
|---|---|---|
| `MatchService` | Round loop, phase management | Replace with ZoneService over time; do not expand |
| `TeamService` | Attackers/Defenders assignment | Refactor into faction/spawn management or retire |
| `ObjectiveService` | Anchor planting objectives | Replace with zone events or contracts |

### Reusable systems (carry forward as-is)

These systems are architecture-agnostic and remain valid in the persistent zone design:

| System | Notes |
|---|---|
| `GunService` | Server-authoritative shot validation; reuse directly |
| `DamageService` | Health mutation, friendly-fire guard, kill feed; reuse directly |
| `RagdollService` | Ragdoll on death; reuse directly |
| `RemoteSetup` | Remote creation; extend with new remote names as needed |
| `GunController` | Client input, cosmetic raycast; reuse directly |
| `ViewModelController` | Viewmodel render; reuse directly |
| `SoundController` | Audio; reuse directly |
| `HUD` (ammo, health) | Reuse ammo and health panels; add cash display panels |
| `KillFeedUI` | Reuse as-is |
| `WeaponData` | Weapon stats data module; extend with new weapons |
| `Logger` | Reuse as-is |
| `Constants` | Extend with new economy/zone constants |

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
