# Broken Knight – World Expansion Roadmap

The world should feel continuous to the player while being composed of independently streamable regions. Every region uses the same data contract for terrain, roads, rivers, settlements, encounters, wildlife, secrets, dungeons, loot tables, climate, map layers, and exits.

## Region topology

```text
                         FAR NORTH / GLACIAL RANGE
                                   |
                         NORTH FRONTIER / ALPINE
                                   |
WESTERN REACHES --- STARTING REALM --- EASTERN MARCHES
        |                  |                   |
   STORM COAST         SOUTH LOWLANDS      ASH/VOLCANIC ARC
        |                  |
  OCEAN + DOCKS       DESERT APPROACH
```

This is a topology, not a promise that regions must be square. Streaming cells may overlap and blend in irregular natural corridors.

## Shared region contract

Every region profile should declare:

- identity: `zone_id`, display name, biome, climate, danger tier, recommended level;
- streaming: origin, bounds, exits, preload margins, population budget, revision;
- land: landforms, mountain chains, snow line, palettes, forests, rock families;
- water: watersheds, source type, river corridors, tributaries, ponds/lakes, waterfalls, ocean exits;
- travel: major roads, secondary roads, trails, bridges/fords, destinations;
- settlement sites: reason for siting, usable shelf, connections, architecture set, services;
- content: encounter sites, wildlife zones, resource zones, secrets, lore, dungeons, quests, loot tables;
- map layers: local labels, atlas symbol, map bounds, discovery/reveal policy.

## Streaming rule

1. Keep the current region fully active.
2. Preload neighboring terrain and collision before the player reaches the blend corridor.
3. Stream visuals in bounded jobs over multiple frames.
4. Activate AI and interactables only after terrain/collision are ready.
5. Keep the prior region alive behind the player until safely past the seam.
6. Preserve hero, horse, inventory, quest, weather, and time state across the transition.
7. Unload the far region gradually and pool reusable objects.

No visible door or loading room is required for outdoor transitions. Mountains, valleys, forests, rivers, roads, fog, and sightline occlusion disguise the technical boundary.

## Build sequence

### Phase A – foundation and northern proof

- Formalize biome/climate/danger data.
- Complete local/region/world map scale switching.
- Give Crownfall a visible snowmelt source, tarn/runoff, waterfall, and continuous downstream route.
- Add northern snow caps, conifers/birch, cold ground cover, distinctive rocks, encounters, wildlife zones, secrets, and lore sites.
- Verify seamless mounted travel and eliminate boundary spikes.

### Phase B – useful RPG loops

- Durable ordinary equipment plus unbreakable Royal gear.
- Ring/accessory slots and special effects.
- Repair/crafting/vendor gold sinks.
- Placeable campfires, cooking, food buffs, hunting, and wildlife drops.
- More regional loot tables and meaningful hidden items.

### Phase C – regional content depth

- Distinct enemy family and settlement kit per region.
- Town routines, interiors, services, signs, quests, books, secrets, and dungeons.
- More deliberate action combat and encounter design.
- Coast/docks, ocean danger, and eventual sailing transition.

### Phase D – additional climates

- Glacial far north. **First region implemented 2026-08-23:** Crownfall Glacial Range, Icewatch Hold, Rimegate, Rimewater Glacier/Rimefall watershed, Frozen Observatory, Blue Maw, Frost Troll encounters, wildlife, lore, caches, and a second seamless boundary.
- Eastern marches and volcanic arc.
- Eastern Marches structure and regional visual foundation are implemented; its gameplay chapter, deeper regional content, and broad travel acceptance remain in progress.
- Western reaches and storm coast.
- Southern lowlands and desert approach.
- Connect regional rivers to seas/basins and revise the atlas as each region is authored.

## Expansion progress log

### 2026-08-23 – Crownfall Glacial Range

