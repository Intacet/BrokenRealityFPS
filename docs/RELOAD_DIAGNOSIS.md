# Reload diagnosis and test instructions

Owner reports that pressing reload neither visibly animates the AKS-74 nor permits subsequent shooting.

## Source findings

- GunController refuses to fire whenever ViewModelController.GetIsReloading() returns true. It sends ReloadRequest, plays reload audio, then calls PlayReloadAnimation.
- SoundController.PlayReload exists and plays the initialized reload sound; there is no confirmed missing-method defect.
- ViewModelController previously set isReloading before playing TP reload, and only cleared it from FP Stopped. TP errors could abort before FP playback/registration. A track that never completes left the fire gate locked indefinitely. Connecting Stopped before Play was already present; repeating that older fix would not resolve the remaining paths.
- WeaponData uses FP reload 107812216949807 and TP reload 82861605710102. IDs alone do not establish permission, successful download, or compatibility with current rig joints. No asset substitution was made.
- GunService immediately transfers ammo on accepted reload; it does not implement a persistent server reload lock. Its AR15 default versus AKS74 client/viewmodel naming remains separate debt.

## Focused local patch

Only runtime changes are in Constants.lua and ViewModelController.lua. FP playback waits for Length > 0, with a three-second loading limit. FP starts before optional TP playback; both Play calls handle errors. A ten-second hard presentation limit recovers a missing completion signal. Stopped/Heartbeat connections are tracked and disconnected on completion, init and weapon cleanup. Server ammo/hits/damage/remotes are unchanged.

These changes fix supported code failure paths. They do not prove the visual asset failure's exact cause. The patch logs asset-loading failure and playback errors through Logger to distinguish them during testing.

## Verification

From the task workspace, run Lune with scripts/Test-Reload.luau under this repository. Thirteen assertions exercise the actual extracted reload method with mocked AnimationTrack and Heartbeat signals: normal completion, spam, repeated reload cleanup, delayed loading, unavailable asset, missing completion, FP errors, TP errors, synchronous completion and model replacement. Full edited runtime files also compile. This is not a Studio or complete Luau type-analysis test.

For Studio, first save a fresh backup and use a disposable copy with its current sources compared against the repo. Apply both edited modules together after reviewing the diff; do not connect the entire baseline project to the city copy. Shoot several rounds, reload, then fire again. Repeat in ADS, with R spam, and after holster/re-equip. Confirm the reload visibly moves arms/magazine and returns to idle. Record Output messages containing "Reload recovered" or "TP reload failed". If the asset fails to load, inspect its permissions and preview that exact animation against the existing R6 viewmodel before changing IDs or joints.

The original place and generated city test were not modified by this task. Studio installation and user-confirmed results remain pending.

## Extended scope — 2026-09-08 (session 2)

Owner re-reported the same symptom ("reload not happening, then the gun doesn't shoot") after this patch had already been written but never installed in Studio or committed. Re-verified the reload patch above by manually tracing all 13 `scripts/Test-Reload.luau` assertions against the current `PlayReloadAnimation` source; all still hold. No behavior change was needed there.

The same structural weakness — a one-shot AnimationTrack whose `Stopped` signal never fires (asset never loads, or a completion signal is dropped) permanently freezing dependent state — also existed in two more places, both now patched with the identical bounded-recovery pattern (Heartbeat watchdog + timeout Constants + tracked connections cleared on weapon switch/holster/respawn):

- **`PlayEquipAnimation` (FP equip).** If the equip asset never loads, the locomotion/idle chain that only ran from `Stopped` would never start, leaving the weapon frozen at bind pose. Recovery now forces that resume after `VIEWMODEL_EQUIP_LOAD_TIMEOUT` (asset never loaded) or `VIEWMODEL_EQUIP_MAX_DURATION` (loaded but never completed) seconds. The existing immediate, unconditional `Play()` call was preserved unchanged — this only adds a safety net, it does not change the success path.
- **`SetAiming` ADS-in / ADS-out.** If `weaponAdsInTrack`/`weaponAdsOutTrack` never fire `Stopped`, `adsState` sticks at `"Entering"`/`"Exiting"`. Because `IsAiming()` is `adsState ~= "Hip"`, GunController would then route every future shot to `PlayADSFireAnimation()`, which itself no-ops outside `"Aiming"` — so the gun keeps firing on the server but shows **no fire animation at all**, a second, independent way to reproduce a "gun doesn't shoot" symptom. Recovery forces the natural transition (`Entering`→`Aiming`, `Exiting`→`Hip`) after the same class of bounded timeout (`VIEWMODEL_ADS_LOAD_TIMEOUT` / `VIEWMODEL_ADS_MAX_DURATION`).

Known gaps intentionally **not** patched this pass (tracked in TECHNICAL_DEBT.md, not blocking):

- Third-person equip (`startThirdPersonEquipSequence`) silently skips the TP equip clip whenever it isn't already loaded at call time (near-always, since loading is async) and falls straight to TP idle. This fails open — no freeze — so it is a missed cosmetic beat, not a lock.
- `weaponEnterRunTrack` (the one-shot Walk/Idle→Run transition) has no timeout, but every other locomotion-state entry already force-clears it (`cancelEnterRun()`), so it can only visibly stick if a player holds Sprint uninterrupted while that specific clip fails to load — narrower and lower-impact than the three paths above.
- GunService applies a reload's ammo transfer immediately on `ReloadRequest` with no server-side reload-duration lock (pre-existing item, unchanged).

None of this — old patch or new — has been installed in Studio or confirmed against the actual AKS-74 animation assets. If reload/equip/ADS still visibly fail to play in Studio after this patch is installed, check Output for `"Reload recovered"`, `"Equip recovered"`, or `"ADS-in/out recovered"` warnings: their presence means the recovery fired (client logic is not the blocker) and the next step is inspecting that specific animation asset's permissions/load in Studio, not further client code changes.
