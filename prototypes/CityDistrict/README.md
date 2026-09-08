# Mercer District — isolated city/destruction prototype

Owner requested a Richmond-inspired map of brick rowhouses, corner shops, warehouses, and alleys, designed for a containment force versus citizens/defenders with PvPvE threats. This is a fictional playable blockout, not a reproduction of a real neighborhood. No external asset downloads are required for the new map geometry.

## Deliverables

- `outputs/CityDistrict/BrokenReality_CityTest.rbxl`: separately generated test place based on the saved Studio baseline.
- `outputs/CityDistrict/BR_CityDistrict.rbxm`: geometry-only model, no embedded scripts.
- `outputs/CityDistrict/DistrictPlan.png`: overhead layout.
- `outputs/CityDistrict/TEST_RESULTS.json`: offline results; not proof of Studio physics or multiplayer success.

Paths above are relative to the original task workspace, not this repository root. The map origin is (10000,100,10000), footprint 730 by 600 studs. There are 26 ground-floor interiors, 2,494 map parts, 132 breakable pieces, 4 spawn markers per team, and 3 objective pads. Upper stories are visual shells, not claimed playable rooms. This is a first district for route and encounter testing, not a finished full-city map or final art pass.

## Layout intent

- Containment stages west; defenders stage east. Permanent screens block direct avenue fire into spawn centers; these are cover, not scripted invulnerability zones.
- A: market junction — street combat, shop fronts and vehicle cover.
- B: residential court — connected back alley, houses and short flank paths.
- C: freight yard — warehouse frontage, side approaches and breakable cover.
- The central avenue is the fast exposed route; rear alleys and pass-through ground floors offer alternatives. Vans interrupt the avenue; offset cross-street screens leave pedestrian bypasses.
- Main doors/alleys have open alternatives. Selected doors and windows can be breached without making destruction mandatory for all routes.
- No high rooftop sniper routes yet. Test ground-level flow before opening elevated positions.
- Existing round/objective code is reused solely to exercise the prototype. No persistent zone, extraction, economy, or creature AI systems are being claimed as implemented.

## Destruction behavior

Only parts beneath BR_CityDistrict with a recognized BR_BreakableProfile attribute are registered. Glass has 20 health, timber 80, light cover 140. Solid buildings, van bodies, spawn screens, and objective plinths stay intact. At the existing server weapon's 28 damage, these take 1, 3, and 5 accepted hits respectively.

The test-only GunService calls DestructionService after its normal phase/ammo/rate checks and server raycast. No new remotes or client-picked damage/targets. Broken parts become non-collidable, non-queryable and invisible on the server, so the result replicates to late joiners too. Bullets do not penetrate a piece during the same shot that breaks it; subsequent shots pass through.

Debris is cosmetic, non-collidable, excluded from raycasts, server-owned, capped at 48 pieces, and removed after 2.5 seconds. Pieces reset on the existing PREP event. There is no timer that unexpectedly rebuilds a door mid-fight. All new event connections are stored and disconnected on cleanup. Core health and material tuning lives in the feature's Constants.lua.

## Preservation / integration

No original place file is overwritten. The builder reads BrokenReality_preRojo.rbxl and writes a different file. In the generated test only, original Workspace objects (except Terrain/Camera) are archived under ServerStorage/BR_OriginalWorkspace_Archive. Their scripts/assets remain there but are no longer active map content. The original place retains its exact hierarchy and behavior. Original terrain remains, far from the new test origin.

The generated copy adds ServerScriptService/CityDistrict, modifies its GunService with two integration insertions, disables its LightingSetup for readable daylight, and supplies new test spawns/objectives. All other migrated source files remain unchanged. The reload animation issue is not fixed by this prototype. Existing networking/round-system debt remains.

These prototype files are NOT mapped by default.project.json or pilot.project.json. Do not connect the existing full Rojo project to this generated test copy: it would restore the baseline GunService and remove the destruction integration. Use the test place as a separate artifact until an explicit integration stage.

## Build and verification

From the original task workspace with Lune 0.10.5:

1. Run `BuildDistrict.luau` using Lune.
2. Run `TestDestruction.luau` using Lune.
3. Open the generated CityTest place in Studio without connecting Rojo.
4. Play, wait for ACTIVE, equip the existing weapon and shoot ground-level windows, timber doors, and crates. Confirm break thresholds, passage after break, intact structural walls, and reset on PREP.
5. Use two Studio clients to verify consistent holes/collision, independent simultaneous hits, and visibility for a late joiner. Profile peak debris and frame rate.
6. Walk intact and broken routes from both spawns to each objective. Record first-contact time, spawn pressure, excessively long sightlines, blocked doors, and whether one team controls all flanks. No competitive balance is claimed until these tests are performed.

Offline tests exercise actual service code with mocked engine signals/network ownership, including invalid hits, damage accumulation, duplicate breaks, debris caps/expiry, reset and connection cleanup. Compilation is a syntax check, not a Luau type-analysis pass or an engine test.

Visual references: [Richmond historic district guidelines](https://www.rva.gov/sites/default/files/2022-04/Old_Historic_District_Guidelines.pdf), [Richmond downtown plan](https://www.rva.gov/sites/default/files/Planning/PDFDocuments/MasterPlan/DowntownPlan/DowntownPlan-July2009.pdf). Server design references: [Roblox raycasting](https://create.roblox.com/docs/workspace/raycasting), [network ownership](https://create.roblox.com/docs/physics/network-ownership).
