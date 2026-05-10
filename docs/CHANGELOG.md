# CHANGELOG.md

All notable changes to this project, newest first.

Format: `## [version or date] — description`
Under each entry: bullet points for what was added, changed, or removed.

---

## [2026-05-10] — Revert viewmodel to programmatic placeholder while proper model is sourced

**Updated — `src/client/ViewModelController.lua`**
- `init()` rebuilt from scratch: no longer clones from `ReplicatedStorage/ViewModels/SCAR`; all geometry is now created programmatically in code
- Creates a `Model` named `ViewModelPlaceholder` parented to `workspace.CurrentCamera`
- Parts built inside the model: `GunBody` (0.3 × 0.2 × 1.4, dark grey), `Barrel` (0.08 × 0.08 × 0.6, dark grey, 0.7 studs forward from body centre), `LeftArm` (0.4 × 0.4 × 1.2, Light orange, offset left/below), `RightArm` (same, offset right/below)
- All parts: `CanCollide false`, `CanQuery false`, `CastShadow false`, `Anchored false`, `Transparency 1` on creation
- `MuzzleAttachment` added at barrel front tip `(0, 0, −0.3)` in barrel local space
- `BASE_OFFSET` changed to `CFrame.new(0.6, -0.4, -1.5)` (placeholder-appropriate, no model-specific compensation needed)
- `setVisibility` simplified: no longer special-cases `HumanoidRootPart` / `FakeCamera` (placeholder has no such parts)
- Removed all `WaitForChild("ViewModels")` and `WaitForChild("SCAR")` calls — no external asset dependency
- `ReplicatedStorage` import retained (still needed for Modules and Remotes)
- All show/hide, `PivotTo`, camera-lock, `CharacterAdded`, `PlayFireAnimation`, and `GetBarrelTipCFrame` logic unchanged

**Debt evaluation**
- DEBT-021 (model cleanup on re-init): unaffected — `init()` destroy-before-create guard still present; entry remains resolved
- DEBT-027 (WaitForChild blocks forever): **deleted** — WaitForChild no longer used in `init()`; the entry is now moot
- DEBT-028 (BASE_OFFSET hardcoded per model): **deleted** — programmatic placeholder uses a geometry-neutral offset; per-weapon offset concern does not apply until a production model with a non-standard pivot is introduced

---

## [2026-05-10] — Fix camera mode, viewmodel cleanup on respawn, gun position offset

**Updated — `src/client/ViewModelController.lua`**
- `Start()`: applies `Enum.CameraMode.LockFirstPerson` to `Players.LocalPlayer` immediately on init, preventing the camera from reverting to third-person
- `Start()`: connects `localPlayer.CharacterAdded` — on each respawn, calls `self:init()` (destroys old model, clones fresh SCAR from ReplicatedStorage) then re-applies `LockFirstPerson`; this handles `player:LoadCharacter()` calls from TeamService at the start of every PREP
- `setVisibility` and `RenderStepped` closures now read `local m = self.model` per-call instead of capturing `local model` at `Start()` time, so the fresh clone after each respawn is automatically picked up
- `BASE_OFFSET` changed from `CFrame.new(0.6, -0.4, -1.2)` to `CFrame.new(3.2, 0.9, -1.2)` to compensate for the Troy Defense AR model's internal geometry layout (~2.6 studs right and ~1.3 studs down relative to the model pivot)
- Added `local Players = game:GetService("Players")` import (required for LocalPlayer and CharacterAdded)

**Debt evaluation**
- DEBT-007 (multiple RoundStateChanged listeners): unaffected — count unchanged
- DEBT-013 (weapon name hardcoded): unaffected
- DEBT-021 (model cleanup on re-init): unaffected — already resolved; `init()` guard still present
- DEBT-027 (WaitForChild timeout): unaffected — already resolved; timeout still in place
- DEBT-028 (BASE_OFFSET hardcoded per-model): **introduced** — see DEBT-028 entry

---

## [2026-05-07] — Update ViewModelController for Troy Defense AR model structure

**Updated — `src/client/ViewModelController.lua`**
- `setVisibility(show)` in `Start()`: when hiding (show=false), all BaseParts set to Transparency=1 as before; when showing (show=true), all BaseParts set to Transparency=0 **except** parts named `HumanoidRootPart` or `FakeCamera`, which always remain at Transparency=1 — these are the physics anchor and camera reference part, not visual geometry
- `Start()`: added nil guard after `self:init()` — if the model failed to load (DEBT-027 early-return path), `Start()` now returns cleanly instead of casting a nil `self.model` to `Model` and crashing; other controllers continue initializing normally

**Debt evaluation**
- All open entries: unaffected

---

## [2026-05-07] — Fix DEBT-027: add WaitForChild timeout for SCAR model

**Updated — `src/client/ViewModelController.lua`**
- `init()`: replaced bare `WaitForChild("ViewModels")` with `WaitForChild("ViewModels", 10)` + nil check + `Logger.warn` + early return
- `init()`: replaced bare `WaitForChild("SCAR")` with `WaitForChild("SCAR", 10)` + nil check + `Logger.warn` + early return
- A missing folder or model now prints an actionable warning in Output and returns cleanly instead of blocking ClientInit forever

**Debt evaluation**
- DEBT-027 (WaitForChild blocks forever): **resolved** — both calls now time out after 10 s with loud warnings; entry marked resolved

---

## [2026-05-07] — Replace block viewmodel with SCAR model using PivotTo

**Model attachment:** `ViewModelController:init()` clones `ReplicatedStorage/ViewModels/SCAR` and parents it to `workspace.CurrentCamera`. `RenderStepped` calls `model:PivotTo(camera.CFrame * CFrame.new(0.6, -0.4, -1.2) * CFrame.new(0, 0, recoilOffset))` every frame, keeping the model locked to the camera. No PrimaryPart is required — `PivotTo` repositions by the model's geometric pivot.

**Updated — `src/client/ViewModelController.lua`**
- Replaced the three hand-built Parts (`gunBody`, `barrel`, `grip`) and `makePart()` helper with a single cloned Model stored as `self.model` (table field, typed `Model?`)
- Added `ViewModelController:init()`: destroys any existing `self.model` (re-init safe), calls `ReplicatedStorage:WaitForChild("ViewModels"):WaitForChild("SCAR")`, clones the model, parents clone to `workspace.CurrentCamera`, hides all `BasePart` descendants via `GetDescendants()` / `IsA("BasePart")` / `Transparency = 1`
- `Start()` calls `self:init()` first, then narrows `self.model` to non-nil `Model`, registers `RoundStateChanged` phase listener and `RenderStepped` loop
- `RenderStepped`: replaced three individual `Part.CFrame` assignments with `model:PivotTo(cam.CFrame * BASE_OFFSET * CFrame.new(0, 0, recoilOffset))`; skipped entirely when `visible == false`
- `setVisibility(show)`: iterates `model:GetDescendants()` / `IsA("BasePart")` to set `Transparency`; called only on phase changes (not per-frame)
- Visibility rule unchanged: shown only during `ACTIVE`, hidden during all other phases
- `PlayFireAnimation()`: sets `recoilOffset = RECOIL_DIST`, then immediately applies `model:PivotTo(model:GetPivot() * CFrame.new(0, 0, recoilOffset))` for a same-frame snap; `RenderStepped` decays `recoilOffset` back to 0 over 0.05 s
- `GetBarrelTipCFrame()`: uses `model:FindFirstChild("MuzzleAttachment", true)` → `CFrame.new(attachment.WorldPosition)`; falls back to `CFrame.new(cam.CFrame.Position + cam.CFrame.LookVector * 1.5)` with `Logger.warn` if attachment is missing
- Removed: `VM_COLOR`, `BARREL_CENTER_OFFSET`, `BARREL_TIP_OFFSET`, `GRIP_OFFSET`, `makePart()`, `local gunBody/barrel/grip`

