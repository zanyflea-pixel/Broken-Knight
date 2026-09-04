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

Priority override (2026-08-27): swimming and ocean-danger polish is the lowest-priority backlog item. A basic functional layer may remain, but no additional swimming work should interrupt visible world construction, regional content, maps, travel logic, or performance.

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
- Corrected the map-teleport suite so its North and West cases land on the actual Pinewatch and Oakrest settlement shelves rather than mislabeled starter coordinates. On the RTX 2080 test machine, the latest verified seven-destination run measures 0.148 seconds for the starter jump and 0.67–1.04 seconds under the paused map for remote cold preparation, down from the earlier 3.82-second same-region and 54–57-second cold-remote paths. Every first controllable frame passes the 34 ms budget; the measured worst is 16.82 ms.
- Batched the individually choppable town-avenue trees and divided streamed transport construction by authored corridor/water site. The Eastern town-outskirts population job fell from 532.8 ms to 18.6 ms; remaining first-time corridor upload spikes continue to be tracked.
- Added signature-checked generated visual scenes for all six streamed regions: North Frontier, Glacial Range, Western Reaches, Stormbreak Highlands, Skeld Coast, and Eastern Marches. They retain population-root registries and full road/river/town/prop/collision content while replacing roughly one hundred procedural streaming jobs per region.
- The accepted single-scene Eastern bake is 5.20 MB with 15,519 nodes; its measured region build fell from 4.95 seconds to 1.08 seconds and the focused teleport to 1.92 seconds. A proposed multi-file chunk format reduced its largest instantiate slice to 25 ms but caused a Godot dummy-renderer RID crash in headless validation, so it was rejected, reverted, and its failed generated chunks were removed.
- Serialized streamed terrain/bake installation and prevented it from overlapping GameplayDirector's regional service rebuild. Rapid cross-world map jumps no longer interleave renderer-resource construction, and map travel now activates the destination tile directly so enemies, services, atmosphere, and maps cannot remain one region behind the hero.
- Tightened north-west preload logic: Pinewatch no longer loads Stormbreak merely because it lies slightly west of the atlas centerline, and the central Glacial corridor no longer loads Skeld. A North map jump that lands beyond the Glacial preload line prepares that northern neighbor beneath the opaque map instead of dropping its terrain cache onto the first walking frame.
- Made baked-world interaction groups persistent and rebuilt the starter plus all six streamed visual scenes. Rideable horses, house doors, castle ladders/stairs/lookouts, and town-torch registries now survive generated-scene loading; the mounted North runtime test is green again.
- Fixed perpendicular corner-repair passes overwriting a neighboring region's owned boundary column. The real Starting Realm/Western Reaches runtime seam improved from a visible 0.54662 m mismatch to 0.00006 m without an overlap skirt or hidden collision patch.
- Formalized the automatically detected Skeld Pass Road crossing as the narrow `Blacktarn Runoff Bridge`, with authored purpose and map data, instead of leaving an unexplained second bridge near the headwater.
- Rebuilt the shipped atlas relief with continuous world-space climate color, irregular survey-paper feathering around the seven authored regions, and relief-height feathering that removes false square cliffs at the edge of the current footprint. The live map still opens from the generated 512 px asset with zero terrain-survey frames.
- Final acceptance after these changes passes starter-region, terrain-integrity, bridge-network, river-cohesion, riverbank-contact, North mounted runtime, Western runtime, Glacial runtime, Stormbreak runtime, Skeld runtime, and Eastern runtime checks. Measured runtime seam gaps are 0.00006 m west and 0.00417 m east.
- Added signature-validated engineered-route cache bakes for all seven regions. The exact road-grade/shoulder solver data is now loaded rather than recomputed during travel: its measured streamed-region cost fell from 97–178 ms to 5.8–8.8 ms, and total cache-backed terrain creation fell from roughly 121–184 ms to 19–25 ms.
- With the route caches and rebuilt signed visual scenes, the seven-destination suite measured 0.148 seconds in the starter area and 0.67–1.04 seconds for cold remote preparation beneath the map; the worst first controllable frame was 16.82 ms.

### 2026-08-27 – Natural-travel streaming and horse interaction

