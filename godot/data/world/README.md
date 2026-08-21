# World profile

`profile.json` is the first place to make world-layout changes. It contains
authored coordinates and sizes; the Godot builders turn those values into
terrain, water, roads, towns, vegetation, collisions, and maps.

## Coordinates

Positions and corridor points use `[x, z]` world coordinates. Positive `x` is
east. Positive `z` is north in the authored profile and map logic. Keep points
inside half of `world_size` unless deliberately creating a zone exit.

## Main sections

- `spawn_site`: initial player area.
- `town_sites`: settlement centers, usable radii, and ground heights.
- `forest_regions`: vegetation density regions.
- `mountain_chains`: oriented mountain footprints and heights.
- `pond_sites` and `waterfall_sites`: inland water features.
- `river_corridors`: ordered centerline points, width, and depth.
- `road_corridors`: primary travel routes.
- `trail_corridors`: narrower secondary routes.
- `ford_sites`: bridge/crossing anchors shared by terrain and traversal logic.

The starting settlement uses `spawn_site.starter: true` so it can receive an
authored town layout without also being duplicated by the regional-town
gameplay systems. `ground_height` and `ground_inner_ratio` keep its occupied
footprint stable. Small `map_sites` may opt into the same terrain treatment with
`usable_ground: true`; Ferrywatch Post is the reference example.

## Editing rules

1. Move connected features together. A changed river crossing usually requires
   matching river, road, and `ford_sites` edits.
2. Put town centers on broad terrain and keep their radius clear of riverbeds.
3. Add intermediate corridor points for curves; avoid sharp zigzags and long
   segments across steep slopes.
4. Keep river point order continuous from source to outlet.
5. Validate JSON and run `world.bat check` from the project root after
   every meaningful pass.

Do not edit `.godot/` or generated `.import` cache content to change the world.