**Updated — `src/shared/WeaponData.lua`**
- Added `WeaponData["SCAR"] = { damage=30, fireRate=0.1, range=400, magazineSize=20, reserveAmmo=100 }`
- Retained `WeaponData["AssaultRifle"]` as a fallback definition (not the active weapon)

**Updated — `src/server/GunService.server.lua`**
- `DEFAULT_WEAPON` changed from `"AssaultRifle"` to `"SCAR"`

**Updated — `src/client/GunController.lua`**
- `CURRENT_WEAPON` changed from `"AssaultRifle"` to `"SCAR"`

**Debt evaluation**
- DEBT-013 (weapon name hardcoded): **worsened** — WeaponData now has two named entries; mismatch between the two hardcoded strings would silently apply wrong stats (damage 25→30, range 300→400, mag 30→20); entry updated
- DEBT-021 (ViewModelController no cleanup on double-Start): **resolved** — `init()` destroys previous `self.model` before cloning; three-Part orphaning risk eliminated; entry marked resolved
- DEBT-007 (RoundStateChanged fan-out): **unaffected** — still one listener in ViewModelController; count stays at 6
- Added DEBT-027: `WaitForChild("ViewModels")` / `WaitForChild("SCAR")` blocks forever if model is missing from ReplicatedStorage

---

## [2026-05-07] — Fix reload to discard magazine instead of topping off

**Updated — `src/server/GunService.server.lua`**
- `ReloadRequest` handler: replaced top-off logic (`needed = magazineSize - mag; pulled = min(needed, reserve); mag += pulled`) with full-discard logic (`pulled = min(magazineSize, reserve); mag = pulled; reserve -= pulled`)
- Concrete example added as a comment: 15 rounds in magazine, 70 in reserve → 30 in magazine, 40 in reserve; the 15 remaining rounds are permanently discarded
- The full-magazine guard (`mag >= magazineSize → early return`) is unchanged and correct: reloading a full magazine with the new logic would consume reserve rounds for zero gain

**Debt evaluation**
- All open entries: unaffected

---

## [2026-05-07] — Add kill feed UI

**Kill feed data flow:** `DamageService:killPlayer()` → `KillFeed:FireAllClients(killerName, victimName, killerTeam, victimTeam)` → `KillFeedUI:addEntry()` → top-right entry stack, fades after 4 s

**Updated — `src/shared/Constants.lua`**
- Added `KILLFEED_DISPLAY_TIME = 4` — seconds each entry is visible before fading
- Added `KILLFEED_FADE_TIME = 0.4` — seconds for the fade-out tween
- Added `TEAM_ATTACKERS = "Attackers"` and `TEAM_DEFENDERS = "Defenders"` — canonical team name strings (triggered by DEBT-020 fix condition: KillFeedUI is the third consumer)
- Added `COLOR_TEAM_ATTACKERS = Color3.fromRGB(255, 80, 80)`, `COLOR_TEAM_DEFENDERS = Color3.fromRGB(80, 140, 255)`, `COLOR_TEAM_NEUTRAL = Color3.fromRGB(220, 220, 220)` — centralized Color3 values for UI team tinting (triggered by DEBT-004 fix condition: KillFeedUI needs team colours)

**Updated — `src/server/RemoteSetup.server.lua`**
- Added `makeEvent("KillFeed")` in the "Teams / death tracking" section

**Updated — `src/server/DamageService.lua`**
- Added `KillFeed` remote reference at module level
- `killPlayer()`: after firing HealthChanged and applying ragdoll, fires `KillFeed:FireAllClients(killerDisplayName, victimDisplayName, killerTeamName, victimTeamName)`; `killerDisplayName` is `attacker.DisplayName` or `""` for environment kills; `killerTeamName` is `playerTeam[attacker]` or `""` if attacker has no recorded team (mid-round joiner or environment kill)
- Header comment updated to note KillFeed broadcast

**New file — `src/client/UI/KillFeedUI.lua`**
- `init(playerGui)`: creates ScreenGui "KillFeedUI" (`ResetOnSpawn=false`, `IgnoreGuiInset=true`, `DisplayOrder=5`); transparent container Frame anchored top-right (AnchorPoint=(1,0), 8 px inset, 260 px wide, `AutomaticSize=Y`); UIListLayout (Vertical, LayoutOrder sort, 2 px padding)
- `Start()`: connects `KillFeed.OnClientEvent` → calls `addEntry()`
- `addEntry(killerName, victimName, killerTeam, victimTeam)`: enforces max 5 entries (oldest `removeEntry()`d immediately when a 6th arrives); creates a 22 px Frame with semi-transparent black background; TextLabel with `RichText=true` showing `<font color="rgb(...)">KillerName</font> → <font color="rgb(...)">VictimName</font>` — team colours from `Constants.COLOR_TEAM_*`; environment kills show `✦ → VictimName` in neutral colour; schedules `task.delay(KILLFEED_DISPLAY_TIME)` → TweenService fades `BackgroundTransparency` and `TextTransparency` to 1 over `KILLFEED_FADE_TIME` → `removeEntry()` on tween completion
- `removeEntry(frame)`: removes frame from `entries` table by reference and calls `Destroy()`; guarded against double-destroy via `if not frame.Parent then return end` check in the delay callback

**Updated — `src/client/ClientInit.client.lua`**
- KillFeedUI inserted at position 5 (after DeathScreen, before CrosshairUI) using `loadInitAndStart`
- CrosshairUI shifts to 6, ViewModelController to 7, SoundController to 8, GunController to 9
- Header comment updated to 9-entry order

**Updated — `docs/PROJECT_MAP.md`**
- Added `KillFeed` row to remote registry (Fired by DamageService.lua, Listened by KillFeedUI.lua)
- Added `KillFeedUI` to Presentation section
- Updated `RagdollApplied` Listened-by to include `SoundController.lua` (correction from prior entry)
- Updated ClientInit order to 9 entries; added `loadInitNoGuiAndStart` to the helpers list

**Debt evaluation**
- DEBT-004 (team colours not in Constants): **further resolved** — `COLOR_TEAM_*` Color3 constants now in Constants.lua; KillFeedUI uses them; TeamService's BrickColor values remain local (outside task scope); entry updated with reasoning
- DEBT-007 (RoundStateChanged fan-out): **unaffected** — KillFeedUI listens to KillFeed, not RoundStateChanged; listener count stays at 6
- DEBT-017 (ClientInit manual update): **worsened** — 9 entries now; count updated
- DEBT-020 (team name strings duplicated): **partially resolved** — `TEAM_ATTACKERS`/`TEAM_DEFENDERS` added to Constants.lua; KillFeedUI uses them; TeamService and ObjectiveService still have local copies (outside task scope); entry updated