- Added a mounted northbound stress benchmark that follows the actual preload/activation route at roughly six times the fastest horse's normal per-frame travel. The original accepted world still exposed one 212.08 ms natural-travel frame even though teleporting was covered by the map.
- Moved streamed terrain construction and packed visual-scene instantiation onto serialized off-tree workers. Live-tree entry now keeps each authored house, collision assembly, road, river, and prop intact while registering oversized population containers in bounded batches well ahead of the seam.
- Reconstructed the large harvestable-tree, ore, and prop-collision metadata registries in frame slices instead of copying more than 20,000 nested values in one completion frame. Map-covered teleports use larger safe slices while natural travel uses conservative slices and rest frames.
- Removed the redundant remote-region gameplay registry scan. Gameplay services rebuild only when their region becomes active, and encounter populations plus dungeon construction are divided across transition frames.
- The accepted northbound mounted stress run now measures 14.26 ms p95, 19.93 ms p99, and 30.70 ms maximum with zero frames at or above 34 ms. The horse remains mounted and `north_frontier` becomes the active gameplay region.
- Fixed starter-horse access from the stable aisle. The old 1.8 m interaction sphere ended inside the stable rail; the usable radius is now 4.5 m and E interaction also discovers newly streamed horses directly from their persistent group. Runtime verification finds all three horses, shows `E — Ride Bracken`, mounts, and dismounts without failure.
- Re-ran starter terrain, four-river cohesion, riverbank contact, all seven rendered bridges, all six streamed-region runtimes, east/west terrain seams, mounted persistence, encounters, vendors, and atlas registration. All pass; the isolated lateral seam remains exact at 0.00000 m with a 0.036 m maximum 45 m approach step.
- Generalized natural mounted acceptance to every streamed direction. Accepted p95/p99/maximum frame times are: North 13.91/21.75/30.21 ms, West 13.60/18.66/29.17 ms, East 13.85/21.00/30.00 ms, Glacial 13.37/17.76/30.63 ms, Stormbreak 13.55/20.11/26.21 ms, and Skeld 13.53/17.95/27.32 ms. Every route has zero frames at or above 34 ms, preserves the mount, and activates the intended region.
- Split each streamed 321×321 physics heightmap into four exact overlapping 161×161 quadrants registered on separate frames. Their physical extents and shared height rows match at 0.00000 m, removing collision-registration spikes without reducing terrain collision resolution.
- Added a paused-map fast path after natural travel was proven. The latest seven-destination run prepares ordinary remote destinations beneath the map in 0.91–1.05 seconds, the chained Pinewatch/northern preparation in 1.52 seconds, and its already-warm Glacial follow-up in 0.29 seconds. The worst first controllable frame is 16.79 ms.
- Added state-preserving visual residency. Regions more than 2.5 km behind the active tile suspend rendering and inherited scripts while retaining nodes, physics, felled-tree/door/discovery state, and generated resources; they wake 1.6 km before re-entry. Starter-to-North-to-starter verification preserves the harvest registry and restores the correct visible tile.
- Restricted harvestable-tree, mineable-rock, and local prop-collision registries to the active region rather than rescanning all previously visited tiles. This prevents interaction setup cost from growing with exploration while preserving the current tile's full gatherable content.
- Full-atlas long-session acceptance loads all six streamed regions, resumes mounted play in central Skeld, and confirms that only Skeld remains visually/process resident there while the starter and five distant regions sleep. With every current region retained in memory, the 360-frame headless movement sample measures 12.05 ms p95, 16.67 ms p99, and 22.29 ms maximum.
- Completed the Eastern Marches player-height composition pass without filling its deliberate grassland vistas. The Blender-authored kit now adds a wheeled Dawnford caravan/ledger stop, Amberfield field gate/tools/sheaves, March Keep gate braziers and guard furniture, Saltwatch salt-drying yard, and Cinderwatch survey instruments, packs, flags, and table. All five compact scenes are grounded, collidable, placed off the travel lanes, and verified in the live streamed region.
- Repositioned the Dawnford, Amberfield, and Saltwatch sets after rendered close-up review found the first placements obscured by houses or settlement fences. March Keep and Cinderwatch were retained after review because their approaches read cleanly and kept the road/open upland views intact.
- Rebuilt the starter and all six streamed visual scenes with current signatures. Eastern verification reports 51 source-kit surfaces, six distant identities, five player-height compositions, 60 marcher houses, 30 hipped roofs, four settlement boundaries, and zero failures.
- Fixed active-region residency wake-up during direct map/test travel. A preloaded tile that had slept while the player was far away now becomes visible immediately on activation instead of waiting for the next 0.22-second streaming poll and briefly showing empty sky.
- Fixed a rendered-runtime wildlife animation type error exposed during visual review; the final capture produces all five acceptance frames without script errors.
- The seven-site rendered Eastern benchmark now measures 3.84 ms median, 6.07 ms p95, 7.22 ms p99, 13.52 ms maximum, and zero frames over 25 ms. Cinderwatch specifically measures 5.29 ms p95 and 5.99 ms p99, clearing the previously tracked near-threshold result. The latest mounted natural East approach remains green at 13.62 ms p95, 19.97 ms p99, 32.20 ms maximum, zero 34 ms spikes, correct regional activation, and mount preservation.
- Completed the previously missing rendered atlas-memory profile on the RTX 2080 target machine. After every current region was loaded, rendered, revisited, and retained, Godot reported 1,089.8 MB static memory (1,094.5 MB peak) and 625.0 MB total rendering-device memory: 316.3 MB textures and 247.5 MB buffers. The six streamed tiles add about 561.6 MB of retained static memory over the 528.1 MB warm starter baseline, while texture memory stays essentially flat because assets/materials are shared.
- The extended all-region rendered revisit retained the mount, kept only the active Eastern tile visible, and measured 17.38 ms p95, 22.61 ms p99, and 28.34 ms maximum. On this target, full state-serialized unloading is not justified by current RAM/VRAM pressure; the existing state-preserving visual/process suspension remains the accepted design. Re-profile after substantial new-region growth or on a future lower-memory minimum-spec target before adding unloading complexity.

