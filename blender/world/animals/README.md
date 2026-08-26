# Riverwatch Horse Assets

- `riverwatch_horse.blend` is the only production horse source.
- `../../../godot/assets/animals/riverwatch_horse.glb` is the only runtime horse.
- `archive/best_previous_v73/` preserves the strongest pre-cleanup attempt for reference; Godot does not import it.
- Rebuild the production asset with `../scripts/build_riverwatch_horse_production.py`.

Do not place experimental GLBs in `godot/assets/animals`; Godot imports every file in that directory even when gameplay does not reference it.