---

## [2026-05-07] — Add server-authoritative ammo system with reload

**Ammo flow:** `TeamAssigned` → `GunService.setupAmmo()` → `AmmoChanged` → `GunController` + `HUD` | `WeaponFired` → ammo check → decrement → `AmmoChanged` | `ReloadRequest` → validate → transfer → `AmmoChanged`

**Updated — `src/shared/WeaponData.lua`**
- Added `magazineSize = 30` and `reserveAmmo = 90` to the AssaultRifle entry; updated field comment

**Updated — `src/server/GunService.server.lua`**
- Added `AmmoChanged` and `ReloadRequest` remote references
- Added `playerMag: { [Player]: number }` and `playerReserve: { [Player]: number }` state tables
- Added `setupAmmo(player)` helper: reads `DEFAULT_WEAPON.magazineSize` and `.reserveAmmo`, populates both tables, fires `AmmoChanged` to the player
- Added `MatchEvents.TeamAssigned.Event` listener → calls `setupAmmo(player)` at PREP start for every player
- `WeaponFired` handler: after rate limit, checks `playerMag[shooter]` — nil (mid-round joiner) silently returns; 0 fires `AmmoChanged(0, reserve)` to re-sync client and returns; positive decrements by 1 and fires `AmmoChanged` before the raycast
- Added `ReloadRequest.OnServerEvent` handler: validates ACTIVE phase and non-nil ammo tables; rejects if reserve ≤ 0 or mag already full (fires AmmoChanged to sync); otherwise transfers `min(magazineSize - mag, reserve)` rounds from reserve to magazine and fires AmmoChanged
- `PlayerRemoving`: now also clears `playerMag[player]` and `playerReserve[player]`

**Updated — `src/server/RemoteSetup.server.lua`**
- Added `makeEvent("AmmoChanged")` and `makeEvent("ReloadRequest")` in the "Health & combat" section

**Updated — `src/client/GunController.lua`**
- Added `AmmoChanged` and `ReloadRequest` remote references at module level
- Added `currentMag` and `currentReserve` state variables (start at 0/0; updated exclusively by AmmoChanged)
- Dry fire check added in `InputBegan` before rate limit: `if currentMag <= 0 then SoundController:PlayDryFire() return end`
- Added second `InputBegan` connection for `Enum.KeyCode.R` in ACTIVE phase: fires `ReloadRequest:FireServer()` then calls `SoundController:PlayReload()` (optimistic sound; server validates)
- Added `AmmoChanged.OnClientEvent` listener: caches `currentMag` and `currentReserve`; logs the new values
- Added `GunController:GetAmmo(): (number, number)` getter returning cached magazine and reserve

**Updated — `src/client/UI/HUD.lua`**
- Added `AmmoChanged` remote reference
- Added `ammoFrame` (130×44 px, bottom-right corner, same semi-transparent black style as health frame) and `ammoLabel` (right-aligned, 22 pt GothamBold, white) created in `init()`; initial text `"— / —"` until first AmmoChanged
- Added `setAmmo(mag, reserve)` helper: formats label as `"30 / 90"` etc.
- Added `AmmoChanged.OnClientEvent` listener in `Start()` → calls `setAmmo()`
- `RoundStateChanged` visibility handler updated: now also toggles `ammoFrame.Visible` alongside `hudFrame.Visible`

**Updated — `docs/PROJECT_MAP.md`**
- Added `AmmoChanged` and `ReloadRequest` rows to remote registry; updated `HitConfirmed` Listened-by to include `SoundController.lua`; updated HUD Presentation entry to include AmmoChanged

**Debt evaluation**
- DEBT-013 (hardcoded weapon name): **worsened** — ammo system adds a third hardcoded lookup point (`setupAmmo` and reload handler both use `DEFAULT_WEAPON`); entry updated
- DEBT-025 (DryFire no asset): **actively triggered** — GunController now calls `PlayDryFire()` on empty magazine; warning fires every playtest; entry updated with urgency
- DEBT-026 (new): ammo not initialized for mid-ACTIVE joiners; nil guard in WeaponFired silently blocks their shots; no crash, no functional impact today but will matter if reinforcement system is added
- All other entries: unaffected

---

## [2026-05-07] — Add sound system with gunshot, hit, reload, death sounds

**New file — `src/client/SoundController.lua`**
- `init()`: creates `SoundService/GameSounds/` folder; creates five `Sound` instances inside it: Gunshot (`rbxassetid://4792534948`, vol 0.6), HitConfirm (`rbxassetid://4612378292`, vol 0.8), Reload (`rbxassetid://3900723713`, vol 0.7), Death (`rbxassetid://3900724014`, vol 0.8), DryFire (no asset assigned yet, vol 0.5). All sounds have `RollOffMaxDistance = 0` (flat/non-positional — correct for local-player feedback)
- `Start()`: connects `HitConfirmed.OnClientEvent` → `PlayHit()`; connects `RagdollApplied.OnClientEvent` → `PlayDeath()` when `userId == LocalPlayer.UserId`. The death sound plays through DeathScreen's EQ muffle (DeathScreen connects first; EQ is active before PlayDeath fires)
- Public API: `PlayGunshot()`, `PlayHit()`, `PlayDryFire()` (logs warning, no-ops until DEBT-025 resolved), `PlayReload()`, `PlayDeath()`
- Volume and asset ID values are named local constants at module level (cannot go in Constants.lua per task scope restriction; move there when a second caller needs them)

**Updated — `src/client/GunController.lua`**
- Added module-level `require(SoundController)` alongside existing ViewModelController and CrosshairUI requires
- Added `SoundController:PlayGunshot()` call immediately after `WeaponFired:FireServer()` in the input handler (cosmetic, no server impact)

**Updated — `src/client/ClientInit.client.lua`**
- Added `loadInitNoGuiAndStart()` helper — for modules that have `init()` (no playerGui argument) followed by `Start()`; fills the gap between `loadAndStart` (no init) and `loadInitAndStart` (init with playerGui)
- SoundController inserted at position 7 using `loadInitNoGuiAndStart`; GunController shifts to position 8
- Header comment updated to 8-entry order; dependency note updated (GunController now requires ViewModelController, CrosshairUI, AND SoundController)

**Debt evaluation**
- DEBT-007 (RoundStateChanged fan-out): **unaffected** — SoundController connects to HitConfirmed and RagdollApplied, not RoundStateChanged
- DEBT-017 (ClientInit manual update): **worsened** — 8 entries now; count updated
- Added DEBT-024: single Sound instances have no audio pooling; rapid PlayGunshot() calls restart instead of overlap
- Added DEBT-025: DryFire has no asset ID; PlayDryFire() is a no-op until the ammo system is built

---

## [2026-05-07] — Add ragdoll system and death screen with blur and audio muffling

**Death pipeline overview:** `DamageService:killPlayer()` → `RagdollService:Apply()` → `humanoid.Health = 0` → `Humanoid.Died` (TeamService alive tracking, unchanged) + `RagdollApplied:FireAllClients()` (DeathScreen client trigger)

