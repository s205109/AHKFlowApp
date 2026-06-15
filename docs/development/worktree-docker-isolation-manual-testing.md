# Worktree Docker Isolation Manual Testing

A **manual** check that the main checkout and one worktree can run SQL Server in Docker at the
same time — each in its own compose project on its own host port. Requires Docker Desktop
running. The dev-only SA password `Dev!LocalOnly_2026` is local-only — never reuse it
anywhere real. Budget about five minutes for the happy path.

## Before you start

- [ ] Docker Desktop is running (`docker ps` works).
- [ ] You have one worktree created (see the port isolation guide), e.g.
  `.claude\worktrees\wt-iso-1`.

## 1. Run Docker SQL from main + worktree

Start the Docker SQL profile in each checkout, in its own terminal:

```powershell
# Terminal A — main checkout
dotnet run --launch-profile "API + Docker SQL"

# Terminal B — worktree (run from .claude\worktrees\wt-iso-1)
dotnet run --launch-profile "API + Docker SQL"
```

- [ ] `docker compose ls --all` shows two projects: `ahkflowapp` and
  `ahkflowapp_<slug>_<hash8>`.
- [ ] `docker ps` shows two SQL containers on distinct host ports — `1433` and one in
  `14330-14399`.
- [ ] Each `scripts\.env.worktree` `AHKFLOW_SQL_PORT` matches its container's port.
- [ ] Both UIs load in a browser with no clash (main and worktree on their own UI ports).

## 2. Remove the worktree and verify teardown

- [ ] Press **Ctrl+C** in both terminals. This stops the SQL container but **keeps its data
  volume** — `docker ps -a` shows the container Exited, and `docker volume ls` still lists
  `ahkflowapp_sqlserver-data`.
- [ ] Close every **Windows Explorer** window and **Windows Terminal** tab whose folder is
  inside the worktree — the usual reason teardown stalls.
- [ ] Remove the worktree (Claude `/exit` → remove, or the git path from the port guide).
  Teardown runs `docker compose -p <project> down -v` only after the folder and branch are
  gone.
- [ ] `scripts/prune-worktree-docker.ps1 -WhatIf` lists only orphaned `ahkflowapp_*`
  projects (never the main base project). Drop `-WhatIf` to remove them.

## 3. Restart resilience (optional)

- [ ] Run the main checkout's `API + Docker SQL` profile, open the app in a browser, then
  press **Ctrl+C**. The container is Exited but the volume remains.
- [ ] Run the same profile again. The app loads in the browser and the log shows **no**
  `Database 'AHKFlowApp' already exists` (error 1801) — the readiness wait absorbs the
  recovery window.
- [ ] With the app stopped, run `docker rm -f ahkflowapp-sqlserver-1`, then start the
  profile again: it still comes up clean (the volume re-attaches and the readiness wait
  covers recovery).

