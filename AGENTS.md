<!-- BK_CODEX_LOCAL_BEGIN -->
# Broke Knight - Codex Local Rules

These rules are intentionally compact to reduce wasted context and keep the local coding workflow efficient.

## Operating mode
- Work directly on the local repository files. Do not ask the user to paste a file that is already readable from the workspace.
- Text only by default. Do not create, capture, attach, upload, or inspect images/video unless the user explicitly asks for visual work.
- Prefer targeted file reads, `rg`, focused searches, `git diff`, and focused tests. Do not recursively dump the whole repository into context.
- Ignore large/generated folders unless relevant: `.git`, `.godot`, `captures`, caches, build output, binary assets, and backup folders.
- Keep user-facing responses compact: what changed, which files changed, validation result, and any blocker.
- For requested code changes, edit the real files and validate them. Do not return giant full-file code dumps unless the user explicitly asks for pasted code.
- Preserve working systems unless evidence shows they need modification.
- Before risky edits, make a backup or rely on a clean Git checkpoint. Never overwrite important Blender/GLB source assets casually.
- For PowerShell/BAT automation, write diagnostics to `C:\Users\Jimmy\Desktop\Broken Knight\Powershell output\test.txt`, parser-check PowerShell changes, back up first, and restore on failure when practical.

## Broken Knight controls and project invariants
- Arrow keys are movement. WASD is not movement.
- QWERT is reserved for skills/spells.
- Sword visual/anatomical right hand maps to rig `hand.L`. Do not "correct" it to `.R`.
- Shield is on the anatomical left side and uses the `.R` rig side; shield anchor is `forearm.R`.
- Sword animation must stay clear of the head and face.
- Do not replace the colored hero GLB or canonical Blender source unless explicitly requested.
- Main project root is `C:\Users\Jimmy\Desktop\Broken Knight`.
- Godot project is `C:\Users\Jimmy\Desktop\Broken Knight\godot`.
- Prefer normal F5 gameplay testing over Movie Maker capture unless capture is specifically required.

## Efficiency
- Read only the files needed for the current task.
- Reuse conclusions from this session instead of rescanning unchanged files.
- Use the smallest useful test set first, then expand only if the focused test exposes a wider problem.
- Avoid repeating long status/history summaries in every response.
<!-- BK_CODEX_LOCAL_END -->

<!-- CODEX_TIE_IN_LOCAL_TEXT_V25_BEGIN -->
# Codex Tie In - Local Text Studio
- Work directly on the local Broken Knight repository. Do not ask for pasted files when the workspace can be read.
- Text only by default. Do not open/automate ChatGPT, Firefox, or browser chat. Do not capture/upload images or video unless explicitly requested.
- Use targeted reads/searches and focused validation to conserve context and usage. Avoid giant recursive dumps and generated/binary folders unless needed.
- Make requested code edits directly in the project and report changed files plus validation results concisely.
- Selected external files may be converted locally to text under `_CodexTieIn\data\context`; treat those text copies as user-provided context.
- For PowerShell/BAT changes, back up first, parser-check, restore on failure when practical, and log diagnostics to `C:\Users\Jimmy\Desktop\Broken Knight\Powershell output\test.txt`.
<!-- CODEX_TIE_IN_LOCAL_TEXT_V25_END -->
