# Broken Knight – Master Feature List

Last reorganized: 2026-08-24

This list consolidates the World Build requests made throughout development. It records intent as well as implementation so later changes do not solve one problem by reintroducing another.

## 1. World structure and expansion

- **Partial** – large seamless-feeling open world built from streamed local regions rather than one permanently loaded map.
- **Implemented** – starting realm, northern frontier, Crownfall Glacial Range, Western Reaches, Stormbreak Highlands, Skeld Coast, and Eastern Marches stream across blended outdoor boundaries without a portal.
- **Partial** – streaming preloads ahead of travel with corridor-aware neighboring-region selection and bounded offscreen material warm-up; broader mounted travel still needs final hitch acceptance without dismounting or losing gameplay state.
- **Partial** – the complete western/northern six-region block is implemented; east, south, volcanic, desert, and farther regional links remain queued on the same interface.
- **Partial** – distinct temperate, alpine, glacial, rainy woodland, windswept highland, and subarctic maritime biomes exist; desert, volcanic, and additional natural biomes remain queued.
- **Partial** – the Grey Sea coast, physical shelf, Frostharbor working dock, and fishing boats are implemented; swimming danger and a future sailing route remain queued.
- **Partial** – regions should grow colder and more dangerous with distance north of the starting area.
- **Partial** – each biome needs its own terrain palette, rocks, trees, vegetation, wildlife, enemies, settlements, loot, and ambient sound.
- **Partial** – authored landmarks, overlooks, valleys, ridges, basins, cliffs, plains, and travel corridors must give every region identity.
- **Partial** – Stormbreak adds purposeful slate ridges, outcrops, headwalls, and upland cliffs; Skeld adds coastal headlands, shore stones, a western ocean shelf, and sea stacks, with larger cliff families still planned.
- **Required rule** – never expose terrain holes, undersides, disconnected chunks, invisible floors, or fall-through seams.
- **Required rule** – build expansion data-first so adding a region does not require rewriting the world runtime.

## 2. Rivers, lakes, ponds, waterfalls, and ocean

- **Partial** – continuous authored river systems that follow terrain, remain inside channels, and terminate logically.
- **Required rule** – river water must remain below the surrounding bank top and physically touch the channel sides; no floating water, shadow gap, or dry air slit.
- **Required rule** – no river may simply stop in playable land or continue nonsensically through an ocean.
- **Implemented** – Rimewater begins at a mapped glacier and waterfall, crosses the glacial range, joins a frontier tributary, then feeds Crownfall downstream.
- **Implemented** – Galehorn Run begins at Blacktarn, descends through Stormbreak, passes under Galehorn Crossing, and continues seamlessly as the Western Reaches' Rainfall River.
- **Implemented** – the Skeld River begins at Rimeglass Tarn and Fall, crosses once beneath Skeld Bridge, reaches Frostharbor, and terminates exactly at Skeldmouth in the Grey Sea.
- **Implemented** – the Grey Sea uses an authored smoothed coastline, submerged terrain, a broad shallow shelf, deep-water walkability block, subtle broken foam, and matching local/world map rendering.
- **Partial** – smooth bends and riverbanks without jagged angles, land bars, random blue cuts, overflow, or harsh color bands.
- **Partial** – banks should blend into nearby soil/grass and remain walkable where the slope reasonably allows it.
- **Implemented** – ponds and waterfalls have authored site support.
- **Partial** – ponds should be irregular, seated in terrain, free of grass/tree intrusions, and useful for fishing.
- **Queued** – richer water surface motion, depth cues, foam near falls/rocks, current direction, and shore detail.
- **Queued** – swimming in rivers/lakes and dangerous ocean swimming with stamina/threat rules.
- **Required rule** – maps and minimaps must draw waterways as connected systems matching the actual world.

## 3. Roads, trails, bridges, and travel

- **Partial** – major roads, secondary roads, and local trails have distinct widths and route roles.
- **Required rule** – every route has a destination purpose and must connect continuously to it.
- **Required rule** – roads avoid extreme grades, use valleys/contours/switchbacks, and never end arbitrarily.
- **Partial** – road surfaces are slightly raised/tapered and must not swallow the hero's feet.
- **Partial** – routes require consistent material color without black sections, hard bands, grass gaps, motion crawl, or texture shimmer.
- **Partial** – bridges are placed at necessary crossings and span usable land to usable land.
- **Required rule** – roads meet bridge decks with no gap, do not paint across the bridge, and remain aligned at both landings.
- **Required rule** – grass/terrain cannot cover bridge approaches or decks.
- **Implemented** – bridges can have structural supports.
- **Partial** – natural standalone foot crossings supplement road bridges where needed for full-map access.
- **Required rule** – no side-water exploit should let the player climb onto a bridge from below.
- **Queued** – regional travel signs with readable words, correct fronts/backs, and useful destination guidance.

