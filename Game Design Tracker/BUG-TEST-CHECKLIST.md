# Broken Knight – Bug Test Checklist

Use this as a repeatable walk-through after meaningful world passes. Record the build date and exact location for every failure.

## Boot and performance

- [ ] Game boots to playable control without excessive startup stall.
- [ ] FPS holds near 60 in wilderness, towns, castle, dungeons, and while mounted.
- [ ] Teleport causes no large visible freeze.
- [ ] Crossing a streamed region seam causes no freeze, dismount, animation loss, state loss, or collision hole.
- [ ] Opening/closing maps and menus introduces no continuing frame spikes.

## Terrain and water

- [ ] No terrain holes, cracks, visible undersides, invisible slabs, or fall-through areas.
- [ ] Hero feet remain on the top surface of terrain, roads, town ground, floors, and bridge approaches.
- [ ] Every river is continuous from a believable source/region boundary to a lake/ocean/downstream boundary.
- [ ] Water remains below bank top and touches both channel sides everywhere.
- [ ] No floating water shadows, dry air gaps, overflow, land bars, abrupt terminations, or jagged hard-angle banks.
- [ ] Ponds sit in terrain and contain no grass/tree intrusions.
- [ ] Riverbank soil/grass blends into surrounding land without climbing cliffs unnaturally.

## Roads and bridges

- [ ] Every major road has a visible destination and remains continuous.
- [ ] Trails remain narrower/secondary and do not turn black or disappear.
- [ ] No route climbs an unreasonable grade or cuts through water/buildings.
- [ ] Every road meets its bridge with no gap, grass, step snag, height mismatch, or road texture on the deck.
- [ ] Every bridge fully spans water and lands on usable ground.
- [ ] Player cannot mount a bridge from its side while standing in the river.

## Architecture and collision

- [ ] No buildings, trees, props, walls, roads, or water overlap incorrectly.
- [ ] All solid props block walking; small intentional ground cover does not snag the player.
- [ ] Every enterable building door opens visibly and cannot trap/push the player into geometry.
- [ ] Every multi-floor building has a real stair/ladder opening and can be traversed both directions without jumping.
- [ ] Castle stairs, ladder, roof doors, lookout, windows, and floors work in both directions.
- [ ] No floating roof pieces, gate pieces, signs, lights, banners, walls, or decorations.
- [ ] Windows are real openings where specified and roofs have no unintended holes.

## Systems and UI

- [ ] Local, region, and world map scales switch correctly and player facing/location remain accurate.
- [ ] Minimap orientation stays fixed and depicts current terrain/roads/rivers/bridges/ponds.
- [ ] Map labels never overlap or overflow and contrast with the surface beneath them.
- [ ] All menus pause; Escape closes the active menu; game resumes only when no menu remains open.
- [ ] Inventory fits screen, stacks pickups, shows equipped items, and hero preview rotates by mouse.
- [ ] Held/equipped axe, pickaxe, torch, sword, shield, and fishing pole display as the correct model.
- [ ] Loot rests grounded without spinning and resembles its inventory icon/in-world item.

## Combat, gathering, and content

- [ ] No enemy spawns/aggros at the starting spawn.
- [ ] Enemies respect walls, gates, terrain, and encounter bounds.
- [ ] Warrior defaults to sword/stamina and abilities improve with skill levels.
- [ ] Axe chops only the selected tree; standing tree disappears; felled tree/log lifecycle is correct.
- [ ] Pickaxe breaks the selected ore rock and drops correct grounded ore.
- [ ] Fishing works at both river and pond with pole, bobber, bite cue, and timed `E` input.
- [ ] Dungeon entrance is obvious/accessible; paths, keys, gates, secrets, boss, chest, and exit all work.
- [ ] Dungeon end chest always spawns collectible rewards.
- [ ] Quests, books, signs, markers, vendors, crafting, food, gold, saves, and loading retain state.

## Presentation

- [ ] No white northern sky band, visible sky edge, or pasted-looking cloud seam.
- [ ] Day/night transitions are gradual and night remains playable with stronger torch visibility.
- [ ] No texture shimmer, z-fighting, crawling road detail, square biome grids, stretched stone, or hard grass color bands while walking.
- [ ] Environment density varies intentionally: dense habitat, scattered transition, and genuinely barren terrain each read differently.