**New file — `src/server/RagdollService.lua`**
- `RagdollService:Apply(character, victim, attacker)` called by DamageService when health reaches 0
- Iterates `character:GetDescendants()` for all `Motor6D` instances; for each: creates two `Attachment` instances in `Part0` (CFrame = `C0`) and `Part1` (CFrame = `C1`), creates a `BallSocketConstraint` linking them (`LimitsEnabled = true`, `UpperAngle = 45`), then sets `Motor6D.Enabled = false`
- Sets `humanoid.PlatformStand = true` (stops Humanoid from counteracting physics) then `humanoid.Health = 0` (fires `Humanoid.Died` → TeamService still handles alive tracking with no changes)
- Fires `MatchEvents.PlayerDied:Fire(victim, killerName)` for future consumers (RewardService, CorpseService)
- Fires `RagdollApplied:FireAllClients(victim.UserId, killerName)` — `killerName` is `attacker.DisplayName` or `""` for environment kills
- Warns if no Motor6Ds found (non-standard rig) or if Part0/Part1 is nil on any joint

**Updated — `src/server/DamageService.lua`**
- Added `require(RagdollService)` at module level
- `killPlayer()` now calls `RagdollService:Apply(character, player, attacker)` instead of directly setting `humanoid.Health = 0`; logs a warning and skips ragdoll if `player.Character` is nil at kill time
- Header comment updated to reflect that character is no longer destroyed

**Updated — `src/server/MatchEvents.lua`**
- Added `MatchEvents.PlayerDied = Instance.new("BindableEvent")` — payload: `(player: Player, killerName: string)` — for future server-side listeners that want a named death signal without relying on `Humanoid.Died`

**Updated — `src/server/RemoteSetup.server.lua`**
- Added `makeEvent("RagdollApplied")` in the "Teams / death tracking" section

**New file — `src/client/UI/DeathScreen.lua`**
- `init(playerGui)`: creates ScreenGui "DeathScreen" (`ResetOnSpawn=false`, `IgnoreGuiInset=true`, `DisplayOrder=10`); full-screen black overlay Frame (starts `BackgroundTransparency=1`); centered text container (hidden by default) with "YOU DIED" (GothamBold, large, white), "Eliminated by [Name]" (Gotham, red, hidden if no killer), "Waiting for next round..." (Gotham, grey)
- `Start()`: connects `RagdollApplied.OnClientEvent` — if `userId == LocalPlayer.UserId`, calls `showDeathUI(killerName)`: creates `BlurEffect` in `game.Lighting` (Size 0 → 24 via TweenService), creates `EqualizerSoundEffect` in `SoundService` (`LowGain=Constants.DEATH_EQ_LOW_GAIN`, `MidGain=Constants.DEATH_EQ_MID_GAIN`, `HighGain=Constants.DEATH_EQ_HIGH_GAIN`), tweens overlay `BackgroundTransparency` from 1 to `1-DEATH_OVERLAY_OPACITY` (0.4), shows text container after `DEATH_FADE_TIME` seconds via `task.delay`
- Connects `RoundStateChanged.OnClientEvent` — on PREP: calls `hideDeathUI()` which hides text, tweens overlay back to transparent, tweens blur Size back to 0 then destroys `BlurEffect`, destroys `EqualizerSoundEffect` after cleanup tween
- Active tween is cancelled before any new tween starts to prevent overlap on rapid phase changes

**Updated — `src/shared/Constants.lua`**
- Added 7 death screen constants: `DEATH_FADE_TIME = 0.8`, `DEATH_OVERLAY_OPACITY = 0.6`, `DEATH_BLUR_SIZE = 24`, `DEATH_CLEANUP_TIME = 0.5`, `DEATH_EQ_LOW_GAIN = 0`, `DEATH_EQ_MID_GAIN = -50`, `DEATH_EQ_HIGH_GAIN = -60`

**Updated — `src/client/ClientInit.client.lua`**
- DeathScreen inserted at position 4 (after HUD, before CrosshairUI); uses `loadInitAndStart()`
- Header comment updated: 7-entry order documented

**Updated — `docs/PROJECT_MAP.md`**
- Added `RagdollApplied` row to remote registry (Fired by RagdollService, Listened by DeathScreen)
- Added `DeathScreen` to Presentation section
- Updated ClientInit order to 7 entries

**Debt evaluation**
- DEBT-007 (RoundStateChanged fan-out): **worsened** — now 6 listeners; entry updated with new count
- DEBT-009 (no friendly-fire guard): **unaffected**
- DEBT-010 (health reset vs mid-respawn): **partially mitigated** — characters stay ragdolled rather than being respawned, reducing the timing window; structural risk remains
- DEBT-017 (ClientInit manual update): **worsened** — 7 entries now; entry updated with current count
- Added DEBT-022: ragdolled characters have no cleanup owner until CorpseService is built; corpses accumulate across rounds
- Added DEBT-023: Motor6D ragdoll conversion assumes standard R15/R6 rig; custom rigs untested

---

## [2026-05-07] — Sync all documentation to current codebase state

**`docs/ROADMAP.md`**
- Stage 2: checked off MatchController, TeamService, ObjectiveService; updated descriptions to reflect actual implementation (win-condition tallying, alive-count tracking, per-player touch counting)
- Stage 3: split "Basic UI" into three separate entries — HUD (checked), MatchUI (checked), ObjectiveUI (unchecked, not yet built)
- Stage 4: checked off GunService, GunController, DamageService; added ViewModelController+CrosshairUI as a checked entry; MovementController remains unchecked

**`docs/PROJECT_MAP.md`**
- Presentation section: added `CrosshairUI` (driven by RoundStateChanged, exposes ShowHitmarker()) and `ViewModelController` (driven by RoundStateChanged, exposes PlayFireAnimation()/GetBarrelTipCFrame()); corrected HUD driven-by list from AmmoChanged to TeamStatusUpdate; added ObjectiveComplete to ObjectiveUI driven-by list

No code changes in this entry. Remote registry, ClientInit order, and debt entries were already up to date from prior sessions.

---

## [2026-05-07] — Add viewmodel, crosshair, hitmarker, muzzle flash

**Part 1 — ViewModelController (`src/client/ViewModelController.lua`, new)**
- Creates three Parts (GunBody 0.8×0.2×0.5, Barrel 0.08×0.6×0.08 with Cylinder SpecialMesh, Grip 0.15×0.25×0.15) parented to `workspace.CurrentCamera` in `Start()`
- All parts: `Anchored=false`, `CanCollide=false`, `CastShadow=false`, `BrickColor="Dark grey"`
- `RunService.RenderStepped` updates GunBody CFrame to `camera.CFrame * CFrame.new(0.6, -0.4, -1.2) * CFrame.new(0, 0, recoilOffset)` every frame; Barrel and Grip follow with fixed offsets
- Visibility toggled by `RoundStateChanged` — shown only during `ACTIVE`, hidden in all other phases
- `PlayFireAnimation()`: sets `recoilOffset = 0.05`; RenderStepped decays it back to 0 at 1 stud/sec (returns in 0.05 s)
- `GetBarrelTipCFrame()`: returns `gunBody.CFrame * CFrame.new(0, 0.04, -0.85)` — the muzzle world CFrame used by GunController for flash placement