- Added a third 7.2 km region north of the North Frontier; current atlas footprint is 7.2 km × 21.6 km.
- Generalized the cache-backed staged loader so both northern neighbors use the same region-build path.
- Added a second terrain seam with matched height curves, a continuous Icebound Realmway, and direct destination-region activation for long map teleports.
- Added Rimewater Glacier, Rimefall, a full river corridor, and a boundary-matched tributary into Crownfall.
- Added Icewatch Hold, Rimegate, Frozen Observatory, Blue Maw, camps, wildlife ranges, secrets, lore, and region-specific encounter sites.
- Added the Blender-authored Frost Troll with its own silhouette, procedural locomotion/windup, combat tuning, and drops.
- Added distinct Icewatch and Rimegate architecture/service identities, four functional expedition camps, Frostline Refuge, two survey shelters, and a continuous surface-fitted glacial road network.
- Added the Blender-authored six-legged Rimecrawler, two collidable nesting grounds, grounded carapace loot, stacking Rime Chitin, Rimecrawler Bracers, the Icewatch Signet, and the two-step `Chitin Under Rime` / `Armor for Last Light` regional quest loop.
- Extended map and minimap biome treatment, glacier/crevasse symbols, planned-region survey relief, and regional snow shading.
- Added matching lair symbols to local maps/minimaps and clipped out-of-view settlement, cave, river, service, and landform labels so local surveys no longer inherit unrelated edge text.
- Structural and full runtime tests pass; the measured terrain-seam mismatch is below 0.003 m with zero road/river endpoint gaps.
- Current glacial route benchmark: 171.2 average FPS, 10.36 ms p95, 17.97 ms maximum, and zero frames at or above 25 ms.

### 2026-08-24 – Western Reaches foundation

- Generalized seamless outdoor streaming laterally and added a fourth 7.2 km region west of the Starting Realm without a portal or dismount.
- Reauthored the region rather than rotating a copy: Oakrest, Rainhaven, Stonecross, Galehorn Watch, Old Rainward Abbey, Rainveil Falls, Mossglass Wood, quarry uplands, wildlife ranges, secrets, camps, and regional encounters now have explicit placement reasons.
- Added the continuous Rainfall watershed from Galehorn springs, through Rainveil Falls and Warden's Span, to the storm-coast edge. Terrain bed, visible liquid, bank support, waterfall grade, and bridge sampling now use the same source-to-mouth elevation model.
- Added the Rainward Realmway hierarchy, its one necessary river bridge, terrain-engineered shoulders, gentler authored grades, and a continuous seam connection to the Starting Realm's Western Reach Road.
- Added distinct rainward timber and quarry-stone town layouts, split-rail boundaries, timber yards, a quarry derrick, and Blender-authored Galehorn Watch, Rainward Waystation, and Old Rainward Abbey structures.
- Added regional cloud/fog treatment, denser oak/birch/maple woodland, six specialized vendors, three regional crafting recipes, three cache loot tables, three readable lore records, and the `Bells in the Rain` / `The Abbot's Last Crossing` quest chain.
- World/local map data now includes all four streamed regions, Oakrest as the western gateway settlement, the complete Rainfall river, road hierarchy, bridge, towns, ponds, relief, forests, landmarks, encounters, lore, and secrets.
- Western structural, gameplay, terrain, riverbank, river-cohesion, and bridge tests pass. Current warm Western travel benchmark is 187.7 average FPS, 9.06 ms p95, with one 46.16 ms first-visibility shader warm-up frame still tracked for further removal.

### 2026-08-24 – Stormbreak Highlands

- Filled the middle-west atlas gap with a fifth independently streamable 7.2 km region linking the Western Reaches to the North Frontier.
- Added a shared four-region seam-junction datum system so pairwise seam curves cannot overwrite one another at atlas corners. The measured Stormbreak/Western and Stormbreak/North terrain mismatches are below 0.001 m; the adjacent North/Glacial junction is below 0.003 m.
- Authored Stormbreak Hold, Cairnstead, Moorwatch, three road shelters/camps, Stormscar Beacon, Blacktarn, Galehorn Crossing, the Shattered Choir, forests, moorland, ridges, saddles, valleys, wildlife, secrets, lore, and regional encounter sites.
- Added the continuous Galehorn Run from Blacktarn through the highlands into the Western Reaches' Rainfall River, with one necessary supported bridge and exact road/river endpoint continuity across both region seams.
- Added a distinct highland architecture set and Blender-authored beacon, enterable road shelter, and ruined choir kit rather than reusing lowland town silhouettes.
- Added seven regional vendors/services, three regional crafting recipes, unique equipment/material loot, readable lore, and the `Fire on Stormscar` / `The Hymn Beneath Thunder` quest pair.
- World atlas, region map, minimap, teleport loading, geographic activation, atmosphere, collision, encounter activation, and return travel all include Stormbreak.
- Structural, full-runtime, gameplay, glacial-regression, Western-regression, and bridge-network tests pass. The warm Stormbreak route benchmark is 142.6 average FPS, 12.32 ms p95, 14.82 ms p99, and zero frames at or above 25 ms; a first-ever renderer/shader warm-up remains visible on a cold run and is tracked rather than hidden.
- The atlas now covers five authored regions in a 14.4 km × 21.6 km footprint. The only empty cell in the current two-by-three world block is the far northwest, reserved for a subarctic coast that will connect Stormbreak, Crownfall, and the ocean.

