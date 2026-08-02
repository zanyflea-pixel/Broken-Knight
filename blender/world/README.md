# World Blender authoring

This folder contains editable Blender sources used only by World Build.

## Layout

- `vegetation/`: canonical `.blend` source files for tree species.
- `scripts/`: deterministic builders and exporters.
- Runtime exports: `../../godot/assets/vegetation/`.

The scripts derive the project root from their own location. They do not
contain user-specific absolute paths, so the project folder can be moved.

## Commands

From the project root:

```powershell
.\world.bat trees
.\world.bat grass
```

`trees` rebuilds birch, maple, and pine sources and GLB exports. Broadleaf and
willow source files are retained separately; do not overwrite a hand-edited
source unless that is the intended change.

Exported GLBs belong in Godot. Editable `.blend` files belong here.