### 2026-08-27 – Regional road wayfinding

- Replaced the same hard-coded Riverwatch destination board appearing in every biome with signs derived from each settlement's authored connection graph. The complete atlas now has 24 settlement-approach signs and 57 directional arms across all seven regions.
- Destination arms physically point toward their named place and include metres or kilometres. Their words exist only on the intended front face; the back remains wood instead of mirrored text, billboarded text, or text visible through the board.
- Scaled the first implementation down after player-height captures showed billboard-like proportions. The accepted signs use a compact post, stone foot, solid collision, modest arm spacing, and region-aware lettering while remaining readable from the road approach.
- Added automated bake verification for regional counts, labels, distances, front/back configuration, collision, and removal of the obsolete universal board. It passes with zero failures; four in-engine captures verify temperate, rainward, glacial, and eastern approaches.

### 2026-08-27 – River surface motion and depth readability

- Split moving river water from still-water behavior. River ribbons now use their existing source-to-mouth V coordinate for downstream travelling waves and broken current strands, while ponds and ocean surfaces retain non-directional motion.
- Reinforced the physical depth-buffer result with a modest cross-channel depth profile so shallow margins and the deeper center remain readable even over coarse terrain triangles. Displacement remains pinned at the banks and water geometry/height was not widened or raised.
- Preserved the existing waterfall/shore system: 13 verified river surfaces, 14 still-water surfaces, 30 cascade sheets, and 7 foam pools across the current atlas. River continuity, bank contact, and waterfall grades all report zero failures.
- Re-captured the Kingsflow surface at two animation times plus both starter falls. The final starter-road performance run measured 4.59 ms average, 6.50 ms p95, 7.76 ms p99, and 13.20 ms maximum with no frames above 25 ms.

### 2026-08-27 – Primary objective navigation

- Added a single authoritative primary-objective selection to the gameplay director. Both active story chains remain mapped, but only the current quest-order objective receives strong navigation treatment.
- The detailed map now distinguishes the primary objective with a larger double diamond while secondary story objectives remain subdued and discoverable. Hover details identify the active objective without drawing a route line across the world.
- Moved live objective guidance into the minimap's uncached overlay. Nearby objectives receive a compact double diamond; offscreen objectives receive one edge arrow and a metre/kilometre readout. The first capture exposed an overlap with the 250 m scale bar, so the distance label was moved inward and recaptured cleanly.
- Automated acceptance confirms two active story objectives, exactly one primary marker, and working edge guidance. The final starter benchmark measured 4.76 ms average, 7.36 ms p95, 8.60 ms p99, and 14.85 ms maximum with no frames above 25 ms.

### 2026-08-27 – Functional regional interiors

