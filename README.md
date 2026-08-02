# Broken Knight

[![Project checks](https://github.com/zanyflea-pixel/Broken-Knight/actions/workflows/project-checks.yml/badge.svg)](https://github.com/zanyflea-pixel/Broken-Knight/actions/workflows/project-checks.yml)

Broken Knight is a Godot 4.7 open-world RPG prototype. The Godot project is
the only playable build; the former browser prototype has been retired.

## Start

- Project command center: `project.bat help`
- World editing guide: `WORLD-BUILD-START-HERE.md`
- World command: `world.bat` (`check`, `play`, `import`, `clean`, `perf`, `trees`, `grass`, `outcrops`, `verges`)
- World performance and cache notes: `docs/world/PERFORMANCE.md`
- Play: `play-godot-world.bat`
- Open the Godot editor: `start-godot.ps1`
- Open the current hero source: `open-hero-blender.bat`
- Export the current hero to Godot: `export-hero-blender.bat`
- Godot editing map: `godot/EDITING-GUIDE.md`
- Blender file map: `blender/FILE-INDEX.md`
- Hero animation list: `blender/ANIMATIONS.md`
- Git and GitHub workflow: `docs/GITHUB-WORKFLOW.md`

## Project layout

```text
Broken Knight/
|-- godot/                  Playable game and runtime assets
|   |-- assets/
|   |-- data/
|   |-- scenes/
|   |-- scripts/
|   |-- tests/
|   `-- tools/              QA, capture, diagnostics, and import hooks
|-- blender/                Editable 3D source and asset-build scripts
|   |-- world/              World-only Blender sources and exporters
|   `-- scripts/            Hero/equipment asset scripts
|-- docs/                   Story, design, and project documentation
|-- tools/
|   `-- godot-4.7/          Bundled engine used by launchers and tests
`-- *.bat / *.ps1           Stable developer entry points
```

## Sources of truth

- Game project: `godot/project.godot`
- Main scene: `godot/scenes/Main.tscn`
- World profile: `godot/data/world/profile.json`
- Editable story: `docs/story/LORE-AND-WORLD.md`
- Current rigged hero source: `blender/BrokenKnight_Hero_Master.blend`
- Current exported hero: `godot/assets/hero/hero_base_body.glb`

Generated Godot cache, test captures, Blender previews, logs, and temporary
files are excluded from source control and may be regenerated. Godot `.import`
sidecars are retained because they can contain authored per-asset settings.

See `PROJECT-STATE.md` for operational details and `godot/WORKFLOW.md` for the
test loop.