## 4. Settlements, architecture, and interiors

- **Partial** – starting town, Crownspire castle city, frontier towns, services, market areas, and enterable structures exist.
- **Required rule** – towns sit on usable dry ground and do not overlap water, roads, walls, trees, or neighboring buildings.
- **Partial** – towns need clearly different layouts, silhouettes, roof forms, materials, scale, culture, and interactable activities.
- **Partial** – houses need real openings/windows/doors instead of painted blue/white rectangles.
- **Partial** – multi-level houses require a real floor opening and fully walkable stairs to every floor.
- **Required rule** – doors animate visibly, open away from the player when possible, and never trap the player in the leaf or wall.
- **Partial** – all furniture, boxes, lamps, bushes, fences, rocks, trees, walls, and architectural props need appropriate collision.
- **Partial** – Crownspire castle has multiple floors, stairs, roof access, lookout structures, rooms, torches, furniture, banners, crest, windows, and throne.
- **Required rule** – castle stairs/ladder must support going up and down without jumping, teleporting, slipping through, or hitting the roof.
- **Required rule** – no floating gate blocks, roof decorations, crenellations, arch pieces, or wall props.
- **Partial** – building interiors need useful decoration and interactable purpose, not empty duplicate rooms.
- **Partial** – vendors should stand behind appropriate counters/market stalls and open a full shop menu.
- **Partial** – town crafting areas and environmental service signage exist.
- **Partial** – towns now receive small collision-aware roaming populations that sleep at distance; richer daily schedules and conversations remain planned.
- **Queued** – readable books, shelves, kitchens, bedrooms, workshops, taverns, storage, guard posts, and regional decor sets.

## 5. Terrain, vegetation, and environment art

- **Partial** – terrain uses blended biome colors, textured materials, authored landforms, fields, forests, rocks, grass, flowers, leaves, and ground clutter.
- **Required rule** – no visible square biome tiles, hard grass color lines, stretched textures, z-fighting, shimmer, or floating foliage.
- **Partial** – grass coverage should fill suitable green land naturally without rows or crude stick shapes.
- **Partial** – leaves/deadwood/undergrowth should gather naturally around trees; dense, sparse, and barren areas need intentional variation.
- **Partial** – realistic Blender tree assets exist for broadleaf, birch, maple, pine, and willow.
- **Required rule** – do not use trees that read as primitive blobs or have downward-pointing branch spikes/root sticks.
- **Partial** – different environmental tree species should match climate, moisture, altitude, and biome.
- **Queued** – additional desert, volcanic, and deadland tree/plant assets; Skeld now uses subarctic pine, birch, krummholz, heather, lichen, and dune-grass composition.
- **Partial** – rock formations and ore rocks require multiple silhouettes and material types, not recolors alone.
- **Partial** – ice-capped northern mountains with an altitude-driven snow line.
- **Partial** – alpine snow and coastal vegetation are implemented; desert cactus/tumbleweed fields and volcanic rock/lava ecology remain queued.

## 6. Maps, minimap, navigation, and markers

- **Partial** – detailed illustrated world map and fixed-orientation minimap represent terrain, settlements, rivers, roads, bridges, ponds, landmarks, services, and player facing.
- **Implemented** – three map scales: detailed local map, current-region map, and zoomed-out world atlas covering all seven authored regions, including the Grey Sea coastline and Eastern Marches.
- **Required rule** – local maps differ by zone and show more detail than the atlas.
- **Required rule** – map fills its available screen area; no decorative blank columns, thick yellow border, unused key panel, or overlapping text.
- **Required rule** – maps use visual detail rather than relying on extra explanatory text.
- **Implemented** – player direction uses a facing silhouette rather than a generic circle.
- **Partial** – map teleport mode supports temporary click-anywhere travel for testing.
- **Implemented** – the detailed atlas relief is a shipped generated asset; roads, rivers, sites, services, facing, hover details, and teleport aiming remain live overlays. Regional views cull only off-screen geography, and mouse movement no longer redraws the full illustrated map.
- **Partial** – map labels have contrast/collision handling and local-view clipping; remaining regions still need continued title and dense-label review.
- **Partial** – dungeon interiors need their own maps instead of the outdoor world map.
- **Queued** – fog-of-war/reveal rules after layouts are stable.
- **Queued** – clearer quest/destination markers that guide without replacing exploration.

