# Project tools

The launchers in the project root are the stable entry points intended for
normal use. This folder contains maintenance tooling and the bundled Godot
runtime they call.

## Project command center

Use `..\project.bat` for normal development:

```powershell
project.bat status
project.bat check
project.bat save "describe the working change"
project.bat sync
```

`project.ps1` implements those commands and includes safeguards for dirty
working trees, oversized non-LFS files, failed tests, and non-fast-forward
pulls. See `..\docs\GITHUB-WORKFLOW.md` for the full workflow.

## Cleanup

Run the safe generated-file cleanup:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\clean-generated.ps1
```

This leaves the Godot import cache intact for faster startup. Add
`-RebuildGodotCache` only when imports are actually stale.

Add `-IncludeLegacy` only when deliberately retiring old browser files and
timestamped Blender checkpoints:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\clean-generated.ps1 -IncludeLegacy
```

The script refuses to delete paths outside the project. It preserves canonical
Godot source, runtime assets, Blender source files, and Godot `.import`
sidecars.

## Other tools

- `project.ps1`: Git, GitHub, validation, and launcher command center.
- `world.ps1`: implementation behind the root `world.bat` entry point. Run
  `world.bat check` after World Build changes.
- `backup-hero-face.ps1`: creates a dated hero-face source backup.
- `generate-ui-assets.ps1`: regenerates UI image assets.
- `godot-4.7/`: the bundled Godot executable used by launchers and tests.
