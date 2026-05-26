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
MovementController      -- Stage 1 + 2A + 2C + 2D + 2E + 2F + 2G + 2H + 2I + 2J + 2K + 2L + 2M + 2N + 2O + 2P + 2Q + 2Q+ + 2R + 3A + 3B (Animate-disable, R6 detection, animation-set selection,
                        --   strafe gating, animation speed multipliers, shift-lock sprint fix,
                        --   custom mouse-lock toggle on LeftControl, character-facing camera yaw,
                        --   third-person zoom limits, mouse-lock camera distance and shoulder offset,
                        --   directional sprint selection via getSprintAnimationName (Stage 2R)):
                        --   owns local movement input (LeftShift=sprint, C=hold-to-crouch (hold=enter, release=exit),
                        --   LeftControl=custom mouse-lock toggle),
                        --   customMouseLocked boolean, UserInputService.MouseBehavior writes,
                        --   Humanoid.AutoRotate writes (false while locked+ACTIVE; restored on off/exit/respawn),
                        --   HumanoidRootPart.CFrame yaw writes (facing camera yaw while locked; position unchanged),
                        --   Players.LocalPlayer.CameraMinZoomDistance and CameraMaxZoomDistance writes (Stage 2K),
                        --   Humanoid.CameraOffset writes (Stage 2K — Vector3.new(1.75,0,0) while locked; zero when off),
                        --   movementState table, Humanoid.WalkSpeed, R6 animation playback,
                        --   character.Animate suppression (R6 characters only),
                        --   presentation-only equippedWeaponName for animation set selection, and
                        --   strafe animation gating via customMouseLocked (NOT Roblox default Shift Lock).
                        --   Reads workspace.CurrentCamera.CFrame for 8-directional camera-relative
                        --   direction detection AND for camera yaw facing (Stage 2E).
                        --   Writes UserInputService.MouseBehavior (LockCenter on, Default off) for
                        --   custom mouse lock — does NOT use MouseBehavior as strafe gate source.
                        --   Writes workspace.CurrentCamera.FieldOfView via TweenService (Stage 3A —
                        --     sprint FOV stretch; see Sprint FOV section below). Never writes camera.CFrame.
                        --   Does NOT set CameraType to Scriptable.
                        --   Does NOT implement a full custom camera controller.
                        --   No new remotes. No slide, vault, or camera effects.
                        --   StarterPlayer.EnableMouseLockOption = false is now set in default.project.json
                        --     (Rojo "Bool" property) — no manual Studio step required for this setting.
                        --   LocalPlayer.DevEnableMouseLock = false is also applied client-side on Start
                        --     and on each CharacterAdded via disableRobloxDefaultMouseLock() (pcall).
                        --
                        --   Custom mouse-lock toggle (Stage 2D — 2026-05-19; key changed Stage 2K — 2026-05-20):
                        --     LeftControl (Constants.CUSTOM_MOUSE_LOCK_TOGGLE_KEY) toggles customMouseLocked.
                        --     Key was LeftAlt in Stage 2D; changed to LeftControl in Stage 2K to keep LeftAlt free.
                        --     LeftShift is sprint-only — no longer conflicts with Roblox Shift Lock.
                        --     customMouseLocked is the source of truth for strafe animation gating.
                        --     SetCustomMouseLocked(true):  customMouseLocked=true,  MouseBehavior=LockCenter,
                        --       CameraMin=CameraMax=8, CameraOffset=Vector3.new(1.75,0,0). (Stage 2K)
                        --     SetCustomMouseLocked(false): customMouseLocked=false, MouseBehavior=Default,
                        --       CameraMin=4, CameraMax=14, CameraOffset=Vector3.zero. (Stage 2K)
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
                        --     WalkLeft/WalkRight only play when customMouseLocked == true (LeftControl on).
                        --     Previously (Stage 2C): gated on UserInputService.MouseBehavior == LockCenter
                        --       (Roblox native shift-lock detection). That path is now the legacy fallback
                        --       when CUSTOM_MOUSE_LOCK_STRAFE_ANIMS_ONLY = false.
                        --     Stage 2D primary path (CUSTOM_MOUSE_LOCK_STRAFE_ANIMS_ONLY = true, default):
                        --       isMouseLockedForStrafeAnimations() returns customMouseLocked.
                        --     Without custom mouse lock, left/right/diagonal movement falls back to WalkForward.
                        --     Sprint with customMouseLocked OFF: always RunForward regardless of direction.
                        --     Sprint with customMouseLocked ON: always RunForward (all directions). (Stage 3J)
                        --       Stage 3G body rotation (raw MoveDirection, lerp 0.18) provides directional visual.
                        --       RunForwardLeft/Right loaded but never selected at runtime.
                        --     Directional sprint selection via getSprintAnimationName() helper (Stage 2R → simplified Stage 3J).
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
                        --       MOVEMENT_RUN_ANIMATION_SPEED_MULTIPLIER    = 1.15 (RunForward; RunForwardLeft/Right loaded but never selected since Stage 3J)
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
                        --       Unarmed.WalkForward       = rbxassetid://81276554788940   (Stage 2M — confirmed-good R6 no-gun walk forward)
                        --       Unarmed.WalkForwardAlt    = rbxassetid://97919904114609   (Stage 2M — alternate forward walk; loaded but not yet selected — no variation system)
                        --       Unarmed.RunForward        = rbxassetid://79045069356901   (Stage 2L — confirmed-good R6 no-gun run forward)
                        --       Unarmed.RunForwardTest    = rbxassetid://118179559114284  (test clip — active when MOVEMENT_RUN_FORWARD_USE_TEST_ANIMATION = true)
                        --       Unarmed.WalkLeft          = rbxassetid://127934481756733  (Stage 2M)
                        --       Unarmed.WalkRight         = rbxassetid://122034548466839  (Stage 2M)
                        --       Unarmed.WalkBackward      = rbxassetid://140436478515683  (Stage 2M)
                        --       Unarmed.WalkBackwardLeft  = rbxassetid://137714892165355  (Stage 2M)
                        --       Unarmed.WalkBackwardRight = rbxassetid://83443564844340   (Stage 2M)
                        --       Unarmed.WalkForwardLeft   = rbxassetid://137297382056770  (Stage 2M)
                        --       Unarmed.WalkForwardRight  = rbxassetid://133633696854516  (Stage 2M)
                        --       Unarmed.RunForwardLeft    = rbxassetid://94337945101783   (Stage 2G — loaded but NEVER SELECTED since Stage 3J; RunForward plays for all directions)
                        --       Unarmed.RunForwardRight   = rbxassetid://104724352837263  (Stage 2G — loaded but NEVER SELECTED since Stage 3J; RunForward plays for all directions)
                        --       Unarmed.Idle              = rbxassetid://132044223555193  (Stage 2H — standing idle, looped)
                        --       Unarmed.EnterCrouch       = rbxassetid://105064599119554  (Stage 2H — enter-crouch one-shot)
                        --       Unarmed.ExitCrouch        = rbxassetid://104596765238289  (Stage 2H — exit-crouch one-shot)
                        --       Unarmed.CrouchIdle            = rbxassetid://81947601552045   (Stage 2N — crouch idle looped; plays while crouched+still)
                        --       Unarmed.CrouchIdleAlt         = rbxassetid://132053404406349  (Stage 2N — deferred alternate; loaded, not yet selected)
                        --       Unarmed.CrouchWalk            = rbxassetid://70428646705219   (Stage 2N — crouch walk forward, canonical fallback alias; was 82558685099409)
                        --       Unarmed.CrouchWalkForward     = rbxassetid://70428646705219   (Stage 2N — crouch walk forward; was 82558685099409)
                        --       Unarmed.CrouchWalkBackward    = rbxassetid://131295440357763  (Stage 2J — crouch walk backward)
                        --       Unarmed.CrouchWalkLeft        = rbxassetid://103170217015576  (Stage 2J — crouch walk strafe left)
                        --       Unarmed.CrouchWalkRight       = rbxassetid://84961452934451   (Stage 2J — crouch walk strafe right)
                        --       Unarmed.CrouchWalkForwardLeft  = rbxassetid://115919203745144 (Stage 2J — crouch walk forward-left diagonal)
                        --       Unarmed.CrouchWalkForwardRight = rbxassetid://107284851359368 (Stage 2J — crouch walk forward-right diagonal)
                        --       Unarmed.CrouchWalkBackwardLeft  = rbxassetid://118800024223445 (Stage 2J — crouch walk backward-left diagonal)
                        --       Unarmed.CrouchWalkBackwardRight = rbxassetid://104285284019251 (Stage 2J — crouch walk backward-right diagonal)
                        --       Unarmed.CrouchWalkStart       = rbxassetid://129868628706658  (Stage 2N — one-shot idle-to-walk transition; plays once on first move while crouched)
                        --       Unarmed.Falling               = rbxassetid://86705296926580   (Stage 2O — looped falling clip; plays while Humanoid is in Freefall)
                        --       Unarmed.LandingLight          = rbxassetid://135438895968665  (Stage 3A — one-shot light landing; normal jumps + small drops ≤ 8 studs)
                        --       Unarmed.LandingMedium         = rbxassetid://135915211175953  (Stage 2O/3A — one-shot medium landing; sprint jumps + drops 8–18 studs)
                        --       Unarmed.LandingHeavy          = rbxassetid://72796290236543   (Stage 3A — one-shot heavy landing; drops ≥ 18 studs regardless of jump)
                        --       Unarmed.TacticalSprintForward1 = rbxassetid://135119369971434 (Stage 2P — looped tactical sprint forward, primary clip)
                        --       Unarmed.TacticalSprintForward2 = rbxassetid://110008857265859 (Stage 2P — alternate forward clip; loaded, not yet selected — no variation system)
                        --       Unarmed.TacticalSprintStop     = rbxassetid://81946205769343  (Stage 2P — one-shot stop clip; plays when tactical sprint ends)
                        --       Unarmed.LowVault    = rbxassetid://78932004147700   (DEFERRED — ID reserved; not loaded or selected; vault system not yet implemented)
                        --       Unarmed.MediumVault = rbxassetid://98948076922717   (DEFERRED — ID reserved; not loaded or selected; vault system not yet implemented)
                        --       Unarmed.SlideInto   = rbxassetid://101320244227398  (DEFERRED — ID reserved; not loaded or selected; slide system not yet implemented — see DEBT-053)
                        --       Unarmed.SlideIdle   = rbxassetid://123763519906235  (DEFERRED — ID reserved; not loaded or selected; slide system not yet implemented — see DEBT-053)
                        --       Unarmed.SlideExit   = rbxassetid://89774397391406   (DEFERRED — ID reserved; not loaded or selected; slide system not yet implemented — see DEBT-053)
                        --       AR15.WalkForward          = rbxassetid://138802532485746
                        --       AR15.RunForward           = rbxassetid://79735501581082
                        --       AR15.Idle                 = rbxassetid://117989834436525  (Stage 2H — standing idle, looped)
                        --       AR15.EnterCrouch          = rbxassetid://79753647497328   (Stage 2H — enter-crouch one-shot)
                        --       AR15.ExitCrouch           = rbxassetid://91295776984408   (Stage 2H — exit-crouch one-shot)
                        --     (IDs updated 2026-05-20 — Unarmed strafe-left/right swapped to confirmed-good R6 clips;
                        --       Stage 2F (2026-05-20) — 5 new Unarmed walk directional clips added;
                        --       Stage 2L (2026-05-20) — Unarmed WalkForward/RunForward replaced; sprint simplified to always use RunForward;
                        --       Stage 2M (2026-05-20) — All 8 Unarmed walk IDs replaced + WalkForwardAlt added (loaded, not yet selected);
                        --       Stage 2G (2026-05-20) — RunForwardLeft + RunForwardRight IDs added (retained in Constants; deferred in Stage 2L, active since Stage 2R);
                        --       Stage 2H (2026-05-20) — Idle + EnterCrouch/ExitCrouch added for both sets;
                        --       Stage 2J (2026-05-20) — 9 Unarmed CrouchWalk* directional IDs added;
                        --       Stage 2N (2026-05-20) — CrouchIdle, CrouchIdleAlt, CrouchWalkStart added; CrouchWalk/CrouchWalkForward IDs updated;
                        --       Stage 2O (2026-05-21) — Falling, LandingMedium added; 3 speed/timing constants added;
                        --       Stage 2P (2026-05-21) — TacticalSprintForward1, TacticalSprintForward2, TacticalSprintStop added;
                        --       Stage 2R (2026-05-21) — directional sprint selection enabled via getSprintAnimationName() helper;
                        --       Stage 3A (2026-05-21) — LandingLight + LandingHeavy IDs added; sprint FOV constants added;
                        --       2026-05-23 — LowVault + MediumVault IDs reserved in Constants; vault system deferred (see DEBT-052)
                        --       2026-05-26 — SlideInto + SlideIdle + SlideExit IDs reserved in Constants; slide system deferred (see DEBT-053))
                        --     Sprint behavior (Stage 3J — 2026-05-25, supersedes Stage 2R/3D):
                        --       All sprint directions (mouse lock ON or OFF): RunForward always.
                        --       Stage 3G body rotation (raw MoveDirection, lerp alpha=0.18) provides
                        --         directional visual — character body faces movement direction during sprint.
                        --       RunForwardLeft/RunForwardRight: loaded in animationTracks but never selected.
                        --       AR15/gun-equipped: sprinting uses AR15 RunForward in all directions (no AR15 run diagonals).
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
                        --     Crouch-walk behavior (Stage 2J — 2026-05-20):
                        --       Nine Unarmed CrouchWalk* IDs added (CrouchWalk/CrouchWalkForward share the same asset).
                        --       All tracks looped. Speed multiplier: MOVEMENT_CROUCH_WALK_ANIMATION_SPEED_MULTIPLIER = 1.0.
                        --       customMouseLocked OFF → CrouchWalkForward fallback (no directional strafe while crouching).
                        --       customMouseLocked ON  → 8-directional selection (same gate as walk strafe animations).
                        --       AR15/gun-equipped: no CrouchWalk IDs — falls back to crouch bottom-pose hold (deferred).
                        --       Crouch visuals: no Humanoid.HipHeight, CameraOffset, or camera.CFrame changes.
                        --     Crouch idle + walk-start behavior (Stage 2N — 2026-05-20):
                        --       CrouchIdle (looped): plays when crouched + not moving. Preferred over holdCrouchBottomPose()
                        --         when the track is loaded. Falls back to holdCrouchBottomPose() when absent.
                        --         playMovementAnimation() guard prevents restart every Heartbeat frame.
                        --       CrouchIdleAlt: deferred alternate. Loaded but never selected until variation system built.
                        --       CrouchWalkStart (one-shot): plays exactly once when the player starts moving while crouched.
                        --         wasMovingWhileCrouching flag tracks first-movement-burst. Reset to false on stop/respawn.
                        --         Set true in EnterCrouch Stopped callback when already moving — skips CrouchWalkStart.
                        --         clearCrouchWalkStart() (mirrors clearCrouchTransitionConnection pattern) must be called
                        --         before any external Stop to prevent spurious callbacks.
                        --       Speed multiplier for CrouchIdle/CrouchIdleAlt: MOVEMENT_CROUCH_WALK_ANIMATION_SPEED_MULTIPLIER (1.0×).
                        --       AR15/non-Unarmed: no CrouchIdle or CrouchWalkStart tracks — bottom-pose hold fallback unchanged.
                        --     Falling + landing behavior (Stage 2O — 2026-05-21):
                        --       Humanoid.StateChanged connected per-character in setupCharacter() (stateChangedConn).
                        --       Freefall → isFalling = true; airStartTime captured; Falling looped clip plays.
                        --         updateMovementAnimation() gated: isFalling → return early (Heartbeat cannot override).
                        --         Falling track only for Unarmed set; AR15 gracefully skips (animationTracks[key] ~= nil guard).
                        --       Landed / Running → isFalling = false; Falling stops; LandingMedium plays if:
                        --         airTime ≥ MOVEMENT_LANDING_ANIMATION_MIN_AIR_TIME (0.25s) AND not crouching
                        --         AND not crouchTransitionPlaying AND LandingMedium track exists.
                        --         isLandingPlaying gates updateMovementAnimation until LandingMedium Stopped fires.
                        --         After LandingMedium Stopped: clearLandingConnection() releases gate; Idle resumes next Heartbeat.
                        --       Short hops (< 0.25s freefall), crouched landing, and in-flight transitions: LandingMedium skipped.
                        --       New constants: MOVEMENT_FALLING_ANIMATION_SPEED_MULTIPLIER=1.0,
                        --         MOVEMENT_LANDING_ANIMATION_SPEED_MULTIPLIER=1.0, MOVEMENT_LANDING_ANIMATION_MIN_AIR_TIME=0.25.
                        --       clearLandingConnection() mirrors clearCrouchTransitionConnection() / clearCrouchWalkStart() patterns.
                        --       stateChangedConn is NOT in _connections — disconnected in loadMovementAnimations() top + destroy().
                        --     Tactical sprint behavior (Stage 2P — 2026-05-21):
                        --       Double-tap LeftShift while moving forward in ACTIVE phase starts tactical sprint.
                        --       Double-tap window: TACTICAL_SPRINT_DOUBLE_TAP_WINDOW = 0.3s.
                        --       Forward check: MoveDirection·camera-flat-forward ≥ TACTICAL_SPRINT_MIN_FORWARD_DOT (0.35).
                        --       Speed ramp: WalkSpeed lerps from SPRINT_SPEED (22) to TACTICAL_SPRINT_SPEED (30)
                        --         over TACTICAL_SPRINT_ACCELERATION_TIME (1.0s) each frame in applySpeed().
                        --       Animation: TacticalSprintForward1 (looped) plays via updateMovementAnimation() sprint branch.
                        --         TacticalSprintForward2 is loaded but never selected (no variation system yet).
                        --       Ends when: LeftShift released, C (crouch) pressed, player stops moving,
                        --         forward-dot drops below MIN_FORWARD_DOT, or phase leaves ACTIVE.
                        --       Stop animation: TacticalSprintStop (one-shot) plays when tactical sprint ends
                        --         (gated by TACTICAL_SPRINT_STOP_ANIMATION_ENABLED = true).
                        --         tacticalSprintStopConn gate in updateMovementAnimation() prevents Heartbeat
                        --         overriding the one-shot (mirrors landingConn / crouchWalkStartConn pattern).
                        --       Phase exit (non-ACTIVE): directly clears state WITHOUT playing TacticalSprintStop
                        --         (no visible effect during phase transitions).
                        --       stopTacticalSprint() has 4 call sites: LeftShift InputEnded, crouch InputBegan,
                        --         Heartbeat isMoving=false, Heartbeat fwdDot < MIN_FORWARD_DOT.
                        --       Gun block: TACTICAL_SPRINT_BLOCKS_GUN_USE = true → GunController blocks
                        --         WeaponFired and ReloadRequest while IsTacticalSprinting() returns true.
                        --       IsTacticalSprinting() is a public boolean method read by GunController.
                        --       AR15 set: no TacticalSprint IDs — tactical sprint plays TacticalSprintForward1
                        --         only for Unarmed. (AR15 tactical sprint IDs deferred.)
                        --       New constants: TACTICAL_SPRINT_ENABLED, TACTICAL_SPRINT_DOUBLE_TAP_WINDOW,
                        --         TACTICAL_SPRINT_SPEED, TACTICAL_SPRINT_ACCELERATION_TIME,
                        --         TACTICAL_SPRINT_MIN_FORWARD_DOT, TACTICAL_SPRINT_BLOCKS_GUN_USE,
                        --         TACTICAL_SPRINT_STOP_ANIMATION_ENABLED.
                        --
                        --     Stage 2Q (2026-05-21): fix crouch animation contamination.
                        --       stopCrouchTracksExcept(allowedKey: string?): stops all _Crouch-keyed
                        --       animationTracks except allowedKey; clears currentAnimationName if
                        --       it was a stopped crouch track. Defined after clearTacticalSprintStopConnection().
                        --       playCrouchTransition() EnterCrouch Stopped callback (not-moving):
                        --       prefers CrouchIdle directly over holdCrouchBottomPose() — eliminates
                        --       frame-0 flash from track:Play(0) in the hold-pose path.
                        --       clearCrouchBottomHold(): removed AdjustSpeed(SPEED_MULT) before Stop —
                        --       eliminates brief resume of frozen EnterCrouch during fade-out.
                        --       stopCrouchTracksExcept call-sites: Stopped callback (crouchIdleKey2),
                        --       updateMovementAnimation not-moving branch (crouchIdleKey),
                        --       CrouchWalkStart path (startKey), CrouchWalk target path (targetCrouchKey).
                        --     Stage 2Q+ (2026-05-22): crouch blend contamination follow-up.
                        --       Root cause 1 fixed: stopCrouchTracksExcept pattern changed from
                        --       "_Crouch" to "Crouch" — EnterCrouch and ExitCrouch keys (which end
                        --       with "Crouch" after the verb) were silently skipped by the old pattern.
                        --       Root cause 2 fixed: removed "if track.IsPlaying" guard; changed
                        --       Stop(FADE_TIME) to Stop(0) — immediately zeroes any residual weight
                        --       including tracks that are fading-but-stopped (IsPlaying=false).
                        --       Root cause 3 fixed: added stopCrouchTracksExcept(key) in
                        --       playCrouchTransition before track:Play() — the critical missing call
                        --       that prevented fading CrouchIdle/ExitCrouch from bleeding through.
                        --       Additional: stopCrouchTracksExcept(fwdKey/aliasKey) added in
                        --       EnterCrouch Stopped moving branch; stopCrouchTracksExcept(nil)
                        --       added in phase exit handler. Total call sites: 8 (4 from 2Q, 4 new).
                        --
                        --     Crouch direct-blend / EnterCrouch disable (Stage 2Q-D — 2026-05-23):
                        --       EnterCrouch one-shot disabled by default (CROUCH_USE_ENTER_TRANSITION_ANIMATION = false).
                        --       Asset had bad intermediate frames (forward-bend artifact visible on frame 0).
                        --       Asset is still loaded into animationTracks — simply never played by default.
                        --       Direct-blend path (playCrouchTransition, entering=true):
                        --         crouchTransitionPlaying stays false — Heartbeat immediately maintains the pose.
                        --         If moving: wasMovingWhileCrouching=true (skips CrouchWalkStart on next Heartbeat).
                        --           customMouseLocked ON + Unarmed set → directional CrouchWalk* (8-dir selection).
                        --           Otherwise → CrouchWalkForward or CrouchWalk alias fallback.
                        --           Fade: CROUCH_DIRECT_BLEND_MOVING_FADE_TIME = 0.10s.
                        --         If not moving: → CrouchIdle (or holdCrouchBottomPose() if track absent).
                        --           Fade: CROUCH_DIRECT_BLEND_FADE_TIME = 0.12s.
                        --         stopCrouchTracksExcept(nil) called before Play to zero residual weights.
                        --         Exits early with return; ExitCrouch path (entering=false) is unchanged.
                        --       CrouchWalkStart gated behind CROUCH_USE_CROUCH_WALK_START_ANIMATION = false.
                        --         When false, updateMovementAnimation falls through immediately to directional selection.
                        --         Forward-lunge artifact on first crouched step eliminated.
                        --         CrouchWalkStart track still loads; never selected unless flag set true.
                        --       No HipHeight, CameraOffset, FOV, camera.CFrame, or sprint/landing changes.
                        --       No new animation IDs. No new remotes.
                        --       New constants: CROUCH_USE_ENTER_TRANSITION_ANIMATION = false,
                        --         CROUCH_DIRECT_BLEND_FADE_TIME = 0.12, CROUCH_DIRECT_BLEND_MOVING_FADE_TIME = 0.10,
                        --         CROUCH_USE_CROUCH_WALK_START_ANIMATION = false.
                        --       Files changed: src/shared/Constants.lua, src/client/MovementController.lua.
                        --       MCP unavailable — needs Studio verification.
                        --
                        --     Zero-gap crouch-exit transitions (Stage 2S — 2026-05-23):
                        --       Eliminates the brief default Roblox neutral pose that appeared between
                        --       crouch release and walk/run/idle resumption. Root cause: playCrouchTransition
                        --       hard-stopped crouch tracks and gated Heartbeat behind crouchTransitionPlaying,
                        --       leaving ≥1 frame where all track weights were zero.
                        --
                        --       Two new pure-read helpers:
                        --         getDesiredStandingLocomotionKey(): mirrors updateMovementAnimation's
                        --           standing/sprint walk selection logic; returns the full track key
                        --           (e.g. "Unarmed_WalkForward") without playing anything.
                        --         resumeStandingLocomotionAfterCrouch(fadeTime): fades all crouch tracks
                        --           out with fadeTime AND starts the standing track in with the same
                        --           fadeTime, so combined weight never reaches zero → no pose flash.
                        --
                        --       crouchEndConn (C release) updated:
                        --         CROUCH_ZERO_GAP_TRANSITIONS_ENABLED = true (master switch).
                        --         Moving and CROUCH_USE_EXIT_TRANSITION_WHILE_MOVING = false (default):
                        --           Skip ExitCrouch; call resumeStandingLocomotionAfterCrouch
                        --           (CROUCH_EXIT_DIRECT_BLEND_FADE_TIME = 0.10s) immediately.
                        --           wasMovingWhileCrouching reset to false; CrouchWalkStart cleared.
                        --         Not moving (or CROUCH_USE_EXIT_TRANSITION_WHILE_MOVING = true):
                        --           Play ExitCrouch (one-shot); in Stopped callback, if
                        --           CROUCH_EXIT_RESUME_LOCOMOTION_IMMEDIATELY = true, immediately call
                        --           resumeStandingLocomotionAfterCrouch (CROUCH_EXIT_IDLE_BLEND_FADE_TIME = 0.12s).
                        --           No more Heartbeat gap after ExitCrouch finishes.
                        --         No ExitCrouch track: falls directly to resumeStandingLocomotionAfterCrouch.
                        --         Legacy path (CROUCH_ZERO_GAP_TRANSITIONS_ENABLED = false):
                        --           original playCrouchTransition(false) call preserved unchanged.
                        --
                        --       No HipHeight, CameraOffset, FOV, camera.CFrame, sprint, landing, or
                        --       server changes. No new animation IDs. No new remotes.
                        --       New constants: CROUCH_ZERO_GAP_TRANSITIONS_ENABLED = true,
                        --         CROUCH_USE_EXIT_TRANSITION_WHILE_MOVING = false,
                        --         CROUCH_EXIT_DIRECT_BLEND_FADE_TIME = 0.10,
                        --         CROUCH_EXIT_IDLE_BLEND_FADE_TIME = 0.12,
                        --         CROUCH_EXIT_RESUME_LOCOMOTION_IMMEDIATELY = true.
                        --       Files changed: src/shared/Constants.lua, src/client/MovementController.lua.
                        --       MCP Studio verified (2026-05-23): module loaded clean, all 9 constants
                        --         live, all 13 source patterns confirmed, no Output errors in play mode.
                        --         C key cannot reach InputBegan via MCP — full visual test requires
                        --         manual Studio playtest.
                        --
                        --     Sprint directional body-facing (Stage 3D — 2026-05-23):
                        --       Stage 3D introduced getCameraRelativeMoveDirection() and
                        --       faceCharacterTowardsDirection() helpers to rotate the character body
                        --       toward MoveDirection during sprint + mouse lock. Stage 3E disabled this
                        --       path (AutoRotate=true caused camera jerk). Stage 3G re-enables it with
                        --       smoothing — see Stage 3G below.
                        --
                        --       Stage 3D helpers (now called by Stage 3G, not dead code):
                        --         getCameraRelativeMoveDirection(): reads movementState.moveVector
                        --           (Humanoid.MoveDirection, already camera-relative in Roblox);
                        --           flattens to XZ; returns nil if below
                        --           SPRINT_DIRECTIONAL_BODY_FACING_MIN_MOVE_MAGNITUDE.
                        --         faceCharacterTowardsDirection(direction): CFrame.lookAt yaw-only write;
                        --           sets AutoRotate = false; optional LERP smoothing via
                        --           SPRINT_DIRECTIONAL_BODY_FACING_SMOOTHING_ENABLED / LERP_ALPHA.
                        --
                        --       Sprint animation selection (getSprintAnimationName — simplified Stage 3J):
                        --         All directions (Forward, Left, Right, Backward, diagonals):
                        --           → RunForward (or RunForwardTest if toggle enabled). Always.
                        --         Stage 3D/2R directional RunForwardLeft/Right branching removed in Stage 3J.
                        --         Body rotation (Stage 3G, MoveDirection, lerp) handles directional visual.
                        --
                        --       New state: lastSprintFacingMode (module-level, cleared on respawn/destroy).
                        --       New constants (Stage 3D, active via Stage 3G):
                        --         SPRINT_FACE_MOVEMENT_DIRECTION_WHILE_MOUSE_LOCKED,
                        --         SPRINT_DIRECTIONAL_BODY_FACING_ENABLED,
                        --         SPRINT_DIRECTIONAL_BODY_FACING_MIN_MOVE_MAGNITUDE,
                        --         SPRINT_DIRECTIONAL_BODY_FACING_DEBUG,
                        --         SPRINT_DIRECTIONAL_BODY_FACING_SMOOTHING_ENABLED = true (Stage 3G),
                        --         SPRINT_DIRECTIONAL_BODY_FACING_LERP_ALPHA = 0.18 (Stage 3G).
                        --
                        --     Natural AutoRotate sprint rotation (Stage 3E — 2026-05-23; DISABLED 2026-05-25):
                        --       Original intent: sets Humanoid.AutoRotate = true during sprint + mouse lock
                        --         so Roblox engine rotates character naturally toward movement direction.
                        --       DISABLED: AutoRotate=true caused camera jerk — the camera is pinned to
                        --         HumanoidRootPart yaw in mouse lock, so every engine body rotation snapped
                        --         the camera with it. SPRINT_USE_NATURAL_AUTOROTATE_WHILE_MOUSE_LOCKED = false
                        --         (2026-05-25). shouldUseNaturalSprintAutoRotate() now always returns false.
                        --       Stage 3E block and shouldUseNaturalSprintAutoRotate() helper are retained as
                        --         dead code (rollback path if Stage 3G is ever disabled).
                        --
                        --     Smooth sprint body-facing toward MoveDirection (Stage 3G — 2026-05-25):
                        --       New block in applyCharacterFacing() after Stage 3E exit block, before
                        --       camera-yaw CFrame write. Active when SPRINT_SMOOTH_BODY_FACING_ENABLED=true
                        --       and customMouseLocked and isSprinting and not isTacticalSprinting and
                        --       not isCrouching and not isSprintStopPlaying and not isLandingMovementLocked.
                        --       When active:
                        --         getCameraRelativeMoveDirection() → if moveDir (magnitude >= 0.1):
                        --           faceCharacterTowardsDirection(moveDir) → return.
                        --         If moveDir nil (below threshold): fall through to camera-yaw write.
                        --       AutoRotate stays false throughout — only a direct CFrame write, no
                        --         Roblox physics rotation → no camera jerk.
                        --       SPRINT_DIRECTIONAL_BODY_FACING_SMOOTHING_ENABLED = true,
                        --         SPRINT_DIRECTIONAL_BODY_FACING_LERP_ALPHA = 0.18:
                        --         faceCharacterTowardsDirection() lerps toward target each Heartbeat.
                        --         At 60Hz + alpha=0.18, body tracks direction changes over ~3–4 frames.
                        --       Walking, idle, crouching, tactical sprint, sprint-stop, landing: continue
                        --         on camera-yaw CFrame path (Stage 3G block guards exclude these).
                        --       No camera.CFrame writes. No HipHeight/CameraOffset/FOV changes.
                        --       No new animation IDs. No new remotes. No server changes.
                        --       New constant: SPRINT_SMOOTH_BODY_FACING_ENABLED = true.
                        --       MCP unavailable — Studio verification was not performed.
                        --       Needs manual playtest.
                        --
                        --     Zero-gap landing exit (Stage 3F — 2026-05-25):
                        --       Eliminates the T-pose / blank-pose flash between a landing one-shot
                        --       finishing and locomotion resuming. Root cause: landingConn Stopped
                        --       callback cleared isLandingPlaying (releasing the Heartbeat gate) but
                        --       did not start the next animation — the gap between callback and next
                        --       Heartbeat tick (~16ms) had all track weights at zero.
                        --       Fix: call playMovementAnimation(getDesiredStandingLocomotionKey())
                        --         directly from the Stopped callback, before the next Heartbeat.
                        --         Guard: LANDING_EXIT_RESUME_LOCOMOTION_IMMEDIATELY = true (master
                        --         switch) and not isLandingPlaying (prevents override if a second
                        --         landing started while this callback was queued).
                        --       getDesiredStandingLocomotionKey() moved to just before
                        --         playLandingAnimation() (from Stage 2S section) so the Stopped
                        --         callback can call it without a forward-reference.
                        --       No new animation IDs. No new remotes. No server changes.
                        --       New constant: LANDING_EXIT_RESUME_LOCOMOTION_IMMEDIATELY = true.
                        --       MCP Studio verified 2026-05-25: LandingHeavy (w=0.61) and Idle
                        --         (w=0.78) overlap in same Heartbeat — no zero-weight gap frame.
                        --
                        --     Sprint camera offset override (Stage 3H — 2026-05-25):
                        --       While sprinting (normal or tactical) + mouse lock: Humanoid.CameraOffset
                        --         is set to Vector3.zero — camera centers directly behind the character;
                        --         the right-shoulder offset (1.75, 0, 0) is removed.
                        --       When sprint ends: CameraOffset restored to CUSTOM_MOUSE_LOCK_CAMERA_OFFSET
                        --         on the next Heartbeat (≤16ms).
                        --       Walking, idle, crouching, sprint-stop, landing: keep the normal offset.
                        --       Mouse lock off: restoreNormalThirdPersonCamera() still applies
                        --         CUSTOM_MOUSE_LOCK_RESTORE_CAMERA_OFFSET (Vector3.zero) as before.
                        --       updateSprintCameraOffset() helper: guarded by ~= so no redundant writes.
                        --       Called from Heartbeat after updateSprintFov().
                        --       No camera.CFrame writes. No HipHeight/FOV changes. No new animation IDs.
                        --       New constant: SPRINT_DISABLES_CAMERA_OFFSET = true.
                        --       Needs manual Studio playtest (Rojo sync pending at commit time).
                        --
                        --     Backpedal turn-around in shift lock (Stage 3L — 2026-05-26):
                        --       New block in applyCharacterFacing() after Stage 3G, before camera-yaw write.
                        --       Active when BACKPEDAL_TURN_ENABLED=true and customMouseLocked and
                        --         directionName ∈ {Backward, BackwardLeft, BackwardRight} and not isSprinting
                        --         and not isCrouching and not isTacticalSprinting and not isSprintStopPlaying
                        --         and not isLandingMovementLocked.
                        --       getCameraRelativeMoveDirection() → if moveDir (magnitude >= 0.1):
                        --         faceCharacterTowardsDirection(moveDir, BACKPEDAL_TURN_LERP_ALPHA) → return.
                        --       Prevents the "stare-forward while backpedaling" look — body sweeps to face
                        --         where the player is actually going.
                        --       BACKPEDAL_TURN_LERP_ALPHA = 0.25: faster than sprint alpha (0.18) so the
                        --         180° pivot completes in ~8–10 frames at 60 fps (≈130–170 ms).
                        --       faceCharacterTowardsDirection gains optional alphaOverride: number? param.
                        --         Sprint callers pass nil (unchanged, still uses SPRINT_...LERP_ALPHA).
                        --       When backward input is released: directionName leaves Backward* set,
                        --         block does not run, camera-yaw write resumes next Heartbeat.
                        --       No camera.CFrame writes. No HipHeight/FOV changes. No new animation IDs.
                        --       New constants: BACKPEDAL_TURN_ENABLED = true, BACKPEDAL_TURN_LERP_ALPHA = 0.25.
                        --       Needs manual Studio playtest — MCP unavailable at commit time.
                        --
                        --     RunForward always — disable RunForwardLeft/Right (Stage 3J — 2026-05-25):
                        --       getSprintAnimationName() simplified: all directional branching removed.
                        --         All sprint directions → getRunForwardSuffix(animSetName) (RunForward or
                        --         RunForwardTest). The ForwardLeft→RunForwardLeft, ForwardRight→RunForwardRight,
                        --         BackwardLeft/Right→RunForwardLeft/Right paths from Stages 2R/3D are gone.
                        --       Stage 3G body rotation (raw MoveDirection, lerp alpha=0.18) provides all
                        --         directional visual information — no per-direction animation switching needed.
                        --       Stage 3G block in applyCharacterFacing() simplified: ForwardLeft/Right
                        --         fixed-angle rotation path (Stage 3I, SPRINT_DIAGONAL_BODY_ROTATION_DEGREES)
                        --         removed. All sprint directions use getCameraRelativeMoveDirection() →
                        --         faceCharacterTowardsDirection() uniformly.
                        --       SPRINT_DIAGONAL_BODY_ROTATION_DEGREES = 20: retained in Constants.lua for
                        --         reference but marked UNUSED — never read at runtime since Stage 3J.
                        --       RunForwardLeft and RunForwardRight tracks still loaded in animationTracks
                        --         but never selected by updateMovementAnimation() or getSprintAnimationName().
                        --       No new animation IDs. No new constants. No camera.CFrame writes.
                        --       Needs manual Studio playtest (Rojo sync pending at commit time).
                        --
                        --     Sprint FOV stretch (Stage 3A — 2026-05-21):
                        --       TweenService smoothly tweens workspace.CurrentCamera.FieldOfView.
                        --       Normal sprint (LeftShift + moving + not crouching) → SPRINT_CAMERA_FOV (78).
                        --       Tactical sprint active → TACTICAL_SPRINT_CAMERA_FOV (84).
                        --       All other states → DEFAULT_CAMERA_FOV (70).
                        --       tweenCameraFov(target, duration): cancels prior tween, starts new one. Never touches camera.CFrame.
                        --       updateSprintFov(): dedup guard (targetFov) prevents per-frame tween restarts.
                        --         Called from: stopTacticalSprint(), sprint InputBegan, sprint InputEnded,
                        --         crouch InputBegan, phase-exit handler, Heartbeat loop.
                        --       FieldOfView restored (tweened to 70) on sprint end, tactical sprint end, phase exit (non-ACTIVE).
                        --       FieldOfView reset (direct set, no tween) on respawn / CharacterAdded.
                        --       FieldOfView tween cancelled + set to 70 in destroy().
                        --       Master switch: SPRINT_FOV_ENABLED (default true). When false, nothing is written.
                        --       New constants: SPRINT_FOV_ENABLED, DEFAULT_CAMERA_FOV, SPRINT_CAMERA_FOV,
                        --         TACTICAL_SPRINT_CAMERA_FOV, SPRINT_FOV_TWEEN_TIME (0.18s), SPRINT_FOV_RESTORE_TIME (0.22s).
                        --       No fall damage. No stamina. No slide, vault, or prone. No camera.CFrame writes.
                        --
                        --     Landing animation classification (Stage 3A — 2026-05-21):
                        --       Three tiers replace Stage 2O's single LandingMedium:
                        --         LandingLight  — normal jumps (no sprint) + small pure drops (≤ 8 studs).
                        --         LandingMedium — sprint jumps + medium pure drops (8–18 studs).
                        --         LandingHeavy  — any drop ≥ 18 studs regardless of jump context.
                        --       wasJumpingThisAirborne: true when airborne phase started with a Jumping state (not walk-off).
                        --       jumpedWhileSprinting: true if sprinting at jump time.
                        --       airborneStartY: HumanoidRootPart.Y captured on Jumping; used for drop-distance calc.
                        --       getLandingAnimationName(dropDist, airTime, wasJump, sprintJump): returns tier string or nil.
                        --       playLandingAnimation(name): uses MOVEMENT_LANDING_ANIMATION_FADE_TIME (0.08) not 0.15.
                        --       Pure-drop guard: MOVEMENT_LANDING_ANIMATION_MIN_AIR_TIME (0.25s) — tiny hops play nothing.
                        --       LandingLight and LandingHeavy: Looped=false (one-shots), same as LandingMedium.
                        --       onHumanoidStateChanged rewritten: Jumping state tracked; Freefall captures airborneStartY
                        --         if wasJumpingThisAirborne=false (walk-off); Landed calls getLandingAnimationName.
                        --       New animation IDs: Unarmed.LandingLight (rbxassetid://135438895968665),
                        --         Unarmed.LandingHeavy (rbxassetid://72796290236543).
                        --       New speed multiplier constants: MOVEMENT_LANDING_LIGHT_SPEED_MULTIPLIER (1.15),
                        --         MOVEMENT_LANDING_MEDIUM_SPEED_MULTIPLIER (1.0), MOVEMENT_LANDING_HEAVY_SPEED_MULTIPLIER (0.9).
                        --
                        --     Landing movement lock + sprint-jump momentum carry (Stage 3B — 2026-05-21):
                        --       LandingLight: no lock. Player retains full movement input on light landings.
                        --       LandingMedium: WalkSpeed set to 0 while animation plays.
                        --         Sprint-jump path: lock lasts SPRINT_JUMP_LANDING_MOMENTUM_DURATION (0.22s);
                        --           a LinearVelocity carries horizontal momentum at SPRINT_JUMP_LANDING_MOMENTUM_SPEED (18 studs/s).
                        --           This is NOT a slide system — no slide state, no slide input, no slide animation.
                        --           LinearVelocity + Attachment parented to HumanoidRootPart; destroyed after 0.22s.
                        --         Non-sprint-jump path: lock lasts LANDING_MEDIUM_LOCK_FALLBACK_DURATION (0.35s).
                        --       LandingHeavy: WalkSpeed set to 0 for LANDING_HEAVY_LOCK_FALLBACK_DURATION (0.65s).
                        --       Early unlock: animation Stopped callback releases the lock when it fires before
                        --         the fallback timer, unless sprint-jump momentum is still active.
                        --       applySpeed() override: if isLandingMovementLocked == true, sets WalkSpeed=0 and returns
                        --         early, before tactical sprint ramp, before all other speed logic.
                        --       Token-based stale-unlock prevention: landingLockToken incremented on every
                        --         clearLandingMovementLock(); each task.delay captures token at dispatch, no-ops if changed.
                        --       captureJumpMomentumDirection(): called at Jumping state entry (not Freefall) because
                        --         AssemblyLinearVelocity/MoveDirection still reflect sprint at that point.
                        --         Priority: AssemblyLinearVelocity → MoveDirection → CFrame.LookVector.
                        --       Phase exit (non-ACTIVE), respawn (loadMovementAnimations), and destroy() all
                        --         call clearLandingMovementLock() — WalkSpeed is never left stuck at 0.
                        --       New state: isLandingMovementLocked, landingLockToken, landingMomentumActive,
                        --         landingMomentumAttachment, landingMomentumVelocity, sprintJumpMomentumDirection.
                        --       New helpers (inserted before loadMovementAnimations to satisfy --!strict forward-ref):
                        --         getFlatVector, captureJumpMomentumDirection, clearLandingMomentum,
                        --         clearLandingMovementLock, startLandingMovementLock, startSprintJumpLandingMomentum.
                        --       New constants: LANDING_MOVEMENT_LOCK_ENABLED, LANDING_MEDIUM_LOCKS_MOVEMENT,
                        --         LANDING_HEAVY_LOCKS_MOVEMENT, LANDING_LIGHT_LOCKS_MOVEMENT,
                        --         LANDING_MEDIUM_LOCK_FALLBACK_DURATION (0.35s), LANDING_HEAVY_LOCK_FALLBACK_DURATION (0.65s),
                        --         SPRINT_JUMP_LANDING_MOMENTUM_ENABLED, SPRINT_JUMP_LANDING_MOMENTUM_DURATION (0.22s),
                        --         SPRINT_JUMP_LANDING_MOMENTUM_SPEED (18), SPRINT_JUMP_LANDING_MOMENTUM_MAX_FORCE (60000).
                        --       Studio verified (MCP): LandingLight at 6 studs — no lock; LandingMedium at 14 studs
                        --         — locked ~0.37s; LandingHeavy at 22 studs — locked exactly 0.65s.
                        --
                        --     Sprint stop polish (Stage 3C — 2026-05-22):
                        --       Normal sprint stop (Shift released after sprinting) is now gated, movement-locked,
                        --         and momentum-carried. This is NOT the slide system — no slide state, no slide
                        --         input, no slide animation. The same TacticalSprintStop animation is reused.
                        --       Duration gate: SprintStop only plays when sprintDuration ≥ SPRINT_STOP_MIN_SPRINT_DURATION (0.75s).
                        --         Short Shift taps (< 0.75s) exit sprint normally without the stop animation.
                        --       Movement lock: WalkSpeed=0 while SprintStop animation plays
                        --         (SPRINT_STOP_LOCKS_MOVEMENT = true). Fallback timer of
                        --         SPRINT_STOP_LOCK_FALLBACK_DURATION (0.38s) releases lock if Stopped callback
                        --         never fires (e.g. animation not loaded).
                        --       Momentum carry: a LinearVelocity pushes the player forward at
                        --         SPRINT_STOP_MOMENTUM_SPEED (16 studs/s) for SPRINT_STOP_MOMENTUM_DURATION (0.24s).
                        --         Direction is taken from lastSprintMomentumDirection, updated each Heartbeat from
                        --         AssemblyLinearVelocity → MoveDirection → CFrame.LookVector fallback chain.
                        --         Only tracked when flatVel.Magnitude ≥ SPRINT_STOP_MIN_HORIZONTAL_SPEED (8).
                        --         LinearVelocity + Attachment parented to HumanoidRootPart; destroyed after 0.24s.
                        --       Token-based stale-unlock: sprintStopLockToken mirrors landingLockToken pattern.
                        --       Interaction — tactical sprint: if isTacticalSprinting when Shift released,
                        --         stopTacticalSprint() runs and returns early; normal SprintStop does NOT also play.
                        --       Interaction — crouch: pressing C while sprinting clears sprintStartTime and cancels
                        --         any in-flight SprintStop via clearSprintStopLock().
                        --       applySpeed() priority: landing lock → sprint-stop lock → tactical sprint ramp → normal.
                        --       updateMovementAnimation() gate: if isSprintStopPlaying then return end (after
                        --         tacticalSprintStopConn gate).
                        --       New state variables: sprintStartTime, lastSprintMomentumDirection,
                        --         isSprintStopPlaying, sprintStopLockToken, sprintStopMomentumAttachment,
                        --         sprintStopMomentumVelocity.
                        --       New helpers: shouldPlaySprintStop, clearSprintStopMomentum, clearSprintStopLock,
                        --         startSprintStopMomentum, playSprintStopWithLock.
                        --       New constants: SPRINT_STOP_ENABLED, SPRINT_STOP_MIN_SPRINT_DURATION (0.75),
                        --         SPRINT_STOP_LOCKS_MOVEMENT, SPRINT_STOP_LOCK_FALLBACK_DURATION (0.38),
                        --         SPRINT_STOP_MOMENTUM_ENABLED, SPRINT_STOP_MOMENTUM_DURATION (0.24),
                        --         SPRINT_STOP_MOMENTUM_SPEED (16), SPRINT_STOP_MOMENTUM_MAX_FORCE (60000),
                        --         SPRINT_STOP_MIN_HORIZONTAL_SPEED (8).
                        --       Studio verification: not yet confirmed via MCP (Rojo Connect dialog required
                        --         manual click; rojo build passes, all grep checks passed on disk).
                        --
                        --     Not in Stage 2A/2C/2D/2F/2G/2H/2I/2J/2N/2O/2P/2Q/2R/3A/3B/3C: AR15 Falling/Landing IDs (deferred),
                        --       AR15 CrouchWalk/CrouchIdle IDs (deferred), AR15 tactical sprint IDs (deferred),
                        --       TacticalSprintForward2 variation system (deferred),
                        --       lower/upper-body split, reload/fire/ADS weapon animations.
                        --
                        --   Stage 2K — third-person camera zoom limits + mouse-lock camera (2026-05-20):
                        --     Normal third-person zoom: CameraMin=4, CameraMax=14 (set in Start() and on CharacterAdded).
                        --     Custom mouse-lock ON: CameraMin=CameraMax=8 (pinned); CameraOffset=Vector3.new(1.75,0,0).
                        --     Custom mouse-lock OFF: CameraMin=4, CameraMax=14; CameraOffset=Vector3.zero.
                        --     destroy() restores CameraMin=4, CameraMax=14 and CameraOffset=zero.
                        --     Camera zoom uses Players.LocalPlayer.CameraMinZoomDistance/CameraMaxZoomDistance only.
                        --     Does NOT set CameraType to Scriptable. Does NOT write camera.CFrame or FieldOfView.
                        --     Toggle key changed: LeftAlt → LeftControl (keeps LeftAlt free; LeftShift=sprint still).
                        --     CameraOffset fallback: if module-level humanoid is nil, looks up from
                        --       Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid") directly.
                        --     New constants: THIRD_PERSON_MIN_ZOOM_DISTANCE=4, THIRD_PERSON_MAX_ZOOM_DISTANCE=14,
                        --       CUSTOM_MOUSE_LOCK_CAMERA_DISTANCE=8, CUSTOM_MOUSE_LOCK_CAMERA_OFFSET,
                        --       CUSTOM_MOUSE_LOCK_RESTORE_CAMERA_OFFSET, CUSTOM_MOUSE_LOCK_APPLIES_CAMERA_DISTANCE,
                        --       CUSTOM_MOUSE_LOCK_APPLIES_CAMERA_OFFSET.
                        --
                        --   Exposes: GetMovementState() → table; GetMoveState() → string (GunController
                        --   compat); IsADSBlocked() → bool; GetViewmodelAddCFrame() → identity;
                        --   SetEquippedWeaponName(name: string?) → switches animation set (presentation only);
                        --   GetEquippedWeaponName() → string? (nil = Unarmed set active);
                        --   SetCustomMouseLocked(bool) → toggles custom mouse lock; writes MouseBehavior,
                        --     CameraMinZoomDistance, CameraMaxZoomDistance, and CameraOffset (Stage 2K);
                        --   IsCustomMouseLocked() → bool (true = LeftControl mouse lock is active);
                        --   IsTacticalSprinting() → bool (true while double-tap tactical sprint is active) (Stage 2P);
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
             --   Custom mouse-lock constants (Stage 2D — 2026-05-19; updated Stage 2K — 2026-05-20):
             --     CUSTOM_MOUSE_LOCK_ENABLED = true — enables LeftControl custom mouse-lock toggle.
             --     CUSTOM_MOUSE_LOCK_TOGGLE_KEY = Enum.KeyCode.LeftControl — toggle key (was LeftAlt in Stage 2D).
             --     CUSTOM_MOUSE_LOCK_STRAFE_ANIMS_ONLY = true — when true, strafe gating reads
             --       customMouseLocked (not UserInputService.MouseBehavior / Roblox ShiftLock).
             --     CUSTOM_MOUSE_LOCK_DEBUG = true — logs mouse-lock toggle events to Output.
             --   Custom mouse-lock bugfix constants (Stage 2D bugfix — 2026-05-19):
             --     DISABLE_ROBLOX_DEFAULT_MOUSE_LOCK = true — gates disableRobloxDefaultMouseLock()
             --       which sets LocalPlayer.DevEnableMouseLock = false on Start and CharacterAdded.
             --     CUSTOM_MOUSE_LOCK_REAPPLY_EVERY_FRAME = true — Heartbeat re-writes MouseBehavior
             --       = LockCenter when it has drifted away from LockCenter (conditional since
             --       Stage 3E-fix-2 2026-05-25; was unconditional — caused camera jerk).
             --     CUSTOM_MOUSE_LOCK_INPUT_PRIORITY = 3000 — ContextActionService priority for LeftAlt
             --       bind; 3000 > CoreScript default 2000 ensures immediate response.
             --   Movement animation playback speed multipliers (updated Stage 2H 2026-05-20):
             --     MOVEMENT_WALK_ANIMATION_SPEED_MULTIPLIER              = 1.3  (WalkForward/Backward/diagonals)
             --     MOVEMENT_STRAFE_ANIMATION_SPEED_MULTIPLIER            = 1.4  (WalkLeft, WalkRight)
             --     MOVEMENT_RUN_ANIMATION_SPEED_MULTIPLIER               = 1.15 (RunForward/RunForwardTest share this multiplier; RunForwardLeft/Right deferred)
             --     MOVEMENT_RUN_FORWARD_USE_TEST_ANIMATION               = false (toggle: false = RunForward, true = RunForwardTest — Unarmed only)
             --     MOVEMENT_IDLE_ANIMATION_SPEED_MULTIPLIER              = 0.75 (Idle — Stage 2H)
             --     MOVEMENT_CROUCH_TRANSITION_ANIMATION_SPEED_MULTIPLIER = 0.9  (EnterCrouch, ExitCrouch — Stage 2H)
             --     MOVEMENT_CROUCH_WALK_ANIMATION_SPEED_MULTIPLIER       = 1.0  (CrouchWalk* directional — Stage 2J)
             --   Third-person camera zoom + mouse-lock camera constants (Stage 2K — 2026-05-20):
             --     THIRD_PERSON_MIN_ZOOM_DISTANCE = 4  — normal min zoom (studs); set on Start/CharacterAdded.
             --     THIRD_PERSON_MAX_ZOOM_DISTANCE = 14 — normal max zoom (studs); set on Start/CharacterAdded.
             --     CUSTOM_MOUSE_LOCK_CAMERA_DISTANCE = 8       — pinned zoom distance while mouse lock is ON.
             --     CUSTOM_MOUSE_LOCK_CAMERA_OFFSET = Vector3.new(1.75, 0, 0) — right-shoulder lateral offset.
             --     CUSTOM_MOUSE_LOCK_RESTORE_CAMERA_OFFSET = Vector3.zero  — offset applied when lock is OFF.
             --     CUSTOM_MOUSE_LOCK_APPLIES_CAMERA_DISTANCE = true — gates CameraMin/Max writes in applyCustomMouseLockCamera.
             --     CUSTOM_MOUSE_LOCK_APPLIES_CAMERA_OFFSET = true  — gates CameraOffset write in applyCustomMouseLockCamera.
             --   Crouch hold constants (Stage 2I — 2026-05-20):
             --     CROUCH_HOLD_KEY = Enum.KeyCode.C — key held to enter/stay crouched; release exits crouch.
             --     CROUCH_HOLD_BOTTOM_POSE_ENABLED = true — enables EnterCrouch clip frozen at final frame
             --       (AdjustSpeed(0) + TimePosition near end) after the one-shot finishes.
             --     CROUCH_TRANSITION_MIN_HOLD_TIME = 0.05 — seconds from clip end; guards against TimePosition
             --       snapping to frame 0 at exact Length on some Roblox versions.
             --     CROUCH_BOTTOM_HOLD_TIME_POSITION_FALLBACK = 0.98 — used when EnterCrouch.Length == 0.
             --   Crouch direct-blend constants (Stage 2Q-D — 2026-05-23):
             --     (see Stage 2Q-D entry in MovementController block above)
             --   Zero-gap crouch-exit constants (Stage 2S — 2026-05-23):
             --     CROUCH_ZERO_GAP_TRANSITIONS_ENABLED = true — master switch; when false, original
             --       ExitCrouch → Heartbeat path is used (may show default-pose gap on release).
             --     CROUCH_USE_EXIT_TRANSITION_WHILE_MOVING = false — when false (default), ExitCrouch
             --       is skipped while the player is moving; direct blend into walk/run instead.
             --       Set true to play ExitCrouch even while moving (re-enables the gap).
             --     CROUCH_EXIT_DIRECT_BLEND_FADE_TIME = 0.10 — crossfade duration (s) for direct
             --       blend from CrouchIdle/CrouchWalk into walk/run (moving path). Both the crouch
             --       fade-out and standing fade-in use this value so total weight never hits zero.
             --     CROUCH_EXIT_IDLE_BLEND_FADE_TIME = 0.12 — crossfade duration (s) for direct
             --       blend into Idle (not-moving path, or ExitCrouch Stopped → Idle).
             --     CROUCH_EXIT_RESUME_LOCOMOTION_IMMEDIATELY = true — when true, standing locomotion
             --       starts in the ExitCrouch Stopped callback rather than waiting for next Heartbeat.
             --       Eliminates the ≥1 frame blank pose after ExitCrouch finishes.
             --   Crouch direct-blend constants (Stage 2Q-D — 2026-05-23):
             --     CROUCH_USE_ENTER_TRANSITION_ANIMATION = false — when false, EnterCrouch one-shot is skipped
             --       on crouch press; direct crossfade into CrouchIdle or CrouchWalk* instead.
             --       Set to true to re-enable the original EnterCrouch one-shot (e.g. if asset is replaced).
             --     CROUCH_DIRECT_BLEND_FADE_TIME = 0.12 — crossfade time (seconds) into CrouchIdle
             --       when the player is not moving at the moment of crouch press.
             --     CROUCH_DIRECT_BLEND_MOVING_FADE_TIME = 0.10 — crossfade time (seconds) into
             --       CrouchWalk* when the player is moving at the moment of crouch press.
             --     CROUCH_USE_CROUCH_WALK_START_ANIMATION = false — when false, CrouchWalkStart one-shot
             --       is never played; updateMovementAnimation falls through to directional selection
             --       immediately on the first crouched step. Set to true to restore original one-shot.
             --   Sprint directional body-facing constants (Stage 3D — 2026-05-23; smoothing enabled Stage 3G):
             --     SPRINT_FACE_MOVEMENT_DIRECTION_WHILE_MOUSE_LOCKED = true — gates the Stage 3D sprint
             --       branch (retained; used by Stage 3G path).
             --     SPRINT_DIRECTIONAL_BODY_FACING_ENABLED = true — master switch for Stage 3D branch.
             --     SPRINT_DIRECTIONAL_BODY_FACING_MIN_MOVE_MAGNITUDE = 0.1 — minimum XZ MoveDirection
             --       magnitude threshold for getCameraRelativeMoveDirection() (Stage 3D/3G helper).
             --     SPRINT_DIRECTIONAL_BODY_FACING_DEBUG = true — logs Stage 3D mode changes.
             --     SPRINT_DIRECTIONAL_BODY_FACING_SMOOTHING_ENABLED = true — Stage 3G: LERP enabled.
             --     SPRINT_DIRECTIONAL_BODY_FACING_LERP_ALPHA = 0.18 — Stage 3G: per-Heartbeat lerp
             --       alpha; ~3–4 frames to track a direction change at 60Hz.
             --   Natural AutoRotate sprint constants (Stage 3E — 2026-05-23; DISABLED 2026-05-25):
             --     SPRINT_USE_NATURAL_AUTOROTATE_WHILE_MOUSE_LOCKED = false — kill switch; false
             --       (2026-05-25 fix) because AutoRotate=true caused camera jerk. Stage 3E code is
             --       retained as dead code for rollback — set true to re-enable AutoRotate sprint.
             --     SPRINT_DISABLE_MANUAL_BODY_FACING_WHILE_MOUSE_LOCKED = true — second kill switch;
             --       both must be true for Stage 3E to activate (currently inactive).
             --     SPRINT_NATURAL_AUTOROTATE_DEBUG = true — logs Stage 3E mode entry/exit once per
             --       transition; gated by lastNaturalSprintAutoRotateActive (no per-frame spam).
             --   Zero-gap landing exit constants (Stage 3F — 2026-05-25):
             --     LANDING_EXIT_RESUME_LOCOMOTION_IMMEDIATELY = true — master switch; when true, the
             --       landing animation Stopped callback immediately crossfades into the correct
             --       locomotion animation (walk/run/idle), eliminating the ≥1 frame blank-pose gap
             --       between landing one-shot end and the next Heartbeat tick. Set false to revert to
             --       the old behaviour (locomotion resumes on the next Heartbeat). Mirrors
             --       CROUCH_EXIT_RESUME_LOCOMOTION_IMMEDIATELY (Stage 2S).
             --   Smooth sprint body-facing constants (Stage 3G — 2026-05-25):
             --     SPRINT_SMOOTH_BODY_FACING_ENABLED = true — master switch for Stage 3G block in
             --       applyCharacterFacing(). When true, sprint + mouse lock rotates character body
             --       smoothly toward MoveDirection via faceCharacterTowardsDirection() lerp. When false,
             --       sprint falls through to camera-yaw write (character always faces camera).
             --   Sprint camera offset override constants (Stage 3H — 2026-05-25):
             --     SPRINT_DISABLES_CAMERA_OFFSET = true — master switch. When true, the Heartbeat
             --       call to updateSprintCameraOffset() sets Humanoid.CameraOffset = Vector3.zero
             --       while sprinting (normal or tactical) in mouse lock, removing the right-shoulder
             --       offset so the camera centers behind the character. Restores to
             --       CUSTOM_MOUSE_LOCK_CAMERA_OFFSET on the next Heartbeat when sprint ends.
             --       Set false to always use CUSTOM_MOUSE_LOCK_CAMERA_OFFSET.
             --   Tactical sprint sensitivity override constants (Stage 3K — 2026-05-26):
             --     TACTICAL_SPRINT_SENSITIVITY_ENABLED = true — master switch. When true,
             --       applyTacticalSprintSensitivity() halves MouseDeltaSensitivity on tactical
             --       sprint entry and restores it on every exit path. Set false for no change.
             --     TACTICAL_SPRINT_SENSITIVITY_MULTIPLIER = 0.5 — fraction of current
             --       UserInputService.MouseDeltaSensitivity applied while tactical sprint is
             --       active. 0.5 = half sensitivity. Tune without code changes.
             --   Fluid crouch transition constants (Stage 3M — 2026-05-26):
             --     CROUCH_DIRECT_BLEND_FADE_TIME = 0.28 — enter-crouch blend (not moving).
             --       Increased from 0.12 for a slower, more physical drop into crouch.
             --     CROUCH_DIRECT_BLEND_MOVING_FADE_TIME = 0.22 — enter-crouch blend (moving).
             --     CROUCH_EXIT_DIRECT_BLEND_FADE_TIME = 0.22 — exit-crouch blend (moving).
             --     CROUCH_EXIT_IDLE_BLEND_FADE_TIME = 0.28 — exit-crouch blend (still).
             --     MOVEMENT_CROUCH_TRANSITION_ANIMATION_SPEED_MULTIPLIER = 0.5 — ExitCrouch
             --       one-shot plays at half speed; slowed from 0.9 for deliberate stand-up feel.
             --     CROUCH_TRANSITION_SPEED_LOCK_ENABLED = true — when true, WalkSpeed is held
             --       at CROUCH_SPEED until resumeStandingLocomotionAfterCrouch() fires. Prevents
             --       the speed snapping to WALK_SPEED the instant C is released while the body
             --       is still blending to standing. Set false to restore instant-speed behaviour.
             --   Instant backward sprint turn constant (Stage 3N — 2026-05-26):
             --     SPRINT_BACKWARD_INSTANT_TURN = true — when true, sprinting in the Backward /
             --       BackwardLeft / BackwardRight direction while shift lock is active snaps the
             --       character body to face the move direction immediately (alpha=1.0, no LERP).
             --       Forward and diagonal-forward sprint use the normal 0.18 LERP unchanged.
             --       Set false to restore the original slow LERP for backward sprint.
             --   Backpedal turn-around constants (Stage 3L — 2026-05-26):
             --     BACKPEDAL_TURN_ENABLED = true — master switch. When true, character body
             --       sweeps to face the backward move direction while walking backward in shift
             --       lock. Set false to revert to original camera-yaw facing during backpedal.
             --     BACKPEDAL_TURN_LERP_ALPHA = 0.25 — per-Heartbeat LERP alpha for the pivot
             --       sweep. Higher than sprint (0.18) for a quicker 180° body turn (~8–10
             --       frames at 60 fps). 1.0 = instant snap. Tune without code changes.
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