## 7. Player traversal, mounts, and survival

- **Implemented** – hero follows sampled terrain height and supports walking, sprinting, jumping, blinking, and mounted travel.
- **Required rule** – feet remain on top of every valid terrain/road/town surface and never sink into raised overlays.
- **Partial** – fall damage and death exist but need forgiving tuning and full regression testing.
- **Required rule** – falling must not launch/teleport the player into the sky.
- **Partial** – horse riding, saddle placement, gallop, and seamless region crossing exist; hero must remain mounted during streaming.
- **Queued** – swimming locomotion and current/ocean danger.
- **Partial** – buildable campfire system and camp cooking.
- **Queued** – rest/sleep utility and safe-camp rules if they support the day/night loop.

## 8. Combat, classes, abilities, and enemies

- **Implemented** – Warrior with sword is the default class; stamina replaces mana for Warrior actions.
- **Partial** – action combat has melee/ranged abilities, enemies, targeting, damage, drops, and skill growth.
- **Partial** – combat should move toward deliberate action-RPG play: readable windups, dodge/positioning, stamina decisions, hit reactions, impact, sensible controls, and tougher encounter roles.
- **Implemented** – ability levels increase strength; some abilities gain behavior such as spread/multishot at later levels.
- **Implemented** – admin god mode and one-hit-kill mode exist.
- **Partial** – distinct enemy models currently include imp, ashfang hound, Gravebound zombie, cave dragon, Frost Troll brute, and the six-legged Blender-authored Rimecrawler; Stormbreak combines them into a higher-danger regional encounter mix while its unique enemy family remains queued.
- **Queued** – broader distinct enemy families with unique silhouettes/behavior, not simple color swaps.
- **Partial** – enemies become harder and more rewarding farther from the starting zone.
- **Required rule** – starter spawn has no immediate aggro; nearby enemies remain far enough away and do not path into spawn.
- **Required rule** – dungeon enemies cannot walk through walls/gates.
- **Partial** – the glacial range now has two authored Rimecrawler lairs; broader regional patrols, ambushes, elites, bosses, and faction behaviors remain planned.

## 9. Wildlife, hunting, fishing, and gathering

- **Implemented** – deer, hares, and grouse use Blender-authored models plus distance-aware sleeping and low-cost movement.
- **Implemented** – wildlife wanders within authored ranges, flees nearby players, can be hunted, and drops grounded meat/hides.
- **Implemented** – biome profiles declare wildlife populations rather than relying on global random spawning.
- **Implemented** – equippable fishing pole, natural river/pond fishing detection, bobber/bite timing, and fish item foundation.
- **Verify** – fishing pole must visibly sit in the hero's hand as a fishing pole in gameplay and equipment preview.
- **Partial** – fishing needs clearer casting/reeling animation, water feedback, and reward variety.
- **Implemented** – axe woodcutting and pickaxe mining foundations; all appropriate trees/rocks should be resource nodes.
- **Required rule** – chopping removes only the selected standing tree, falls one tree, despawns it later, and leaves non-spinning logs to pick up manually.
- **Partial** – rock nodes need distinct ore types, visuals, break states, and pickups.
- **Implemented** – herbs, sticks/logs, berries, mushrooms, ores, fish, and other materials can enter stacked bag slots.
- **Required rule** – gathered/dropped items are visible, grounded, non-spinning objects resembling the actual item.

## 10. Inventory, equipment, loot, gold, and durability