**Part 2 — CrosshairUI (`src/client/UI/CrosshairUI.lua`, new)**
- Creates a ScreenGui "CrosshairUI" (`ResetOnSpawn=false`, `IgnoreGuiInset=true`) in `init(playerGui)`
- Crosshair: four white Frames (2×10 px top/bottom, 10×2 px left/right) with 4 px gap and `AnchorPoint=(0.5, 0.5)`; container hidden until `Start()` receives a phase
- Hitmarker: four white 2×10 px Frames placed diagonally (NE, NW, SE, SW — ±8 px from center, rotated ±45°) forming an X; hidden by default
- `Start()` connects `RoundStateChanged` — crosshair shown during `PREP` and `ACTIVE` only
- `ShowHitmarker()`: sets hitmarker container visible, hides it after 0.1 s via `task.delay`

**Part 3 — GunController (`src/client/GunController.lua`, updated)**
- Added module-level requires: `ViewModelController` (sibling) and `CrosshairUI` (`UI/CrosshairUI`)
- After `WeaponFired:FireServer()`: calls `ViewModelController:PlayFireAnimation()`, then creates a 0.3-stud Neon bright-yellow Sphere Part (SpecialMesh) at `ViewModelController:GetBarrelTipCFrame()` parented to `workspace.CurrentCamera`, destroyed after 0.05 s via `task.delay`
- `HitConfirmed` listener: now calls `CrosshairUI:ShowHitmarker()` before the existing `Logger.debug("HIT")` call
- No changes to raycast, rate-limiting, phase gate, or server fire logic

**Part 4 — ClientInit (`src/client/ClientInit.client.lua`, updated)**
- New initialization order: MatchController → MatchUI → HUD → CrosshairUI → ViewModelController → GunController
- CrosshairUI uses `loadInitAndStart()` (needs PlayerGui); ViewModelController uses `loadAndStart()` (no PlayerGui)
- Dependency comment updated: ViewModelController and CrosshairUI must start before GunController

**Debt evaluation**
- DEBT-007 (RoundStateChanged fan-out): **worsened** — now 5 listeners (MatchController, MatchUI, HUD, CrosshairUI, ViewModelController); entry updated with new count and escalated urgency
- DEBT-017 (ClientInit manual update): **worsened** — 2 more entries added (CrosshairUI, ViewModelController)
- All other open entries: unaffected
- Added DEBT-021: ViewModelController parts created once in `Start()` with no cleanup — second call would orphan the first set of parts

---

## [2026-05-07] — Batch 1: Constants, Types, RemoteSetup, Logger baseline audit

Confirmed and completed the shared-module baseline required before building further systems. Most values were already present from the previous session; the audit identified and filled one gap.

**`src/shared/Constants.lua`**
- Already present: `Phase.MATCHEND`, `MAX_HEALTH`, `ANCHOR_PLANT_TIME`, `COUNTDOWN_TICK`, `TELEPORT_Y_OFFSET`, `LOBBY_POLL_INTERVAL`, `MATCH_END_PAUSE`
- Added: `RESPAWN_DELAY = 5` — seconds before a player re-enters play at round start; reserved for the future reinforcement system, not yet consumed by any service

**`src/shared/Types.lua`**
- Already correct: `Phase` union includes all five values (`"LOBBY" | "PREP" | "ACTIVE" | "RESULTS" | "MATCHEND"`); `RoundStatePayload` already carries `winner`, `attackerWins`, `defenderWins`
- No changes made

**`src/server/RemoteSetup.server.lua`**
- Already present: `makeEvent("TeamStatusUpdate")`
- No changes made

**`src/shared/Logger.lua`**
- Already exists with `RunService:IsStudio()` DEBUG_MODE guard, `Logger.debug()`, `Logger.warn()`
- No changes made

**Debt evaluation**
- DEBT-001 (Phase type sync): updated to "partially resolved" — both files list the same five phases after MATCHEND was added; structural risk (no compiler enforcement) remains
- DEBT-016 (Logger DEBUG_MODE): confirmed fully resolved from prior session; no action needed

---

## [2026-05-07] — Four systems for first playtest: death tracking, win conditions, objectives, HUD + MatchUI

**System 1 — Death tracking (TeamService)**
- `Players.CharacterAutoLoads = false` set at the top of TeamService; Roblox never auto-spawns characters
- `player:LoadCharacter()` called for all players at the start of each PREP phase (concurrent)
- New state: `aliveAttackers`, `aliveDefenders`, `diedConnections: { [Player]: RBXScriptConnection }`, `currentPhase`
- `handlePlayerDied(player)`: removes the player from the alive table for their team, fires `TeamStatusUpdate:FireAllClients(attAlive, defAlive)`, and fires `MatchEvents.RoundEndedEarly` if one team is fully eliminated (simultaneous elimination → Defenders win as tiebreak)
- `setupDeathTracking()`: connects `Humanoid.Died` for every player at ACTIVE start; broadcasts initial alive counts; stores connections by player for clean disconnection
- `cleanupDeathTracking()`: disconnects all `Humanoid.Died` connections; called at RESULTS
- `PlayerRemoving`: disconnects the player's death connection; treats a mid-ACTIVE disconnect as a death via `handlePlayerDied()` before clearing tables
- `resetTeams()` updated to call `cleanupDeathTracking()` and use `table.clear()` for alive tables
- Added `TeamStatusUpdate` RemoteEvent to `RemoteSetup.server.lua`
- Added `MatchEvents.RoundEndedEarly = Instance.new("BindableEvent")` to `src/server/MatchEvents.lua`

**System 2 — Win conditions (MatchService)**
- Removed the old local `RoundEndedEarly` BindableEvent and `MatchService` table; early-end signals now flow through `MatchEvents.RoundEndedEarly` so TeamService and ObjectiveService can fire it
- New state: `currentWinner: string`, `attackerRoundWins: number`, `defenderRoundWins: number`
- `broadcast()` now includes `winner`, `attackerWins`, `defenderWins` in every `RoundStateChanged` payload
- `GetMatchConfig` returns the full payload including winner and win counts
- `countdown()` signature changed to `(phase, round, duration, listenForEarlyEnd?): (boolean, string)` — returns the winner string captured from `MatchEvents.RoundEndedEarly` when ended early
- `runActive()` returns `"Time Expired"` on normal completion or the winner team name on early end
- `runResults(round, winner)` sets `currentWinner` before broadcasting so RESULTS payloads carry the winner
- `runMatch()` resets win counts at match start, tallies wins per round ("Time Expired" counts as Defenders), determines the overall match winner (or "Draw"), broadcasts MATCHEND with `MATCHEND_DURATION`, then waits
- Added `Constants.MATCHEND` phase to `Constants.Phase`; "MATCHEND" added to `Types.Phase` union
- Added `Constants.RESULTS_DURATION = 10` and `Constants.MATCHEND_DURATION = 15` to `Constants.lua`