### 2026-08-24 – Skeld Coast and completed six-region block

- Filled the far-northwest atlas cell with the independently streamed Skeld Coast, completing the current two-by-three region block while retaining the 14.4 km × 21.6 km world footprint.
- Reused the shared four-region seam-junction datum so Skeld connects south to Stormbreak and east to the Glacial Range without a portal, wall, dismount, or terrain crack. Measured mismatch is below 0.005 m on both borders.
- Added the Grey Sea as the first ocean basin: a smoothed authored coastline, broad physical shallow shelf, deep blocked water, underwater terrain, subtle broken foam, local/world-map sea rendering, and an exact Skeld River mouth.
- Added the continuous Skeld River from Rimeglass Tarn and Rimeglass Fall through Frostharbor to Skeldmouth, with one necessary coast-road bridge and no duplicate or accidental water crossings.
- Authored Frostharbor, Vardholm, Kelpwick, Cape Keld Light, Whalebone Chapel, Rimepass shelter, South Cove camp, two ponds, coastal ridges, raised beaches, tundra, salt moor, forests, wildlife, secrets, and five regional encounter grounds.
- Added the `skeld_coast` architecture identity with 45 coastal houses, fish/net yards, sea-stone boundaries, three unique longhalls, and Blender-authored lighthouse, working pier, ruined chapel, and two tapered fishing boats with sails, mast, oars, cargo, collision, and distinct placement.
- Added eight coastal merchants/services, three Skeld recipes, regional cache/monster loot, three readable lore records, and the linked `Light Against the Grey` / `The Bones Remember` quest chapter.
- Added six-region world/local maps, coastal relief, shoreline and ocean rendering, town/road/river/landmark data, teleport loading, maritime atmosphere, gameplay activation, and seamless return travel.
- Structural, gameplay, full-runtime, rendered-content, glacial-regression, Stormbreak-regression, and bridge-network tests pass. The worst sampled shoreline terrain/water difference is 0.91 m across coarse triangles; the authored river/sea datum mismatch is 0.00 m.
- The accepted Skeld harbor-road benchmark restores the proven rendering path at 94.6 average FPS and 6.86 ms median on the RTX 2080 test machine. A proposed whole-town mesh batch was rejected and reverted after it reduced performance. First-visibility uploads still raise p95 to 23.27 ms and remain the next tracked optimization target.

### 2026-08-24 – Starter-world boot bake

- Added a compressed, pre-baked starter-realm population scene while preserving the complete procedural population builder as a safe fallback.
- Terrain and collision remain generated from the authoritative cached heightfield; rivers, roads, bridges, vegetation, props, architecture, collisions, doors, horses, torches, and gathering registries load from the bake.
- The bake stores stable paths for batched tree/ore render parts and resolves them after loading. Individual tree chopping was reverified with 7,926 registered trees, neighboring instances unchanged, and physical log drops intact.
- A SHA-256 source signature covers `WorldProfile.gd`, `TerrainBuilder.gd`, and `WorldPreviewBuilder.gd`. A missing or stale bake automatically falls back to procedural construction rather than loading mismatched world data.
- Rebuild command after authored starter-layout/builder changes: run Godot headless with `--script res://tools/build/build_starting_world_visual_bake.gd`. Imported mesh and texture reimports remain external and do not require a layout bake.
- Boot-flow time on the RTX 2080 test machine improved from roughly 13.0 seconds to 5.1 seconds. The Riverwatch travel benchmark now measures 121.9 average FPS, 16.89 ms p95, and one 29.04 ms first-visibility frame.
- A direct baked/procedural Riverwatch capture produced the same visible world composition; solid-world, starter-region, boot-flow, and individual-tree tests pass.