- **Partial** – combined inventory/equipment page shows bag stacks, armor slots, weapon/shield, stats, and a rotatable hero preview.
- **Required rule** – all bag items use distinct icons matching the item's in-world design.
- **Required rule** – equipment visibly occupies correct slots; drag previews are appropriately sized.
- **Partial** – equipment visuals include weapons, shields, torch, armor, axe, pickaxe, and fishing pole.
- **Implemented** – two ring slots, ring drag/equip rules, monster drops, merchant stock, stats, and frost/ember/wind visual effects.
- **Partial** – more weapons, armor sets, tools, crafting materials, consumables, and rare hidden items are still needed; Eastern Marches now adds Marchwarden Lamellar, Emberglass Oath Band, Saltmeadow Roundshield, Cinderwatch Scale Jack, Barrow Witness Band, Signal Knife, regional food, hides, ore, resin, and Emberglass.
- **Implemented** – manual world pickup, stacked bag storage, enemy gold/material/gear drops, chest loot, and shop purchases.
- **Partial** – gold needs meaningful recurring sinks: repairs, supplies, recipes, services, lodging/travel, and upgrades.
- **Implemented** – ordinary equipment has durability, loses condition through combat, shows condition in UI, can break, and can be repaired for gold.
- **Required rule** – Royal armor, Royal shield, and Royal sword are admin-grade and never lose durability.
- **Partial** – Royal armor is equipable through admin controls and must fill/show all proper equipment slots.
- **Partial** – hidden/quest unique items include the Rimefinder Signet, Aurora Surveyor Band, Icewatch Signet, Blue Maw Cleaver, Abbot's Tideglass Signet, Galehorn Patrol Cloak, Rainward Patrol Signet, Stormward Patrol Mantle, Stormscar Keeper Mantle, Tempest Choir Band, Cape Keld Watchcoat, and Greywake Lantern Band; frostward reduces incoming damage and windstep increases travel speed, with more utility effects planned.

## 11. Crafting, food, cooking, and economy

- **Implemented** – recipe/crafting foundation and town crafting stations.
- **Partial** – recipes include survival items and cooked food but need a much larger progression and stronger usefulness.
- **Partial** – food can heal or grant timed buffs; cooked food should outperform raw ingredients.
- **Implemented** – a crafted Camp Kit places a bounded number of campfires on validated outdoor terrain.
- **Partial** – campfires open a cooking-only recipe list; fish, hunted venison, mushrooms, herbs, and multi-ingredient meals are supported.
- **Partial** – Rime Chitin/Rimecrawler Bracers, Rainward and Stormbreak recipes, Skeld's Saltsteel Harpoon/Sealhide Watchcoat/Greywake Lantern Band, and Eastern Marches' Marchwarden Lamellar/Emberglass Oath Band/Saltmeadow Roundshield establish regional ingredient/equipment loops; recipe discovery, crafting skill growth, and tool requirements remain planned.
- **Queued** – hunting-to-cooking loop and a practical reason to stock food before dangerous travel.
- **Partial** – vendors have category catalogs and gold prices; the glacial, Rainward, Stormbreak, Skeld, and Eastern Marches settlements carry regional stock. Dawnford, March Keep, Cinderwatch, Amberfield, and Saltwatch now have distinct trade roles; more useful recurring services remain planned.

## 12. Quests, lore, books, secrets, and world guidance

- **Implemented** – quest menu, active quest display, reward flow, Gravebound campaign, and Oathbound campaign foundations.
- **Partial** – starting story and regional quest chains need clearer introductions, objectives, outcomes, and world consequences.
- **Partial** – Icewatch, the Western Reaches, Stormbreak, Skeld Coast, and Eastern Marches each have linked regional quest pairs; the Marcher chain connects Cinderwatch threats, hidden records, and regional equipment rewards. More quests tied to roads, ruins, hunting, dungeons, factions, and travel remain planned.
- **Partial** – northern books/tablets are readable in a dedicated paused reader; more journals, plaques, and regional signs remain planned.
- **Partial** – dungeon false walls and northern concealed caches exist; overlooks, rare encounters, treasure trails, and more utility items remain planned.
- **Required rule** – signs must have actual readable words, correct orientation, and solid construction rather than glowing placeholder text.
- **Queued** – a coherent world history explaining Crownspire, the Broken Knight, the Gravebound, the northern frontier, ruins, dungeons, and future regions.

## 13. Dungeons and caves