**System 3 — Objective capture (ObjectiveService)**
- New file `src/server/ObjectiveService.server.lua`
- Subscribes to `MatchEvents.TeamAssigned` to build a local `playerTeams` table; does not require TeamService directly (avoids cross-require and DEBT-011 timing risk)
- On ACTIVE: scans `Workspace/Objectives` for BaseParts and calls `registerObjective()` on each
- `registerObjective(part)`: creates an `ObjectiveState` record and connects `Touched`/`TouchEnded` with per-player touch counting (prevents body-part spam from causing false entry/exit)
- `startCapture(state, planter)`: spawns a task that ticks progress every `COUNTDOWN_TICK`; fires `ObjectiveUpdated:FireAllClients(part, progress)` each tick; exits cleanly if `state.planter` changes before `ANCHOR_PLANT_TIME` elapses
- `cancelCapture(state)`: clears planter and fires `ObjectiveUpdated` with progress 0
- `completeObjective(state)`: marks planted, fires `ObjectiveComplete:FireAllClients(part)`, checks if all objectives are planted, fires `MatchEvents.RoundEndedEarly("Attackers")` when they are
- `resetObjectives()`: disconnects all `Touched`/`TouchEnded` connections and clears the objectives table; called on PREP and RESULTS
- `PlayerRemoving`: clears `playerTeams` entry and cancels any in-progress capture by that player

**System 4 — MatchUI and HUD**
- `src/client/UI/MatchUI.lua` (new ModuleScript): creates a ScreenGui with a top bar (round/phase label + timer), a RESULTS overlay (winner + round scores), and a MATCHEND overlay (match winner + final scores); hidden during LOBBY; connects `RoundStateChanged.OnClientEvent` in `Start()`
- `src/client/UI/HUD.lua` (new ModuleScript): creates a ScreenGui with a bottom-left frame containing a health number, a colour-coded health bar (green → orange → red by ratio), and a team-alive-count label; connects `HealthChanged`, `TeamStatusUpdate`, and `RoundStateChanged` in `Start()`; hidden during LOBBY and MATCHEND
- `src/client/MatchController.lua`: added `currentWinner`, `currentAttackerWins`, `currentDefenderWins` state; `applyState()` reads these from the payload; added `GetWinner()`, `GetAttackerWins()`, `GetDefenderWins()` public getters
- `src/client/ClientInit.client.lua`: added `loadInitAndStart()` helper for UI modules that require `init(playerGui)` before `Start()`; added `Players.LocalPlayer:WaitForChild("PlayerGui")` reference; updated initialization order to: MatchController → MatchUI → HUD → GunController

**Debt evaluation**
- DEBT-003 (lastFiredPhase phase-only): unaffected — MatchService changes do not worsen or resolve it
- DEBT-007 (applyState growth): partially triggered — MatchUI and HUD connect directly to RoundStateChanged; updated entry to reflect the fan-out pattern and the planned BindableEvent fix
- DEBT-009 (no friendly-fire guard): unaffected
- DEBT-011 (no on-demand team query): ObjectiveService uses TeamAssigned subscription correctly; risk not triggered since all services start before the first PREP phase
- DEBT-017 (ClientInit manual update): worsened by two new UI entries; still acceptable at this controller count
- Added DEBT-018: `getPlayerFromPart` duplicated in DamageService and ObjectiveService
- Added DEBT-019: `Players.CharacterAutoLoads = false` set globally in TeamService with no fallback
- Added DEBT-020: `TEAM_ATTACKERS` / `TEAM_DEFENDERS` string literals duplicated across TeamService and ObjectiveService

---

## [2026-05-07] — Resolve DEBT-015: ClientInit pattern + controller ModuleScript conversion

**Part 1 — MatchController renamed**
- `src/client/MatchController.client.lua` → `src/client/MatchController.lua` — Rojo now creates a ModuleScript instance; `require()` from GunController resolves correctly
- Updated header comment from `-- LocalScript` to `-- ModuleScript`
- Removed the `MatchController:Start()` self-call at the bottom of the file — leaving it would have caused `Start()` to fire twice on first `require()` (once from the module tail, once from ClientInit), registering `RoundStateChanged.OnClientEvent` twice and causing double event delivery
- Added clarifying comment on `Start()`: called once by ClientInit, not self-invoked

**Part 2 — GunController renamed and wrapped**
- `src/client/GunController.client.lua` → `src/client/GunController.lua` — ModuleScript so ClientInit can require it
- Updated header comment from `-- LocalScript` to `-- ModuleScript`; removed now-resolved DEBT-015 prerequisite warning
- Added `local GunController = {}` table and wrapped all event connections (`InputBegan`, `HitConfirmed.OnClientEvent`, `HealthChanged.OnClientEvent`) and the Ready log inside `GunController:Start()` — no logic changed, only structure
- Added `return GunController` at the bottom
- All module-level requires and state declarations (`lastShotTime`, `CURRENT_WEAPON`) remain at module level as before

**Part 3 — ClientInit**
- Created `src/client/ClientInit.client.lua` — the only LocalScript in the Controllers folder; requires `MatchController` then `GunController` via `script.Parent:WaitForChild()`; calls each controller's `:Start()` in dependency order; both the `require` and the `Start()` call for each controller are individually guarded by `pcall` with `Logger.warn()` on failure so one broken controller never silently blocks the others

**Docs**
- Updated `docs/PROJECT_MAP.md`: added "Client initialization pattern" section explaining the ClientInit runner, current initialization order, and instructions for adding future controllers
- Updated `docs/TECHNICAL_DEBT.md`: DEBT-015 marked resolved with full reasoning (double-call bug explained); DEBT-007 and DEBT-013 file references corrected from `.client.lua` to `.lua`; DEBT-008 file reference corrected; added DEBT-017 (ClientInit must be manually updated when a new controller is added)

---

## [2026-05-07] — Resolve DEBT-016: Logger.DEBUG_MODE auto-detects Studio vs production

- Updated `src/shared/Logger.lua`: replaced `local DEBUG_MODE = true` with `local DEBUG_MODE = game:GetService("RunService"):IsStudio()` — `Logger.debug()` is now automatically silent in every published build without any manual code edit before shipping; the manual-step risk described in DEBT-016 is fully eliminated
- `src/client/GunController.client.lua`: already built and committed in the previous session (`6904711`); satisfies all requirements (UserInputService left-click, phase gate via `MatchController:GetPhase()`, client-side rate limit from `WeaponData`, camera raycast excluding local character, `WeaponFired:FireServer(origin, direction, now)`, `HitConfirmed` and `HealthChanged` listeners, Logger throughout); no changes needed
- `docs/PROJECT_MAP.md`: `WeaponFired` and `HitConfirmed` listener columns already correctly show `GunController.client.lua` from the five-rules task; no changes needed
- Updated `docs/TECHNICAL_DEBT.md`: marked DEBT-016 resolved with full reasoning

---

## [2026-05-07] — Five project rules: Logger, no magic numbers, no silent failures, remote ownership, no circular requires

**Rule 1 — No circular requires (doc only)**
- Added rule to `CLAUDE.md`: never require a module that directly or indirectly requires the caller back; use a BindableEvent in `MatchEvents.lua` for bidirectional server communication; confirm one-way dependency direction before requiring

**Rule 2 — Remote ownership**
- Updated `docs/PROJECT_MAP.md`: expanded remote registry table from 4 to 5 columns — added **Listened by** column; changed **Fired by** from generic "Client"/"Server" labels to exact script filenames (`GunController.client.lua`, `GunService.server.lua`, `DamageService.lua`, `MatchService.server.lua`, `TeamService.server.lua`, `MatchController.client.lua`); rows for unbuilt systems marked `pending`
- Added rule to `CLAUDE.md`: register every remote in `docs/PROJECT_MAP.md` before implementing; one Fired by, one Listened by per remote; never fire or listen to an unregistered remote

