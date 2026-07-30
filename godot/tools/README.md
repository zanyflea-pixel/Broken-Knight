# Project tools

- `verification/` contains automated pass/fail checks.
- `capture/` contains screenshot and visual-review generators.
- `diagnostics/` contains audits, benchmarks, and inspection scripts.
- `import/` contains asset import/build helpers.

Run GDScript tools with the bundled console executable:

```powershell
& "..\..\tools\godot-4.7\Godot_v4.7-stable_win64_console.exe" `
  --headless --path . -s res://tools/verification/verify_castle_tree_pass.gd
```
