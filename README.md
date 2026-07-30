# Broken Knight

Broken Knight is a Godot 4.7 open-world RPG prototype. The Godot project is
the only playable build; the former browser prototype has been retired.

## Start

- Play: `play-godot-world.bat`
- Open the Godot editor: `start-godot.ps1`
- Open the current hero source: `open-hero-blender.bat`
- Export the current hero to Godot: `export-hero-blender.bat`

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
|   `-- scripts/
|-- docs/                   Design notes and project documentation
|-- tools/
|   `-- godot-4.7/          Bundled engine used by launchers and tests
`-- *.bat / *.ps1           Stable developer entry points
```

## Sources of truth

- Game project: `godot/project.godot`
- Main scene: `godot/scenes/Main.tscn`
- World profile: `godot/data/world_profile.json`
- Current rigged hero source: `blender/hero_restart_rigged.blend`
- Current exported hero: `godot/assets/hero/hero_base_body.glb`

Generated Godot cache, test captures, Blender previews, logs, and temporary
files are excluded from source control and may be regenerated. Godot `.import`
sidecars are retained because they can contain authored per-asset settings.

See `PROJECT-STATE.md` for operational details and `godot/WORKFLOW.md` for the
test loop.