**Rule 3 — No magic numbers**
- Audited all files in `src/server/` and `src/client/` for numeric literals that are not loop counters or table indices
- Added four new named constants to `src/shared/Constants.lua`:
  - `TELEPORT_Y_OFFSET = 3` — studs above a spawn part's centre so characters land on top (moved from local variable in `TeamService.server.lua`)
  - `COUNTDOWN_TICK = 1` — seconds between each broadcast inside a phase countdown (moved from `task.wait(1)` in `MatchService.server.lua`)
  - `LOBBY_POLL_INTERVAL = 2` — seconds between player-count checks while waiting for MIN_PLAYERS (moved from `task.wait(2)` in `MatchService.server.lua`)
  - `MATCH_END_PAUSE = 3` — seconds between end of one match and start of the next (moved from `task.wait(3)` in `MatchService.server.lua`)
- Added rule to `CLAUDE.md`: no numeric literal in any service or controller except loop counters and table indices

**Rule 4 — Logger.lua**
- Created `src/shared/Logger.lua` — `DEBUG_MODE = true` flag at top; `Logger.debug(...)` prints `[DEBUG]` prefix only when flag is true; `Logger.warn(...)` always calls Roblox `warn()` with `[WARN]` prefix; no other logic
- Updated all six source files to replace every `print()` with `Logger.debug()` and every `warn()` with `Logger.warn()`, and to require Logger via `Modules:WaitForChild("Logger")`:
  - `src/server/MatchService.server.lua`
  - `src/server/TeamService.server.lua`
  - `src/server/DamageService.lua`
  - `src/server/GunService.server.lua`
  - `src/client/MatchController.client.lua`
  - `src/client/GunController.client.lua`
- Added rule to `CLAUDE.md`: never call `print()` or `warn()` directly; always use Logger

**Rule 5 — No silent failures**
- Audited all files in `src/server/` and `src/client/` for unlogged failures; found and fixed three:
  - `src/server/TeamService.server.lua` `teleportToSpawn()` — nil `character` returned silently → now calls `Logger.warn("[TeamService] teleportToSpawn: character is nil for <name> — skipping")`
  - `src/server/TeamService.server.lua` `teleportToSpawn()` — nil `HumanoidRootPart` returned silently → now calls `Logger.warn("[TeamService] teleportToSpawn: HumanoidRootPart missing for <name> — skipping")`
  - `src/server/GunService.server.lua` — `typeof` guard for invalid Vector3 payload returned silently → now calls `Logger.warn("[GunService] WeaponFired: invalid payload types from <name>")`
- Added rule to `CLAUDE.md`: every `pcall` failure branch must log with `Logger.warn()`; every unexpected nil return must log with `Logger.warn()`

**Debt evaluation**
- Updated `docs/TECHNICAL_DEBT.md`:
  - DEBT-004: marked partially resolved — `TELEPORT_Y_OFFSET` moved to Constants; `ATTACKER_COLOR`/`DEFENDER_COLOR` remain local (BrickColor values fall outside the no-magic-numbers rule); colour-duplication risk persists
  - DEBT-010: corrected stale file reference from `DamageService.server.lua` to `DamageService.lua`
  - Added DEBT-016: `Logger.DEBUG_MODE` is a source-level flag — shipping with debug output visible requires a manual code edit; fix is `RunService:IsStudio()` guard

---

## [2026-05-06] — GunController + CLAUDE.md debt-resolution rule

- Added `src/client/GunController.client.lua` — listens to left mouse button via `UserInputService`; gates shots on `MatchController:GetPhase() == ACTIVE`; enforces client-side rate limit from `WeaponData["AssaultRifle"].fireRate`; casts a client-side ray from `workspace.CurrentCamera` (result not yet used — placeholder for future viewmodel hit FX); fires `WeaponFired:FireServer(origin, direction, now)`; listens to `HitConfirmed` and prints `HIT` (placeholder for hitmarker); listens to `HealthChanged` and prints current/max health (placeholder for HUD)
- Updated `CLAUDE.md`: appended new Claude behavior rule — when a task touches a debt entry, evaluate whether the underlying risk is genuinely gone before marking it resolved, not just whether the requested fix was applied
- Updated `docs/TECHNICAL_DEBT.md`: added DEBT-015 (MatchController.client.lua must be renamed MatchController.lua — blocking prerequisite identical to the DEBT-012 pattern); updated DEBT-013 to reflect that GunController also has a hardcoded `CURRENT_WEAPON` that doubles the sync risk; corrected stale file reference in DEBT-009 (`DamageService.server.lua` → `DamageService.lua`)

---

## [2026-05-06] — Resolve DEBT-012: rename DamageService to ModuleScript

- Renamed `src/server/DamageService.server.lua` → `src/server/DamageService.lua` — Rojo maps `.server.lua` to Script and `.lua` to ModuleScript; the old name prevented `require()` from GunService at runtime; logic is identical, only the file header comment changed (`-- Script` → `-- ModuleScript`)
- `default.project.json` unchanged — server folder is mapped by directory path, not by explicit file list
- Updated `docs/TECHNICAL_DEBT.md`: marked DEBT-012 resolved with today's date

---

## [2026-05-06] — GunService

- Added `src/server/GunService.server.lua` — validates client shot requests server-side; listens to `WeaponFired` RemoteEvent; enforces ACTIVE-phase gate, Vector3 type guard, per-player rate limit (from WeaponData.fireRate), and server raycast; calls `DamageService:Apply(victim, damage, shooter)` on a confirmed hit; fires `HitConfirmed` back to the shooter client for a cosmetic hitmarker; cleans up `lastShotTime` on `PlayerRemoving`
- Updated `src/shared/WeaponData.lua` — replaced stub comment with first real entry: `WeaponData["AssaultRifle"] = { damage = 25, fireRate = 0.1, range = 300 }`
- Updated `docs/TECHNICAL_DEBT.md` — updated DEBT-009 (friendly-fire guard now actively triggered by GunService); added DEBT-012 (DamageService.server.lua must be renamed to DamageService.lua — blocking prerequisite before GunService can run); added DEBT-013 (hardcoded DEFAULT_WEAPON until GunController supplies weapon name in payload); added DEBT-014 (clientTick received but not validated against shot-replay window)

---

## [2026-05-06] — Fix three bugs from DamageService/TeamService tasks

- `src/server/TeamService.server.lua`: removed dead `local TeamService = {}` table, `TeamService:GetTeam()` method, and `return TeamService` — TeamService is a `.server.lua` Script and cannot be required, so the public API was unreachable; replaced with a comment explaining that team data is accessed via `MatchEvents.TeamAssigned`
- `src/server/MatchEvents.lua`: `MatchEvents.TeamAssigned` BindableEvent confirmed present (was already added when DamageService was written; no change needed)
- `src/shared/Constants.lua`: `Constants.MAX_HEALTH = 100` confirmed present (was already added when DamageService was written; no change needed)
- `docs/TECHNICAL_DEBT.md`: added DEBT-011 — no on-demand team query path exists for services that miss the TeamAssigned event window; fix when a late-loading service needs `TeamData.GetTeam(player)`

