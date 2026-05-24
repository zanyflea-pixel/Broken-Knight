# Broke Knight

A browser RPG prototype built as plain JavaScript modules. Run it through the local server so module imports load correctly.

## Run

```powershell
cd "C:\Users\Jimmy\Desktop\Broke Knight"
powershell -NoProfile -ExecutionPolicy Bypass -File .\start-broke-knight-server.ps1
```

Open the URL printed by the script.

The root URL now forwards to the cache-busted 3D entry so `/` and `/index-3d.html` cannot quietly drift apart.

The startup script also prints the canonical 3D URL, current branch, and current commit so future chats have one obvious source of truth.

To stop it cleanly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\stop-broke-knight-server.ps1
```

If you want the foreground diagnostic server that prints directly into the terminal, you can still use:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\serve-broke-knight.ps1
```

## Useful Commands

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\check-broke-knight.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\update-project-snapshot.ps1
```

`check-broke-knight.ps1` verifies required files, local module imports, and HTTP responses from the running server.

`check-3d-entry.ps1` verifies that the root page forwards to the real 3D entry and that the live 3D page still exposes the expected boot/UI canvases.

## Project State

See [PROJECT-STATE.md](C:\Users\Jimmy\Desktop\Broke Knight\PROJECT-STATE.md) for the canonical entrypoint, recovery sources, and the rules we use to keep future chats from drifting.

`update-project-snapshot.ps1` refreshes `all-project.txt` from the current project files.

## Controls

- Arrow keys: move
- Mouse or click: aim / attack
- Q/W/E/R: skills
- 1/2: health and mana potions
- F: interact
- B: dock or sail
- M: map
- I: inventory
- K: skills
- J: quests and tracking
- O: status
- G: dev tools
- Esc: close menus or leave dungeon
