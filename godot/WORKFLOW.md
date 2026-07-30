# Godot workflow

## Edit and play

1. Open the editor with `..\start-godot.ps1`.
2. Edit the project under this directory.
3. Run `res://scenes/Main.tscn`.
4. Use the targeted verification scripts under `tools/verification/`.
5. Store temporary screenshots under `artifacts/`; that directory is ignored.

## QA tool layout

- `tools/verification/`: pass/fail gameplay and content checks
- `tools/capture/`: visual review captures
- `tools/diagnostics/`: audits, benchmarks, and inspection tools
- `tools/import/`: import/build helpers

The `.godot/` directory is an import cache, not source. It can be deleted when
imports become stale and will be rebuilt by the editor.
