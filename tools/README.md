# Project tools

The launchers in the project root are the stable entry points intended for
normal use. This folder contains maintenance tooling and the bundled Godot
runtime they call.

## Cleanup

Run the safe generated-file cleanup:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\clean-generated.ps1
```

Add `-IncludeLegacy` only when deliberately retiring old browser files and
timestamped Blender checkpoints:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\clean-generated.ps1 -IncludeLegacy
```

The script refuses to delete paths outside the project. It preserves canonical
Godot source, runtime assets, Blender source files, and Godot `.import`
sidecars.

## Other tools

- `backup-hero-face.ps1`: creates a dated hero-face source backup.
- `generate-ui-assets.ps1`: regenerates UI image assets.
- `godot-4.7/`: the bundled Godot executable used by launchers and tests.