- Expanded the Blender-authored architecture detail kit with a stocked bookcase, working kitchen, artisan workbench, tavern counter, guard station, and writing desk. The imported sets preserve their individual materials while loading as one draw-friendly mesh per composition.
- Assigned interiors by building purpose instead of repeating the same table in every shell: cottages receive kitchens, alehouses/inns receive serving bars, workshops receive visible tools, merchant buildings receive stocked shelves, and townhouses receive writing desks. All six authored house roles remain represented.
- Added simple collision bounded to the visible footprint of each large composition, while keeping house doors, ground-floor aisles, and upper stair exits clear. The castle now adds a stocked archive, entrance watch post, council writing desk, and armory workbench without obstructing its central route.
- Rendered close-ups caught a cottage chest crowding the new kitchen; it was moved to the side wall before acceptance. Verification reports 46 filled bookcases, 17 kitchens, 17 workshops, 29 tavern/inn bars, one castle guard post, 13 writing desks, 123 collision-aware compositions, six house roles, and zero missing meshes or failures.
- Rebuilt the starter and all six streamed visual bakes. The accepted starter route measures 4.44 ms average, 6.13 ms p95, and 12.22 ms maximum; Crownspire measures 6.82 ms average, 16.56 ms p95, and 23.61 ms maximum, retaining the 60 FPS target at the dense castle composition.

### 2026-08-27 – Regional geology landmark families

- Added a reusable Blender geology kit with four genuinely different silhouettes: a continuous stratified escarpment, columnar basalt wall, snow-capped glacial crag, and open wave-cut coastal arch. The first layered-cliff attempt looked like a pile of blocks and the first coast piece read as a generic rock blob; both were rejected and rebuilt before acceptance.
- Placed 55 sparse formations across the seven authored regions from mountain-chain and landmark data rather than random scatter. Placement clears roads, rivers, ponds, bridges, and towns; samples the full footprint; rejects unsuitable slopes; seats at the lowest sampled terrain point; and uses one simple collision box per formation.
- The accepted distribution is 34 layered cliffs, 6 basalt escarpments, 12 glacial crags, and 3 coastal arches. All are MultiMesh-batched by 620 m cells with 1.5 km visibility range, preserving distant landmark readability without creating a dense rock grid.
- Rebuilt the starter and all six streamed visual bakes. Geology, terrain-integrity, riverbank-contact, and road-hierarchy verification all pass with zero failures, and full boot reaches 100% in 4.42 seconds.
- Rendered RTX 2080 acceptance measures 4.72 ms average / 7.22 ms p95 in the starter region and 5.38 ms average / 15.16 ms p95 through the Glacial Range, both with zero 25 ms spikes. Two early Eastern Cinderwatch runs intermittently produced a 25–30 ms frame near the older signal-yard composition; a targeted geology-shadow experiment did not help and was reverted. The visibility trace showed periodic map/main-viewport draw-count changes rather than a geology activation, and the clean follow-up measured 5.18 ms average / 15.13 ms p95 / 21.34 ms maximum with zero 25 ms spikes. Keep Cinderwatch on the performance watch list rather than weakening the accepted formations.

### 2026-08-27 – Geology cartography and Eastern minimap correction

- Replaced the detailed map's generic three-rock outcrop glyph with four compact silhouettes matching the accepted geology families: layered strata, basalt columns, snow-capped crags, and open coastal arches. Major authored geology appears on the minimap without labels, circles, or extra explanatory panels; ordinary rock scatter remains unmarked.
- Added `landmark_sites` to the world-map static signature so structural landmark edits invalidate the cached cartographic layer correctly.
- Visual review of Cinderwatch exposed an older coordinate shortcut that treated every position beyond world X=7800 as a dungeon. The seamless Eastern Marches occupy that same range, so their minimap incorrectly rendered Barrowfen Ossuary. Dungeon selection now follows the hero's authoritative interior-mode state instead.
- Surface and dungeon verification both pass, as does the 512 px full-screen map with all four geology families. The recaptured Cinderwatch minimap shows the real terrain, Emberwash, Dawnway road, player facing, and basalt formations.
- With the actual Eastern minimap workload restored, Cinderwatch measures 5.28 ms average / 14.97 ms p95 / 20.01 ms p99; one intermittent 27.13 ms frame remains on the watch list. Starter measures 4.70 ms average / 6.90 ms p95 / 13.76 ms maximum with no 25 ms spikes.

### 2026-08-27/28 – Embercrag volcanic ecology