---

## [2026-05-06] — DamageService + DEBT-006 resolution

- Added `src/server/DamageService.server.lua` — server-authoritative health tracking; `DamageService:Apply(victim, amount, attacker)` clamps damage and calls `killPlayer()` when health reaches zero; `HealthChanged` fires to the victim's client on every health change; health resets to `MAX_HEALTH` on every PREP phase for all connected players; `playerHealth` and `playerTeam` tables are cleared on `PlayerRemoving`
- Added `Constants.MAX_HEALTH = 100` to `src/shared/Constants.lua` — single source of truth for starting and maximum health (config module rule)
- Updated `src/server/MatchEvents.lua`: added `MatchEvents.TeamAssigned = Instance.new("BindableEvent")` — fired per-player inside TeamService's `assignTeams()`, consumed by DamageService for team tracking
- Updated `src/server/TeamService.server.lua`: added `MatchEvents.TeamAssigned:Fire(player, teamName)` inside the `assignTeams()` loop — resolves DEBT-006
- Updated `docs/TECHNICAL_DEBT.md`: marked DEBT-006 resolved; added DEBT-009 (no friendly-fire guard in Apply() yet) and DEBT-010 (health reset during mid-respawn may cause brief Humanoid mismatch)

---

## [2026-05-06] — Resolve DEBT-008: GetMatchConfig errors now visible in Output

- Updated `src/client/MatchController.client.lua`: split the pcall `else` branch into two cases — `not ok` now calls `warn()` with the actual error string (red in Output) rather than a generic print; `ok` with a nil result keeps the original timing-fallback print
- Updated `docs/TECHNICAL_DEBT.md`: marked DEBT-008 resolved with today's date

---

## [2026-05-06] — Technical debt tracking added

- Created `docs/TECHNICAL_DEBT.md` — running registry of known maintenance risks and deferred problems; 8 entries covering: Phase type sync (DEBT-001), RemoteSetup Folder cast resolved (DEBT-002), lastFiredPhase phase-only comparison (DEBT-003), TeamService colours/offset not in Constants (DEBT-004), odd player split bias (DEBT-005), playerTeams has no observer signal (DEBT-006), MatchController applyState growth risk (DEBT-007), pcall silently swallows GetMatchConfig errors (DEBT-008)
- Updated `CLAUDE.md`: added `docs/TECHNICAL_DEBT.md` to the required reading list; added two new Claude behavior rules — (1) add every flagged risk to TECHNICAL_DEBT.md before finishing a task, (2) read TECHNICAL_DEBT.md at the start of every task and report which entries are relevant before writing code

---

## [2026-05-06] — Fix PhaseChanged firing once per second instead of once per transition

- Updated `src/server/MatchService.server.lua`: added `lastFiredPhase = ""` to the State block; wrapped `MatchEvents.PhaseChanged:Fire()` in a `phase ~= lastFiredPhase` guard so it fires exactly once per phase transition rather than every second — all current and future listeners (TeamService, ObjectiveService) are automatically protected

---

## [2026-05-06] — Wire MatchService → MatchEvents

- Updated `src/server/MatchService.server.lua`: added `require(MatchEvents)` in the dependencies block; added `MatchEvents.PhaseChanged:Fire(phase, round)` inside `broadcast()` after `FireAllClients` — TeamService and future ObjectiveService now receive phase signals without polling

---

## [2026-05-06] — TeamService + MatchEvents bridge

- Added `src/server/MatchEvents.lua` — server-only ModuleScript holding `PhaseChanged` BindableEvent; bridges MatchService → TeamService (and future ObjectiveService) without polling; includes instructions for the two lines that must be added to MatchService to activate the connection
- Added `src/server/TeamService.server.lua` — assigns players to Roblox Teams on PREP, teleports each to a random spawn in `Workspace/Spawns/Attackers` or `Workspace/Spawns/Defenders`, fires `TeamAssigned` to each client, resets on RESULTS; handles missing spawn folders gracefully; exposes `TeamService:GetTeam(player)` for DamageService and ObjectiveService

---

## [2026-05-06] — MatchController (client)

- Added `src/client/MatchController.client.lua` — client-side match state mirror; syncs on join via `GetMatchConfig`, then stays current via `RoundStateChanged`; stores `currentPhase`, `currentRound`, `currentTimeLeft`, `currentMaxRounds` locally; prints state to Output for verification; exposes `GetPhase`, `GetRound`, `GetTimeLeft`, `GetMaxRounds` for MatchUI to call once built

---

## [2026-05-06] — Two type-safety fixes

- `src/server/RemoteSetup.server.lua`: fixed unsafe nil cast — `FindFirstChild` result is now left as `Instance?`, nil-checked first, then narrowed with `:: Folder` only inside the branch where nil is already ruled out
- `src/shared/Types.lua`: added a prominent sync warning on the `Phase` union explaining that Luau cannot derive it from `Constants.Phase` at compile time, and that both files must be updated together whenever a phase is added or renamed

---

## [2026-05-06] — Coding rules expanded in CLAUDE.md and PROJECT_RULES.md

- Added explicit "Config modules" rule: tunable values must live in `ReplicatedStorage/Modules`, never hardcoded
- Added "Explaining changes" rule: every task must list every changed file, explain how new code connects to existing systems, flag maintenance risks, and provide test steps
- These rules now appear in both `CLAUDE.md` (Claude behavior section + code rules) and `docs/PROJECT_RULES.md`

---

## [2026-05-06] — Stage 1 infrastructure + MatchService

- Added `default.project.json` (Rojo project), `wally.toml`, `selene.toml`, `stylua.toml`
- Added `src/shared/Constants.lua` — Phase enum (LOBBY, PREP, ACTIVE, RESULTS), all timing values, MAX_ROUNDS, MIN_PLAYERS
- Added `src/shared/Types.lua` — `Phase` and `RoundStatePayload` type exports
- Added `src/shared/WeaponData.lua` — stub, populated when GunService is built
- Added `src/shared/ZoneData.lua` — stub, populated when ZoneService is built
- Added `src/server/RemoteSetup.server.lua` — creates all RemoteEvents and RemoteFunctions in ReplicatedStorage/Remotes at server start
- Added `src/server/MatchService.server.lua` — full match loop: Lobby → (Prep → Active → Results) × 5, fires RoundStateChanged every second, handles GetMatchConfig for late-joining clients, exposes RoundEndedEarly BindableEvent for ObjectiveService
- Updated `docs/NAMING.md` — added PREP phase, corrected file extension table (`.server.lua`, `.client.lua`, `.lua`)
- Updated `docs/ROADMAP.md` — checked off Stage 1 items and MatchService

---

## [2026-05-06] — Project initialized

- Created `CLAUDE.md` with game concept, toolchain, folder structure, server/client rules, build order, and Claude behavior guidelines
- Created `docs/PROJECT_RULES.md`
- Created `docs/PROJECT_MAP.md`
- Created `docs/NAMING.md`
- Created `docs/ROADMAP.md`
- Created `docs/CHANGELOG.md`

No game code written yet. Infrastructure and documentation only.
