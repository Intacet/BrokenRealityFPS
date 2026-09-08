# Technical debt and unresolved migration questions

## Reload recovery patch

Local code addresses an indefinite client reload lock and TP playback preventing FP playback. Visual asset load/permissions and joint compatibility remain unconfirmed in Studio. See RELOAD_DIAGNOSIS.md; no animation asset ID was changed. User testing and source reconciliation before installation are pending.

## Animation lock recovery — equip / ADS (new, not yet Studio-tested)

Same bounded-recovery pattern as the reload patch, applied to `PlayEquipAnimation` and to ADS-in/ADS-out in `SetAiming`. See RELOAD_DIAGNOSIS.md "Extended scope". Not installed in Studio; visual asset load/permissions remain unconfirmed there, same as the reload patch.

Two related gaps were found but intentionally left unpatched this pass (lower impact, no permanent lock):
- Third-person equip (`startThirdPersonEquipSequence`) skips the TP equip clip whenever it isn't already loaded at the moment `EquipWeapon` calls it (near-always, since asset loading is asynchronous) and falls straight to TP idle — a missed cosmetic beat, not a freeze.
- `weaponEnterRunTrack`'s one-shot Walk/Idle→Run clip has no completion timeout; it can only visibly stick if a player holds Sprint uninterrupted while that specific clip fails to load, since every other locomotion-state entry already force-clears it via `cancelEnterRun()`.

## Server-side reload has no duration lock

`GunService` transfers ammo immediately on `ReloadRequest` with no persistent server-side reload-duration lock, independent of client animation timing. A player could in principle spam `ReloadRequest` to top up ammo instantly regardless of the client's reload animation length. Not addressed by the client-side animation-recovery patches above — this is a server balance/exploit question, not an animation bug, and needs an explicit decision before any server-side reload-lock remote/logic change (no new remotes without explicit request).

The initial migration questions below are historical; see dated findings and SCRIPT_INVENTORY.md for inspected source. Do not treat unresolved questions as confirmed defects.

| Item | Status | Next step |
| --- | --- | --- |
| Complete script inventory and dependencies | Unknown | Inspect Studio Explorer and sources |
| Missing strict mode or legacy print/warn/wait/spawn | Not assessed | Record during verbatim capture; fix separately |
| Gameplay magic numbers | Not assessed | Review later for Constants.lua |
| Server authority and remote validation | Not assessed | Review one system at a time later |
| RBXScriptConnection cleanup | Not assessed | Review later |
| R15/SCAR legacy references | Not assessed | Record occurrences without assuming current direction |
| Script children, attributes, tags, RunContext, package behavior | Unknown | Capture before any sync mapping |
| Asset IDs, ownership/access, unpublished animation work | Unknown | Inventory and back up in Studio |

Do not create replacement systems to resolve speculative debt. Preserve baseline behavior during migration.

## City prototype — 2026-09-08

- Reload animation does not visibly play according to the owner; deferred, not repaired by the map work.
- Mercer District is a first blockout: upper floors are shells, terrain is flat, props are simple, and spawn/objective balance is untested. No new creature AI or zone persistence was added.
- Destruction passed 22 offline checks, but engine physics, multiplayer replication/late join, passage through breaches, reset behavior, and performance still need user-confirmed Studio results.
- Existing AR15 server weapon and AKS74 viewmodel naming/configuration differ; keep this separate from city integration.
- Generated test-copy GunService integration is not represented in src or Rojo mappings. Connecting baseline default.project.json to the city copy would revert that integration.
- New map artifacts are stored separately from Git. The generator is backed up in Git, but rebuilding the complete test requires the separately preserved original place file.
