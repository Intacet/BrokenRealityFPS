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
ZoneService (server)   [LEGACY NAME — will be repurposed for persistent zone entry/exit state]
  │  owns: per-map physics overrides (gravity, walkspeed, fog density)
  └─ fires: ZoneEffectApplied → all clients (visual overlay trigger)
```

### AI (planned — not yet built)

```
MonsterService (server)
  │  owns: individual monster agents, pathfinding, attack logic
  │  targets: all players (no team distinction in persistent zone mode)
  │  Stage 8 on the persistent zone roadmap — built after shops, missions, and events
  │
HordeService (server)   [LEGACY PLAN — replaced by ambient zone spawn budget in persistent zone]
  │  owns: wave timing, spawn budget, escalation across rounds
  └─ calls: MonsterService:SpawnMonster()
```

---

### Planned persistent-zone systems (not yet built — see docs/PERSISTENT_ZONE_ROADMAP.md)

The systems below are the target architecture for Milestone 1 (persistent zone). None are started yet. Build order and stage specs are in `docs/PERSISTENT_ZONE_ROADMAP.md`.

```
ZoneService (server) [Stage 1 — repurposed from legacy name above]
  │  owns: persistent zone state (no round timer; re-entry always open)
  │  owns: zone entry/exit gate state
  │  owns: player-in-zone tracking
  └─ fires: ZoneStateChanged → all clients

EconomyService (server) [Stage 2]
  │  owns: carried cash balance per player (server-authoritative; never trust client)
  │  owns: secured funds balance per player (never lost on death)
  │  owns: deposit logic (carried cash → secured funds via physical terminal)
  └─ fires: EconomyChanged → affected client (display only)

ExtractionService (server) [Stage 3]
  │  owns: extraction trigger validation (player physically reached exit)
  │  owns: carried cash → secured funds credit on successful extraction
  └─ fires: ExtractionSuccess → affected client

DeathDropService (server) [Stage 4]
  │  owns: death drop bag creation (position, contents)
  │  owns: drop pickup validation
  └─ fires: DeathDropSpawned / DeathDropPickedUp → all clients (in range)

ShopService (server) [Stage 5]
  │  owns: zone shop and base armory purchase validation
  │  owns: price table (server-authoritative; client never decides price)
  │  deducts carried cash (zone shop) or secured funds (base armory)
  └─ fires: PurchaseResult → purchasing client

LootService (server) [Stage 5]
  │  owns: loot object spawn positions and remaining contents
  │  owns: loot pickup validation
  └─ fires: LootSpawned / LootPickedUp → all clients (in range)

MissionService (server) [Stage 6]
  │  owns: faction trader mission state per player
  │  owns: mission accept, progress, and completion validation
  └─ fires: MissionUpdated / MissionComplete → affected client

ZoneEventService (server) [Stage 7]
  │  owns: Reality Breakdown event timers and state
  │  owns: loot surge, monster escalation, zone spread logic
  └─ fires: ZoneEventStarted / ZoneEventEnded → all clients

BaseService (server) [Stage 9]
  │  owns: safe metro base area (no PvP, no monsters)
  │  owns: base upgrade state (armory tier, storage tier, medical tier)
  │  owns: upgrade purchase validation (secured funds only)
  └─ fires: BaseStateChanged → affected client

StashService (server) [Stage 9]
  │  owns: per-player persistent stash contents
  │  owns: stash deposit/withdraw validation
  └─ fires: StashChanged → affected client

MonsterService (server) [Stage 8]
  │  owns: ambient zone monster agents, pathfinding, attack logic
  │  (see AI section above)
```

**NOT planned for first playable version — explicitly deferred:**

```
FleaMarketService / PlayerMarketplace
  │  DEFERRED — do not build until economy, stash, item ownership, anti-duplication,
  │  and moderation/abuse controls are stable and intentionally addressed.
  │  "Player-to-player marketplace" is a long-term feature, not a first-playable feature.