- Added a reusable Blender-authored volcanic kit with six player-height families: a broad fractured cooled-lava shelf with longitudinal flow ropes, an irregular glassy obsidian fan on a shattered basalt base, eroded fumarole mounds with dark throats and restrained mineral deposits, charred split-trunk snags, hardy ash scrub, and fireweed patches.
- Rejected the first rendered kit because its lava ridges read as exposed hoops, its obsidian was a row of primitive cones, and its vents resembled small pots. The rebuilt silhouettes use continuous fractured surfaces and irregular authored mesh construction instead.
- Rejected the first charred snag because its perfect cylindrical trunk and broad material band read as constructed geometry. The accepted snag has a roughened taper, broken crown, forked limbs, and narrow vertical bark weathering. Ash scrub and fireweed were retained after close rendered review.
- Placed 81 features around Embercrag: 5 lava shelves, 7 obsidian clusters, 5 fumarole fields, 16 charred snags, 22 ash-scrub clusters, and 26 fireweed patches. All placement is deterministic, MultiMesh-batched, and clears rivers, roads, trails, ponds, bridges, and settlements.
- Corrected steep-slope seating after rendered review exposed lowest-corner anchoring burying most of the vents and shelves. Every formation now fits the sampled local terrain plane, stays embedded without floating, and keeps collision aligned to the visible slope.
- A flower capture exposed radial candidates beyond Embercrag's southeast terrain edge: the height sampler clamps outside the tile even though no mesh exists there. Volcanic placement now rejects a 120 m playable-edge margin, and automated verification confirms all 81 accepted transforms are over real terrain.
- Added a 1.394 km landform-scale ash/basalt apron around the authored Embercrag center. Rotated macro fields warp two broad radial fades, so charcoal stone, gray-brown ash, and restrained oxidized grit merge gradually into the existing March loess rather than creating a circular decal or hard biome line.
- Rebuilt the starter and all six streamed visual bakes. Volcanic ecology (including exact apron center/radius), regional geology, terrain integrity, river cohesion, riverbank contact, and road hierarchy all pass with zero failures; full boot reaches 100% in 4.22 seconds.
- The first post-vegetation Eastern run remained fast at 5.08 ms average / 16.53 ms p95 but showed three intermittent 25–28 ms Cinderwatch frames. A visibility-traced follow-up cleared them, and the final baked terrain-apron run measures 5.02 ms average / 14.85 ms p95 / 23.86 ms maximum with zero 25 ms spikes. Cinderwatch remains on the existing watch list; no accepted ecology geometry was weakened.

### 2026-08-28 – Embercrag cartography

- Added the same broad volcanic apron to the local and regional illustrated maps as six restrained irregular ash layers with broken radial fissure strokes. It sits below roads, rivers, settlements, and labels, communicates volcanic ground visually, and adds no legend or explanatory panel.
- Added a cratered mountain silhouette for Embercrag on both the detailed map and fixed-orientation minimap. The first capture put the hero directly over the symbol, so acceptance was recaptured from the western apron where the volcano, terrain footprint, river approaches, and route hierarchy could be judged separately.
- Added the volcanic palette to the minimap's 64×64 terrain survey. The first implementation searched every map site for every terrain pixel and aligned with five 25–27 ms refresh frames; it was rejected and replaced by a precomputed volcano-only cache.
- Map and surface/dungeon minimap verification pass with zero failures. The final visibility-traced Eastern movement run measures 5.11 ms average / 15.49 ms p95 / 24.78 ms maximum with zero 25 ms spikes, while retaining the accepted cartography.

### 2026-08-28 – Landform-scale mountain cliff walls

- Expanded the reusable Blender geology kit from four to six families with an 84 m stratified mountain wall and a 76 m glacial cirque headwall. Both are watertight continuous landforms with broken skylines, tapered ends, eroded ledges, irregular buried feet, and long rear aprons that extend into the uphill side of a mountain.
- Rejected the first rendered version because it read as a rectangular retaining wall. A second in-world review exposed dark rectangular material patches and a model-on-terrain silhouette; both were removed before acceptance. The final walls taper into the range, face outward from their mountain chain, follow the longitudinal terrain grade, sit 3.8 scaled metres into the ground, and retain restrained rock detail without black holes or luminous surfaces.
- Added deterministic mountain-chain placement with at most one wall per chain. The accepted atlas distribution is 25 walls: 18 stratified and 7 glacial. Candidate walls clear rivers by 120 m, roads by 150 m, local trails by 76 m, ponds by 180 m, bridges by 250 m, towns by 300 m, and the playable terrain edge by the complete scaled footprint plus 120 m.
- Every accepted wall samples nine footprint points, rejects excessive relief or low/wet ground, aligns its long axis to the sampled mountain grade, uses four localized collision segments rather than one oversized invisible block, and is MultiMesh-batched with 2.4 km visibility. Verification reports zero clearance or out-of-bounds failures.
- Rebuilt the starter and all six streamed visual bakes after final material acceptance. The starter remains 12.45 MB; streamed bakes remain 3.45–6.46 MB. Terrain integrity, river cohesion, riverbank contact, road hierarchy, all seven bridge placements, existing regional geology, and the new wall verifier pass with zero failures.
- Final signature-valid boot reaches 100% in 4.38 seconds. The seven-site Eastern runtime sample measures 6.89 ms median / 7.11 ms p95 / 7.15 ms p99 / 7.27 ms maximum with zero frames over 25 ms. The starter bake loads in 863.6 ms and instances in 260.8 ms; the Glacial bake loads in 414.0 ms and instances in 121.6 ms.