- **Partial** – well dungeon and cave dungeon foundations include rooms, passages, gates, keys, secrets, enemies, torches, boss checks, maps/markers, and reward chests.
- **Required rule** – cave entrances are clearly carved into and accessible from the mountainside, with aligned approach routes and no fall-through terrain.
- **Partial** – dungeons need deeper branching layouts, hallways, dead ends, verticality, hidden secrets, environmental storytelling, puzzles, and distinct visual themes.
- **Required rule** – gates look like gates, keys look like keys, interaction requirements are clear, paths are readable, and end chests always contain visible loot.
- **Required rule** – darkness remains atmospheric but traversable; torches illuminate all required navigation and combat spaces.
- **Partial** – dungeon-specific minimaps need room/corridor accuracy and later reveal rules.
- **Queued** – region-appropriate high-level dungeons with unique enemies, bosses, lore, and item sets.

## 14. Sky, lighting, weather, and presentation

- **Partial** – moving daylight cloud panorama and sky system exist.
- **Implemented** – the white northern horizon band was removed by replacing the split lower-sky gradient and preventing height fog from recoloring the sky.
- **Implemented** – outdoor day/night progression is active on a one-real-hour cycle; indoor dungeon fill remains stable.
- **Partial** – readable moonlight, star field, gradual transitions, and dusk-responsive torches are active but need continued visual tuning in every biome.
- **Implemented** – equippable hand torch emits light; positioning/arm pose still needs refinement.
- **Partial** – global lighting/color/exposure requires consistency without blown-out highlights or muddy gray/green scenes.
- **Required rule** – texture filtering, mipmaps, material offsets, and LOD transitions must not shimmer or blur painfully during movement.
- **Partial** – region-specific cloud bias, tint, fog, height, and density distinguish the rainward west, alpine north, glacial range, windswept highlands, and maritime Skeld Coast without changing time-of-day continuity.

## 15. UI, menus, controls, and admin

- **Implemented** – health/stamina HUD, minimap, quests, FPS counter, inventory/equipment, skills, quest log, vendors, crafting, pause menu, and admin menu.
- **Required rule** – every menu pauses gameplay; gameplay resumes only when all menus are closed.
- **Required rule** – Escape closes any open menu.
- **Implemented** – `M` map, `I` combined equipment/inventory, `B` bag/inventory compatibility, `K` skills, and `G` admin.
- **Partial** – menu typography/layout/contrast must fit without clipping, overflow, black voids, or overlapping content.
- **Implemented** – admin teleports, Royal armor, level/gold, enemy spawn, god mode, and one-hit kill foundation.
- **Partial** – admin remains focused on useful testing actions and avoids clutter.
- **Queued** – structured test/bug checklist hooks for region, encounter, dungeon, crafting, and map verification.

## 16. Performance and production rules

- **Required target** – 60 FPS during normal travel on the target machine.
- **Partial** – seven-region chunked terrain/content streaming, corridor-aware ahead-of-player loading, bounded offscreen regional render warm-up, sliced procedural fallback jobs, deterministic multi-region seam junctions, shared river-crossing datums, MultiMesh population, generated atlas relief, streamed heightmap collision, and signature-checked visual bakes for the starter plus all six streamed regions exist.
- **Implemented** – the starter population bake reduces measured boot completion from roughly 13.0 seconds to 5.1 seconds while retaining automatic procedural fallback if the bake is missing or stale.
- **Measured** – same-region map teleport improved from 3.82 seconds to 0.32 seconds; cold remote targets improved from roughly 54–57 seconds to 1.72–1.91 seconds, with a 27.77 ms worst first playable frame across all seven destinations. The Eastern town-outskirts fallback job improved from 532.8 ms to 18.6 ms after replacing individually materialized avenue trees with registered/choppable species batches.
- **Tracked limitation** – the accepted single-scene streamed bake still has an approximately 118–135 ms instantiate slice during far-ahead preload. A smaller-slice multi-file experiment was reverted after it failed headless renderer validation.
- **Required rule** – no large teleport, zone-boundary, castle, or menu-open frame spikes.
- **Required rule** – streaming cannot dismount the player, reset animation/state, respawn enemies at the player, or lose inventory/quests.
- **Required rule** – distant AI/wildlife/props use LOD, culling, sleeping, pooling, or low-frequency simulation.
- **Required rule** – the shipped atlas relief must prevent terrain texture generation during play; any regeneration happens through the dedicated build/capture path after structural world changes.
- **Required rule** – meaningful passes are tested in-engine; regressions are reverted or fixed in the same pass.
- **Required rule** – keep the project organized by reusable region/content data, shared builders, assets, systems, tests, and documentation.
- **Required rule** – preserve prior gameplay features while expanding; never silently delete a requested system to gain FPS.
