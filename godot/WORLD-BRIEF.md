# World Brief

Use this as the shape of a world request when you want the Godot world rebuilt.

## 1. Core Feel
- Example: frontier coast, autumn woods, ashlands, ruined highlands
- Example: cozy starting region, dangerous north, open central travel routes

## 2. Starting Area
- Starting town name
- Terrain around it: flat / rolling / coastal / forested
- What should be close by: river, road junction, bridge, dock, cliffs

## 3. Towns
For each town:
- name
- rough direction from start
- what biome/terrain it sits in
- what makes it important

## 4. Rivers
For each main river:
- where it starts
- where it flows
- if it feeds into a lake or ocean
- where branches split off
- where crossings should exist

## 5. Roads
For each main road:
- what places it connects
- whether it is a trade road, mountain pass, coast road, forest road
- whether it should be straight, winding, or sparse

## 6. Mountains / Cliffs / Valleys
- where the edge ranges should be
- where interior highlands should be
- where travel should be blocked or funneled through passes

## 7. Water Bodies
- west sea / south bay / inland lake / marsh / gulf
- what should feel open water vs narrow river

## 8. Travel Logic
- where the player should naturally go first
- what routes should feel safe
- what areas should feel late-game or hostile

## 9. Visual References
- names of games or moods
- specific things to lean toward
- specific things to avoid

## Current Build Inputs

The active world data lives in `data/world/profile.json`. Start with the
project-root `WORLD-BUILD-START-HERE.md` before changing it.

That file currently drives:

- terrain footprint
- town anchors
- river corridors
- road corridors
- mountain chains
- ocean basins
- flat settlement regions