### 2026-08-25 – Eastern Marches foundation (structure, visual foundation, and first gameplay loop accepted)

Done:

- Added the seventh independently streamable 7.2 km region east of the Starting Realm. The atlas now covers 21.6 km × 21.6 km without a portal, loading door, terrain wall, or forced dismount.
- Authored Dawnford, Amberfield, March Keep, Saltwatch, Embercrag, Cinderwatch, Glassmere, Ashstep Falls, camps, forests, ecology, wildlife, secrets, lore sites, and five regional encounter grounds with explicit terrain and travel reasons.
- Added the Dawnway major realmroad, Saltwatch secondary market road, Glassmere survey road, and three local tracks. The measured worst authored road grade is 0.131 and all settlement centers remain dry.
- Added the coherent Emberwash watershed, Glassmere tributary, and Redstone headwater. Both rivers that reach Riverwatch continue through the zone seam at exact matching endpoints and water datums.
- Added shared river-crossing seam metadata to terrain generation. The complete Starting Realm/Eastern Marches terrain boundary now differs by at most 0.00067 m, including both riverbeds and banks, rather than hiding cracks with overlap meshes.
- Kept Ember Span as the sole major-road bridge and authored Saltmeadow Bridge as the smaller necessary market-road crossing. A former Saltwatch route crossed the tributary twice; that route was rejected and replaced with a watershed-aware contour route.
- Added full local, region, minimap, atlas, and teleport representation for all seven regions, including Eastern roads, rivers, towns, lakes, crossings, relief, and regional sites.
- Runtime acceptance now verifies seam traversal, 60 marcher houses, both authored bridges, three waterways, all road tiers, mounted round-trip travel, encounter/vendor activation, quest-state preservation, and the seven-region atlas.
- Rebuilt and signature-validated the optimized starter population bake after the shared terrain/profile changes. Existing starter terrain, river cohesion, bridge placement, and terrain integrity regressions still pass.
- Added the Blender-authored Eastern environment kit with March Keep fortification, Dawnford caravanserai, Amberfield windmill, Saltwatch granary, Cinderwatch beacon, and Embercrag basalt crown. All six regional identities are grounded, collidable, and distance culled.
- Replaced generic Eastern settlement presentation with 60 marcher-stone/marcher-timber houses, 30 terracotta hipped roofs, joined gables, limestone/plaster walls, dark oak, market awnings, and four settlement boundary treatments.
- Added continuous terrain-palette regions for Dawnway loess, amber grassland, Emberwash alluvium, Cinderwatch basalt, and Glassknife chalk, plus denser batched meadow cover and deliberately placed regional groves.
- Rebuilt Glassmere with a 660-vertex irregular water perimeter, a smooth collision-free shore transition, adaptive reeds, willow dressing, and river-bank mouth tapers. The Glassmere Shore Path now curves to and stops on its walkable west bank instead of extending into the lake.
- Added subtle in-world hierarchy to the shared compacted-earth road palette: major roads read cleaner and lighter than secondary roads while retaining compatible junction colors. Road hierarchy, town travel, riverbank contact, and starter-region regressions pass.
- Added bounded offscreen rendering for newly streamed regions and tightened cardinal preload corridors. Cinderwatch no longer triggers the unrelated North Frontier loader, and the starter spawn no longer immediately builds the Western Reaches.
- Replaced the stale starter visual fallback with a current 12.01 MB signature-valid bake containing 30,800 visual nodes. Runtime verification now reports `status=loaded`.
- Current Cinderwatch rendered benchmark on the RTX 2080: 5.19 ms median and 16.76 ms p95 on immediate arrival with one frame above 25 ms; after normal settling, 4.46 ms median, 15.62 ms p95, and zero frames above 25 ms.
- Completed the first Eastern-specific gameplay/content loop: nine regional vendor/service roles, three useful recipes, distinct loot for all three Eastern cache families, three readable lore records, and two linked Marcher quests with authored rewards.
- Added the Blender-authored Ashscale Basilisk as Cinderwatch's distinct regional predator, including a custom silhouette, articulated gait/jaw/tail motion, encounter placement, progression counters, materials, and grounded regional drops.
- The dedicated Eastern gameplay verifier passes with 101 hostiles across 14 types, five Ashscale Basilisks, nine vendor roles, both linked quests, all recipes, and no failures. Western, Stormbreak, Skeld, and Oathbound gameplay regressions also remain green.
- Added Cinderwatch's connected Signal Yard, survey shelter/work furniture, beacon piers and bond bands, sunwashed-basalt shelves, outcrops, and fireweed so the beacon reads as an occupied destination rather than an isolated dark tower.
- Added Glassmere willow groupings, wet-meadow ecology, and authored rock groups. A narrower procedural shoreline experiment exposed coarse land wedges and was rejected; the accepted smooth 660-vertex shore geometry remains in place.
- Repaired the four-region lateral seam's first interior terrain rows after slope stabilization. The previously measured 8.553 m corner-approach step is now 0.131 m, while the actual boundary mismatch remains 0.00000 m; terrain, river, bridge, town-travel, and starter regressions pass.
- Replaced runtime world-atlas height surveying with a generated 512 px cartographic relief asset while retaining live roads, rivers, towns, forests, services, discoveries, and player direction. Regional map drawing now excludes only off-screen regions and uses a cheap dynamic overlay for tooltips/teleport aiming.
- On the RTX 2080 test machine, a same-region map teleport improved from 3.82 seconds to 0.32 seconds in the final seven-target suite. All seven destinations pass: cold remote transitions are now 1.72–1.91 seconds instead of 54–57 seconds, and the worst first playable frame was 27.77 ms.
- Batched the individually choppable town-avenue trees and divided streamed transport construction by authored corridor/water site. The Eastern town-outskirts population job fell from 532.8 ms to 18.6 ms; remaining first-time corridor upload spikes continue to be tracked.
- Added signature-checked generated visual scenes for all six streamed regions: North Frontier, Glacial Range, Western Reaches, Stormbreak Highlands, Skeld Coast, and Eastern Marches. They retain population-root registries and full road/river/town/prop/collision content while replacing roughly one hundred procedural streaming jobs per region.
- The accepted single-scene Eastern bake is 5.20 MB with 15,519 nodes; its measured region build fell from 4.95 seconds to 1.08 seconds and the focused teleport to 1.92 seconds. A proposed multi-file chunk format reduced its largest instantiate slice to 25 ms but caused a Godot dummy-renderer RID crash in headless validation, so it was rejected, reverted, and its failed generated chunks were removed.

