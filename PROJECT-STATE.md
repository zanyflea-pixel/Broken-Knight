# Broke Knight Project State

This file is the local source of truth for future Codex chats and automations.

## Canonical Entry

- Root URL: `http://127.0.0.1:8000/`
- Canonical 3D URL: `http://127.0.0.1:8000/index-3d.html?cb=20260529g`
- Root should forward to the canonical 3D URL.

## Canonical Run Flow

Start the project with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\start-broke-knight-server.ps1
```

Stop it with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\stop-broke-knight-server.ps1
```

The startup script should print:

- root URL
- canonical 3D URL
- current branch
- current commit

## Health Checks

Run the full project check:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\check-broke-knight.ps1 -BaseUrl http://127.0.0.1:8000
```

Run the dedicated 3D entry check:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\check-3d-entry.ps1 -BaseUrl http://127.0.0.1:8000
```

The 3D entry check verifies:

- root still forwards to the 3D entry
- the 3D page still has the boot loader
- the 3D page still has both canvases
- the live server is serving the expected 3D bootstrap

## Known Recovery Sources

- Automation memory:
  - `C:\Users\Jimmy\.codex\automations\3d-update\memory.md`
- Automation worktree:
  - `C:\Users\Jimmy\.codex\worktrees\2463\Broke Knight`
- Local recovery copy:
  - `C:\Users\Jimmy\Desktop\Broke Knight Recover`

## Operational Rules

- Treat `index-3d.html` as the real 3D entrypoint.
- Do not let `index.html` drift into a separate shell again.
- Prefer one active branch and commit milestone often.
- Before broad 3D UI changes, keep a backup or commit point.
- If the page feels wrong, verify the canonical URL first before debugging deeper systems.


















