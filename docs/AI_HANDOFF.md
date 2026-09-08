# AI_HANDOFF.md

Snapshot of work-in-progress for the next AI session. Updated at the end of each session.

---

## Last updated: 2026-09-08

### What was done this session

**Task: Diagnose and fix AKS74 first-person reload animation not visibly playing**

**Diagnosis (source-only, MCP unavailable):**

`PlayReloadAnimation` in `src/client/ViewModelController.lua` used `RBXScriptSignal:Connect()` instead of `:Once()` on both the `tpReloadTrack.Stopped` and `weaponReloadTrack.Stopped` signals. Because these track objects are persistent (loaded once in `_setupWeaponAnimations`, kept alive until `HolsterWeapon` / `StopWeaponAnimations` destroys them), each call to `PlayReloadAnimation` permanently stacked a new Stopped callback. On reload #1 the single callback worked correctly. On reload #2, both callbacks fired: the first cleared `vmLocomotionState` to `""` and resumed locomotion; the second called `SetLocomotionState("")` — an invalid state — corrupting the post-reload resume. Each additional reload compounded the damage.

By contrast, the ADS tracks (`weaponAdsInTrack.Stopped`, `weaponAdsOutTrack.Stopped`) in `SetAiming` already correctly used `:Once()` at lines 2291 and 2344.

**Fix applied:**
- `src/client/ViewModelController.lua` line 1972: `tpReloadTrack.Stopped:Connect` → `:Once`
- `src/client/ViewModelController.lua` line 1988: `weaponReloadTrack.Stopped:Connect` → `:Once`

The connect-before-play ordering (from commit `04a445d`) was preserved.

**Secondary unresolved risk:**
The reload animation ID `rbxassetid://107812216949807` (updated in commit `229bc6e`) has not been verified against the AKS74 viewmodel rig. If it was recorded on a different rig, `LoadAnimation` succeeds silently but the track produces no visible deformation. This requires Studio verification.

**Docs updated:**
- `docs/TECHNICAL_DEBT.md` — DEBT-061 updated with the fix note; DEBT-082 added (Studio verification checklist for sequential reloads and animation ID rig compatibility)
- `docs/CHANGELOG.md` — entry added under 2026-09-08

---

### What still needs Studio verification

See **DEBT-082** in `docs/TECHNICAL_DEBT.md` for the full 8-item checklist.

Quick summary:
1. Press R in play mode → first-person reload animation visibly plays on the AKS74 viewmodel
2. Reload completes → idle / locomotion resumes correctly (no stuck bind pose)
3. Press R again immediately → second reload plays cleanly (primary regression target for the `:Connect` → `:Once` fix)
4. Press R five times sequentially → each reload and locomotion resume are clean (no progressive state corruption)
5. Reload while sprinting → sprint / run animation resumes after reload
6. Reload while in ADS → ADS exits, reload plays, hip idle resumes
7. No `[ViewModelController]` errors in the Output panel during any of the above

---

### Active debt entries touched this session

| Entry | Status | Notes |
|---|---|---|
| DEBT-061 | Updated | Added note that `:Connect` accumulation bug was fixed 2026-09-08; Studio re-verification still required |
| DEBT-082 | New | Reload animation Stopped-callback fix + animation ID rig verification (Studio required) |

---

### Files changed this session

| File | Change |
|---|---|
| `src/client/ViewModelController.lua` | Lines 1972 and 1988: `:Connect` → `:Once` on reload Stopped signals |
| `docs/TECHNICAL_DEBT.md` | DEBT-061 updated; DEBT-082 added |
| `docs/CHANGELOG.md` | 2026-09-08 entry added |
| `docs/AI_HANDOFF.md` | Created (this file) |

---

### What to do next

1. **Studio verification of DEBT-082** — test sequential reloads and confirm the fix works and the animation ID plays visibly.
2. If the animation is invisible even after this fix, the root cause is the animation ID not being recorded on the AKS74 viewmodel rig. In that case: open the animation in Roblox Studio, confirm it is authored for the AKS74 viewmodel skeleton, and re-export if needed.
3. When DEBT-082's checklist passes, mark it RESOLVED and update DEBT-061 accordingly.