Still needed:

- Build authored player-height compositions around Dawnford's arrival, Amberfield's fields, March Keep's gate, Saltwatch's work yards, and Cinderwatch's survey camp without filling the deliberate long-distance grassland views.
- Continue reducing the accepted streamed-bake instantiation slice (about 118–135 ms for the largest Eastern scene) without reintroducing the rejected chunk-resource crash or thinning accepted world detail. It currently occurs during far-ahead preload or beneath the paused teleport map.
- Repeat natural mounted seam approaches for every baked region; the full seven-destination teleport suite passes, but real movement is the acceptance test for whether ahead-of-player bake instantiation is unobtrusive enough.
- The immediate Cinderwatch p95 is within 0.09 ms of the strict 16.67 ms threshold and remains tracked rather than rounded down.

## Performance budgets

- Gameplay target: 60 FPS.
- Avoid synchronous region construction or resource loading in the movement frame.
- Ship the valid starter population bake and retain signature-checked procedural fallback.
- Share materials and meshes; use MultiMesh for passive scatter.
- Use distance tiers for AI, wildlife, particles, shadows, lights, grass, and animation.
- Limit active thinking enemies/wildlife to the player's encounter neighborhood.
- Ship the generated world-atlas terrain relief; regenerate it through the map capture tool after structural terrain/profile changes instead of surveying 262,144 terrain points when the player opens M.
- Ship signature-valid generated visual scenes for every streamed region and rebuild them after changes to the world profile, terrain builder, or preview builder; retain the procedural fallback for stale/missing bakes.
- Profile every new biome on foot, mounted, teleporting, inside settlements, and at seams.