### 2026-08-28 – Glacial terrain anti-checker pass

- Removed the large gray/white square and diagonal terrain facets exposed by the new cirque-wall review. The rejected first correction merely mixed the repeated highland-stone photograph at several scales; it reduced the photo repeat but left eye-level bands. A second emissive diagnostic hid contrast by washing the range white and was also rejected.
- The accepted Glacial Range composition is evaluated entirely from three overlapping, differently rotated world-space fields. It preserves a colder northern mantle, glacier forefield, packed-snow islands, and darker moraine without consulting coarse triangle height/slope, exposing the repeated stone image, or using long sinusoidal color bands.
- Snow remains below display white, receives normal world lighting, carries restrained non-repeating close grain, and softens its rendered normal without changing collision or terrain height. Final walking-height captures cover both the glacier approach and moraine slope; the dedicated source verifier reports zero failures.
- Rebuilt the starter and all six streamed visual bakes. Terrain integrity, the exact Frontier/Glacial seam, river cohesion, riverbank contact, road hierarchy, all seven bridges, 25 large cliff walls, and the 118-feature world map remain green. The signature-valid Glacial runtime reports five Frost Trolls, 21 wildlife, four lore sites, three hidden caches, and no failures.
- Final Forward+ Glacial travel on the RTX 2080 measures 4.81 ms average, 3.38 ms median, 14.10 ms p95, 15.98 ms p99, and 19.54 ms maximum with zero frames at or above 25 ms. The accepted material therefore retains the 60 FPS budget instead of purchasing cleaner snow with heavier terrain geometry.

### 2026-08-28 – Authored mineable geology and break states

- Replaced recolored procedural ore spheres with a reusable Blender kit containing eight reviewed meshes: distinct intact and depleted states for iron, copper, silver/quartz, and gold/quartz. The first render was rejected because iron still read as a gray blob with pegs and copper was nearly spherical; the second replaced those hosts with angular grounded masses, and a final review replaced pasted cylindrical veins with low jagged mineral seams.
- The accepted atlas contains 1,690 mineable deposits: 717 in the Starting Realm, 223 in the North Frontier, 150 in the Glacial Range, 127 in the Western Reaches, 182 in Stormbreak, 96 on the Skeld Coast, and 195 in the Eastern Marches. Intact states remain spatially MultiMesh-batched and distance culled.
- Depleted geometry is created only for a deposit the player actually breaks. Three pickaxe hits hide only that intact batch instance, remove its nearby collision, leave a low ore-matched fractured remnant, and drop separate manual ore and stone pickups. After 150 seconds the remnant is freed and the exact intact instance/collision return; neighboring deposits never disappear.
- Rebuilt the starter and all six streamed visual bakes. The starter grows modestly from 12.45 MB to 12.72 MB; streamed bakes remain 3.68–6.70 MB with unchanged node counts. The eight-mesh/21-surface asset check, all-bake registry check, isolated break-state test, mining integration, and solid-world collision regression pass with zero failures.
- Starter Forward+ travel measures 4.54 ms average / 6.11 ms p95 / 13.91 ms maximum with zero 25 ms spikes. A first Glacial run exposed one 28.33 ms first-visibility frame; the warm acceptance cleared it and measures 5.12 ms average / 15.47 ms p95 / 24.48 ms maximum with zero 25 ms spikes, preserving the 60 FPS travel target.

Still needed:

- No blocking item remains from this natural-streaming/retained-atlas acceptance batch. Re-open memory-unloading work only when additional regions or a defined lower-memory target materially change the measured budget.

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