```

---

### Metro base design notes

- The **metro station** is the primary safe-base fantasy. Players spawn here, deposit earnings, visit traders, upgrade their operation, and re-enter the zone.
- The metro base is a **physical space** in Workspace, not an abstract menu. Players walk to the deposit terminal, walk to the armory, walk to traders.
- **Future storage and back-room upgrades** happen here — lockers, crates, expanded armory, medical bay. These are Stage 9.
- **Train arrival/departure sequences** are atmospheric polish. They are desirable but must be skippable. Do not build train cinematics until the core loop is proven. If implemented, always provide an instant-skip option (tap to skip, or just a collider trigger).
- The metro base currency is **secured funds only**. Carried cash is not spendable at the base — only at zone shops or at the deposit terminal (which converts it to secured funds).

---

### Zone entry/exit design notes

- Zone transitions must be **physical** — gates, train routes, sewer tunnels, and checkpoint exits are valid. No abstract teleport menu or instant loading screen.
- **Multiple exits** should exist eventually to prevent extraction camping at a single point. The first playable version may have one exit; add more when the extraction loop is proven.
- **Multiple entrances** can be added later to spread player spawn distribution in the zone.
- Valid transition types: checkpoint gate (walk through), train stop (board/exit), sewer hatch, tunnel, surface checkpoint.
- ZoneService owns gate state (open/locked/destroyed) and validates that a player physically reached an exit before extraction is credited.
- ExtractionService fires `ExtractionSuccess` to EconomyService for the carried-cash → secured-funds credit. The client cannot trigger this unilaterally.

### Presentation (client only, no server impact)

```
MovementController      -- Stage 1 + 2A + 2C + 2D + 2E + 2F + 2G + 2H + 2I (Animate-disable, R6 detection, animation-set selection,
                        --   strafe gating, animation speed multipliers, shift-lock sprint fix,
                        --   custom mouse-lock toggle on LeftAlt, character-facing camera yaw):
                        --   owns local movement input (LeftShift=sprint, C=hold-to-crouch (hold=enter, release=exit),
                        --   LeftAlt=custom mouse-lock toggle),
                        --   customMouseLocked boolean, UserInputService.MouseBehavior writes,
                        --   Humanoid.AutoRotate writes (false while locked+ACTIVE; restored on off/exit/respawn),
                        --   HumanoidRootPart.CFrame yaw writes (facing camera yaw while locked; position unchanged),
                        --   movementState table, Humanoid.WalkSpeed, R6 animation playback,
                        --   character.Animate suppression (R6 characters only),
                        --   presentation-only equippedWeaponName for animation set selection, and
                        --   strafe animation gating via customMouseLocked (NOT Roblox default Shift Lock).
                        --   Reads workspace.CurrentCamera.CFrame for 8-directional camera-relative
                        --   direction detection AND for camera yaw facing (Stage 2E).
                        --   Writes UserInputService.MouseBehavior (LockCenter on, Default off) for
                        --   custom mouse lock — does NOT use MouseBehavior as strafe gate source.
                        --   Does NOT write camera.CFrame, CameraOffset, or FieldOfView.
                        --   Does NOT implement a full custom camera controller.
                        --   No new remotes. No slide, vault, or camera effects.
                        --   StarterPlayer.EnableMouseLockOption = false is now set in default.project.json
                        --     (Rojo "Bool" property) — no manual Studio step required for this setting.
                        --   LocalPlayer.DevEnableMouseLock = false is also applied client-side on Start
                        --     and on each CharacterAdded via disableRobloxDefaultMouseLock() (pcall).
                        --
                        --   Custom mouse-lock toggle (Stage 2D — 2026-05-19):
                        --     LeftAlt (Constants.CUSTOM_MOUSE_LOCK_TOGGLE_KEY) toggles customMouseLocked.
                        --     LeftShift is sprint-only — no longer conflicts with Roblox Shift Lock.
                        --     customMouseLocked is the source of truth for strafe animation gating.
                        --     SetCustomMouseLocked(true):  customMouseLocked=true,  MouseBehavior=LockCenter.
                        --     SetCustomMouseLocked(false): customMouseLocked=false, MouseBehavior=Default.
                        --     Mouse lock is released to Default ONLY when:
                        --       • character respawns (loadMovementAnimations reset)
                        --       • destroy() is called
                        --     Phase exits (ACTIVE → LOBBY → RESULTS) do NOT reset customMouseLocked.
                        --     The player's LeftAlt toggle state is preserved across all phase changes.
                        --     Gated by Constants.CUSTOM_MOUSE_LOCK_ENABLED (default true).
                        --     This is NOT a full custom camera system — LockCenter locks the cursor but
                        --     camera rotation still runs through the Roblox default camera controller.
                        --
                        --   Stage 2D bugfix (2026-05-19):
                        --     disableRobloxDefaultMouseLock() — called in Start() and on every
                        --       CharacterAdded; uses pcall on LocalPlayer.DevEnableMouseLock = false;
                        --       gated by Constants.DISABLE_ROBLOX_DEFAULT_MOUSE_LOCK (default true).
                        --     ContextActionService:BindActionAtPriority — replaces UserInputService.InputBegan
                        --       for the LeftAlt toggle. Priority 3000 (> CoreScript default 2000) eliminates
                        --       the ~1-frame input lag. Action name: MOUSE_LOCK_ACTION_NAME (module constant).
                        --       Unbound by name in destroy(); NOT stored in _connections.
                        --     Reapply-every-frame — Heartbeat re-writes MouseBehavior = LockCenter while
                        --       customMouseLocked is true; prevents CoreScripts from stealing the lock state.
                        --       Gated by Constants.CUSTOM_MOUSE_LOCK_REAPPLY_EVERY_FRAME (default true).
                        --     default.project.json EnableMouseLockOption = false — StarterPlayer property
                        --       set via Rojo "Bool" syntax; replaces the previous "Manual Studio step".
                        --
                        --   Strafe animation gating (Stage 2C + 2D):
                        --     WalkLeft/WalkRight only play when customMouseLocked == true (LeftAlt on).
                        --     Previously (Stage 2C): gated on UserInputService.MouseBehavior == LockCenter
                        --       (Roblox native shift-lock detection). That path is now the legacy fallback
                        --       when CUSTOM_MOUSE_LOCK_STRAFE_ANIMS_ONLY = false.
                        --     Stage 2D primary path (CUSTOM_MOUSE_LOCK_STRAFE_ANIMS_ONLY = true, default):
                        --       isMouseLockedForStrafeAnimations() returns customMouseLocked.
                        --     Without custom mouse lock, left/right/diagonal movement falls back to WalkForward.
                        --     Sprint uses RunForward in all directions regardless of customMouseLocked.
                        --     Outer gate: MOVEMENT_STRAFE_ANIMS_REQUIRE_MOUSE_LOCK (kept, still true).
                        --
                        --   LeftShift sprint + shift-lock fix (Stage 2C — 2026-05-18):
                        --     Sprint InputBegan no longer uses the gameProcessed (gp) guard for LeftShift.
                        --     Roblox's built-in shift-lock marks Shift as gameProcessed = true, which
                        --     previously silently blocked sprint while shift lock was active.
                        --     Fix: sprint only blocks if UserInputService:GetFocusedTextBox() ~= nil
                        --     (player is typing). All other gameProcessed reasons (including shift lock)
                        --     are allowed through for LeftShift only. Crouch (C key) still uses gp guard.
                        --
                        --   Animation playback speed multipliers (Stage 2C — 2026-05-18):
                        --     AnimationTrack:AdjustSpeed() is called on play. Speeds do NOT change
                        --     Humanoid.WalkSpeed. Values from Constants.lua:
                        --       MOVEMENT_WALK_ANIMATION_SPEED_MULTIPLIER   = 1.3  (WalkForward/Backward/diagonals)
                        --       MOVEMENT_STRAFE_ANIMATION_SPEED_MULTIPLIER = 1.4  (WalkLeft, WalkRight)
                        --       MOVEMENT_RUN_ANIMATION_SPEED_MULTIPLIER    = 1.15 (RunForward, RunForwardLeft, RunForwardRight)
                        --
                        --   Animation set selection (added 2026-05-18):
                        --     Default animation set is Unarmed (no gun) when equippedWeaponName == nil.
                        --     AR15 animation set plays only after SetEquippedWeaponName("AR15") is called.
                        --     equippedWeaponName is PRESENTATION ONLY — it does not affect server weapon
                        --     state, ammo, damage, hit validation, reload, or inventory.
                        --     True server-owned equipment state is deferred — see DEBT-050.
                        --     SetEquippedWeaponName(nil or "") → Unarmed set.
                        --     SetEquippedWeaponName("AR15") → AR15 set.
                        --     Any other name → Unarmed fallback + one-time warn.
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
                        --
                        --   Stage 2E — character-facing camera yaw (2026-05-19):
                        --     When CUSTOM_MOUSE_LOCK_FACE_CAMERA_YAW = true (default):
                        --       Enabling LeftAlt mouse lock: caches Humanoid.AutoRotate →
                        --         originalAutoRotate, sets AutoRotate = false, calls applyCharacterFacing().
                        --       Every Heartbeat while locked: getCameraFlatLookVector() reads
                        --         workspace.CurrentCamera.CFrame.LookVector, flattens to XZ.
                        --         HumanoidRootPart.CFrame = CFrame.lookAt(pos, pos+flatLook).
                        --         Position is preserved — NOT a teleport.
                        --       Toggle-off: restoreCharacterAutoRotate(), clears originalAutoRotate.
                        --       Phase exit (REQUIRE_ACTIVE=true): restoreCharacterAutoRotate()
                        --         but originalAutoRotate is preserved (NOT cleared) for re-entry.
                        --       ACTIVE re-entry with lock still on: AutoRotate=false again, applyCharacterFacing().
                        --       Respawn: originalAutoRotate = nil; new Humanoid starts fresh.
                        --       Destroy: restoreCharacterAutoRotate() if locked, then clear all.
                        --     getCameraFlatLookVector() returns nil if XZ magnitude < 0.001 (near-vertical
                        --       camera); applyCharacterFacing() skips gracefully.
                        --     lastFacingSkippedReason deduplicates skip-reason debug logs (once per change).
                        --     New constants: CUSTOM_MOUSE_LOCK_FACE_CAMERA_YAW,
                        --       CUSTOM_MOUSE_LOCK_REQUIRE_ACTIVE_FOR_CHARACTER_ROTATION,
                        --       CUSTOM_MOUSE_LOCK_ROTATION_DEBUG.
                        --
                        --   Stage 2A + 2C + 2D + 2F animation support (R6 only):
                        --     Loads AnimationTrack objects per character via Humanoid.Animator.
                        --     Both Unarmed and AR15 tracks pre-loaded at spawn for instant set switching.
                        --     Plays during ACTIVE phase only; stops on phase exit and when not moving.
                        --     WalkLeft/WalkRight (pure lateral strafe) only when customMouseLocked == true (LeftAlt on).
                        --     WalkBackward plays for Backward regardless of mouse-lock (Unarmed only).
                        --     WalkForwardLeft/Right and WalkBackwardLeft/Right play regardless of mouse-lock (Unarmed only).
                        --     AR15 set: unchanged — left/right grouping with WalkForward fallback.
                        --     Debug: set-change and strafe-blocked-change logged once per change.
                        --     Animation IDs (Constants.MOVEMENT_ANIMATION_IDS.R6):
                        --       Unarmed.WalkForward       = rbxassetid://97200177177374
                        --       Unarmed.RunForward        = rbxassetid://81826691810907
                        --       Unarmed.WalkLeft          = rbxassetid://115652140967957
                        --       Unarmed.WalkRight         = rbxassetid://82804864629403
                        --       Unarmed.WalkBackward      = rbxassetid://107080862064563  (Stage 2F)
                        --       Unarmed.WalkBackwardLeft  = rbxassetid://107785647885776  (Stage 2F)
                        --       Unarmed.WalkBackwardRight = rbxassetid://109190640713438  (Stage 2F)
                        --       Unarmed.WalkForwardLeft   = rbxassetid://97324289156918   (Stage 2F)
                        --       Unarmed.WalkForwardRight  = rbxassetid://81077784555491   (Stage 2F)
                        --       Unarmed.RunForwardLeft    = rbxassetid://94337945101783   (Stage 2G — mouse-lock-gated sprint diagonal)
                        --       Unarmed.RunForwardRight   = rbxassetid://104724352837263  (Stage 2G — mouse-lock-gated sprint diagonal)
                        --       Unarmed.Idle              = rbxassetid://132044223555193  (Stage 2H — standing idle, looped)
                        --       Unarmed.EnterCrouch       = rbxassetid://105064599119554  (Stage 2H — enter-crouch one-shot)
                        --       Unarmed.ExitCrouch        = rbxassetid://104596765238289  (Stage 2H — exit-crouch one-shot)
                        --       AR15.WalkForward          = rbxassetid://138802532485746
                        --       AR15.RunForward           = rbxassetid://79735501581082
                        --       AR15.Idle                 = rbxassetid://117989834436525  (Stage 2H — standing idle, looped)
                        --       AR15.EnterCrouch          = rbxassetid://79753647497328   (Stage 2H — enter-crouch one-shot)
                        --       AR15.ExitCrouch           = rbxassetid://91295776984408   (Stage 2H — exit-crouch one-shot)
                        --     (IDs updated 2026-05-20 — Unarmed strafe-left/right swapped to confirmed-good R6 clips;
                        --       Stage 2F (2026-05-20) — 5 new Unarmed walk directional clips added;
                        --       2026-05-20 — Unarmed WalkForward + RunForward replaced with confirmed-good R6 clips;
                        --       Stage 2G (2026-05-20) — RunForwardLeft + RunForwardRight added; mouse-lock-gated sprint diagonals;
                        --       Stage 2H (2026-05-20) — Idle + EnterCrouch/ExitCrouch added for both sets)
                        --     Sprint diagonal behavior (Stage 2G):
                        --       Unarmed + customMouseLocked ON: ForwardLeft sprint → RunForwardLeft; ForwardRight sprint → RunForwardRight.
                        --       Unarmed + customMouseLocked OFF: all sprint directions → RunForward.
                        --       AR15/gun-equipped: all sprint directions → AR15 RunForward (no run diagonals).
                        --     Idle behavior (Stage 2H):
                        --       Both sets: Idle (looped) plays when standing still in ACTIVE phase.
                        --       Idle plays via updateMovementAnimation (not moving path) — no special gate.
                        --     Crouch hold behavior (Stage 2I — 2026-05-20):
                        --       C is now hold-to-crouch: InputBegan (C held) → enter crouch + EnterCrouch one-shot;
                        --         InputEnded (C released) → exit crouch + clearCrouchBottomHold() + ExitCrouch one-shot.
                        --       After EnterCrouch finishes (Stopped callback): if still crouching and moving and a
                        --         CrouchWalk ID exists → play CrouchWalk; otherwise → holdCrouchBottomPose():
                        --         plays EnterCrouch at AdjustSpeed(0) parked at (Length - CROUCH_TRANSITION_MIN_HOLD_TIME)
                        --         so the character visually holds the bottom of the crouched pose.
                        --       clearCrouchBottomHold(): restores AdjustSpeed then Stop(fade). Called on C-release,
                        --         phase exit, and destroy(). On respawn, variables cleared without Stop (old Animator gone).
                        --       crouchHoldTrack is managed independently of currentAnimationName — not stopped by
                        --         stopCurrentMovementAnimation(), preventing standing locomotion from overwriting the pose.
                        --       updateMovementAnimation() crouch branch (returns early, before standing logic):
                        --         moving + CrouchWalk ID exists → CrouchWalk; moving + no CrouchWalk → hold bottom pose;
                        --         idle → hold bottom pose.
                        --       No HipHeight, CameraOffset, or camera.CFrame changes. CrouchWalk is optional — only plays
                        --         if an ID already exists in Constants.MOVEMENT_ANIMATION_IDS.R6.<Set>.CrouchWalk.
                        --       New constants: CROUCH_HOLD_KEY, CROUCH_HOLD_BOTTOM_POSE_ENABLED,
                        --         CROUCH_TRANSITION_MIN_HOLD_TIME, CROUCH_BOTTOM_HOLD_TIME_POSITION_FALLBACK.
                        --     Crouch transition behavior (Stage 2H):
                        --       crouchTransitionPlaying flag gates updateMovementAnimation during in-flight one-shot.
                        --       clearCrouchTransitionConnection() (renamed from stopCrouchTransition() in Stage 2I)
                        --         disconnects the Stopped conn only; callers manage crouchTransitionPlaying explicitly.
                        --     Not in Stage 2A/2C/2D/2F/2G/2H/2I: CrouchWalk/CrouchIdle animation IDs (no IDs added in 2I),
                        --       lower/upper-body split, reload/fire/ADS weapon animations.
                        --
                        --   Exposes: GetMovementState() → table; GetMoveState() → string (GunController
                        --   compat); IsADSBlocked() → bool; GetViewmodelAddCFrame() → identity;
                        --   SetEquippedWeaponName(name: string?) → switches animation set (presentation only);
                        --   GetEquippedWeaponName() → string? (nil = Unarmed set active);
                        --   SetCustomMouseLocked(bool) → toggles custom mouse lock; writes MouseBehavior;
                        --   IsCustomMouseLocked() → bool (true = LeftAlt mouse lock is active);
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
             --   Movement animation set name constants:
             --     MOVEMENT_ANIMATION_SET_UNARMED = "Unarmed" — key for the no-gun animation set.
             --     MOVEMENT_ANIMATION_SET_AR15    = "AR15"    — key for the AR15 animation set.
             --     MOVEMENT_DEFAULT_ANIMATION_SET = MOVEMENT_ANIMATION_SET_UNARMED — project default.
             --   Movement animation control constants (all default true):
             --     CUSTOM_MOVEMENT_ANIMATIONS_ENABLED — master switch; false disables all
             --       custom movement track loading and playback; Animate runs as normal.
             --     DISABLE_DEFAULT_ANIMATE_FOR_CUSTOM_MOVEMENT — when true, MovementController
             --       sets character.Animate.Disabled = true before loading custom tracks;
             --       false leaves Animate running (may cause override/blend conflicts).
             --     MOVEMENT_ANIMATION_DEBUG — when true, logs animation load, switch,
             --       set-change, and strafe-blocked-change events; set false in production.
             --     MOVEMENT_STRAFE_ANIMS_REQUIRE_MOUSE_LOCK = true — outer gate: strafe anims
             --       require some form of mouse lock. When CUSTOM_MOUSE_LOCK_STRAFE_ANIMS_ONLY
             --       is true (default), source is customMouseLocked, not native ShiftLock.
             --   Custom mouse-lock constants (Stage 2D — 2026-05-19):
             --     CUSTOM_MOUSE_LOCK_ENABLED = true — enables LeftAlt custom mouse-lock toggle.
             --     CUSTOM_MOUSE_LOCK_TOGGLE_KEY = Enum.KeyCode.LeftAlt — toggle key.
             --     CUSTOM_MOUSE_LOCK_STRAFE_ANIMS_ONLY = true — when true, strafe gating reads
             --       customMouseLocked (not UserInputService.MouseBehavior / Roblox ShiftLock).
             --     CUSTOM_MOUSE_LOCK_DEBUG = true — logs mouse-lock toggle events to Output.
             --   Custom mouse-lock bugfix constants (Stage 2D bugfix — 2026-05-19):
             --     DISABLE_ROBLOX_DEFAULT_MOUSE_LOCK = true — gates disableRobloxDefaultMouseLock()
             --       which sets LocalPlayer.DevEnableMouseLock = false on Start and CharacterAdded.
             --     CUSTOM_MOUSE_LOCK_REAPPLY_EVERY_FRAME = true — Heartbeat re-writes MouseBehavior
             --       = LockCenter every frame while customMouseLocked is true.
             --     CUSTOM_MOUSE_LOCK_INPUT_PRIORITY = 3000 — ContextActionService priority for LeftAlt
             --       bind; 3000 > CoreScript default 2000 ensures immediate response.
             --   Movement animation playback speed multipliers (updated Stage 2H 2026-05-20):
             --     MOVEMENT_WALK_ANIMATION_SPEED_MULTIPLIER              = 1.3  (WalkForward/Backward/diagonals)
             --     MOVEMENT_STRAFE_ANIMATION_SPEED_MULTIPLIER            = 1.4  (WalkLeft, WalkRight)
             --     MOVEMENT_RUN_ANIMATION_SPEED_MULTIPLIER               = 1.15 (RunForward, RunForwardLeft, RunForwardRight)
             --     MOVEMENT_IDLE_ANIMATION_SPEED_MULTIPLIER              = 0.75 (Idle — Stage 2H)
             --     MOVEMENT_CROUCH_TRANSITION_ANIMATION_SPEED_MULTIPLIER = 0.9  (EnterCrouch, ExitCrouch — Stage 2H)
             --   Crouch hold constants (Stage 2I — 2026-05-20):
             --     CROUCH_HOLD_KEY = Enum.KeyCode.C — key held to enter/stay crouched; release exits crouch.
             --     CROUCH_HOLD_BOTTOM_POSE_ENABLED = true — enables EnterCrouch clip frozen at final frame
             --       (AdjustSpeed(0) + TimePosition near end) after the one-shot finishes.
             --     CROUCH_TRANSITION_MIN_HOLD_TIME = 0.05 — seconds from clip end; guards against TimePosition
             --       snapping to frame 0 at exact Length on some Roblox versions.
             --     CROUCH_BOTTOM_HOLD_TIME_POSITION_FALLBACK = 0.98 — used when EnterCrouch.Length == 0.
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
