# Git and GitHub workflow

The project-level `project.bat` command is the normal interface. It keeps Git
commands predictable and runs the same checks locally that GitHub runs after a
push.

## First-time setup

Run this once after cloning or moving the project:

```powershell
project.bat setup
```

This enables Git LFS for the bundled Godot executable and canonical hero
assets, uses fast-forward-only pulls, prunes deleted remote branches, improves
conflict display, and disables ambiguous automatic line-ending conversion.

## Daily workflow

```powershell
project.bat status
project.bat godot
project.bat check
project.bat save "describe the working change"
project.bat sync
```

`save` runs checks, shows exactly what will be committed, and asks before
creating the commit. It does not push. `sync` refuses to run with uncommitted
files, then performs a fast-forward-only pull and pushes the current branch.
That prevents an accidental merge commit from hiding divergent work.

Use `project.bat save "message" -SkipChecks` only for documentation or another
change that cannot affect the running project.

## Useful commands

| Command | Purpose |
| --- | --- |
| `project.bat status` | Refresh origin and show changed/ahead/behind state |
| `project.bat check` | Run world, hero, combat, enemy, asset, and Git checks |
| `project.bat clean` | Ask, then remove captures, temporary output, previews, logs, and autosaves |
| `project.bat play` | Run the game |
| `project.bat godot` | Open the Godot project |
| `project.bat hero` | Open the canonical Blender hero |

## GitHub checks

`.github/workflows/project-checks.yml` runs `project.bat check` on pushes to
`main`, pull requests, and manual workflow runs. A red check means the pushed
commit failed the same verification available locally.

Large canonical hero files and the bundled engine use Git LFS. Never use
`git lfs migrate` casually: it rewrites repository history. The current setup
does not rewrite existing commits.

## Recovery

- See changed files: `project.bat status`
- See recent checkpoints: `git log --oneline -10`
- Restore one file from the last commit only when intentional:
  `git restore -- path/to/file`
- Never use `git reset --hard` to solve an ordinary mistake; it discards local
  work.
