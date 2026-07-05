# Worktree Isolation Manual Testing

A quick **manual** check that the main checkout and one worktree run side by side with
isolated **ports** and **databases**. Every step is something you run or click by hand —
there is no automated runner here. Budget about five minutes per scenario for the happy path.

Two scenarios share one setup and teardown frame:
- **Scenario 1 — Port + LocalDB isolation:** each checkout runs the API and UI on its own
  ports against its own LocalDB database.
- **Scenario 2 — Docker SQL isolation:** each checkout runs SQL Server in its own Docker
  compose project on its own host port.

The main checkout is the control: it keeps `5600` (API) / `5601` (UI) and the base
`AHKFlowApp` database. The worktree gets the next free pair (`5602` / `5603`) and its own
database, created automatically when its API starts.

## Before you start

- [ ] You are in the **main checkout** root and `git status` is clean.
- [ ] Nothing is listening on `5600` / `5601` (close any running launcher).
- [ ] LocalDB answers: `sqlcmd -S "(localdb)\mssqllocaldb" -Q "SELECT 1"` succeeds.
- [ ] For Scenario 2 only: Docker Desktop is running (`docker ps` works). The dev-only SA
  password `Dev!LocalOnly_2026` is local-only — never reuse it anywhere real.

## Create a worktree

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/new-worktree.ps1 -Name wt-iso-1
```

Claude Code users can instead type **"Create a worktree named wt-iso-1"** in the prompt — it
runs the same hook.

- [ ] The command prints a path under `.claude\worktrees\wt-iso-1`.
- [ ] That worktree's manifest exists and shows distinct values:

```powershell
Get-Content .claude\worktrees\wt-iso-1\scripts\.env.worktree
```

- [ ] `AHKFLOW_API_PORT=5602`, `AHKFLOW_UI_PORT=5603`, and a
  `AHKFLOW_DB_NAME` shaped like `AHKFlowApp_wt_iso_1_<hash>`.

## Scenario 1 — Port + database isolation (LocalDB)

### Run main + worktree together

Port isolation covers **both** tiers, so each checkout must start the API **and** the UI. Use
the root launcher profile `API + LocalDB` — it starts both tiers together (running the API
project alone leaves the UI ports `5601` / `5603` dark). Start each checkout in its own
terminal. In Development the API migrates its database at startup, so no extra request is
needed.

**Terminal A — main checkout:**

```powershell
dotnet run --launch-profile "API + LocalDB"
```

**Terminal B — worktree:**

```powershell
Set-Location .claude\worktrees\wt-iso-1
dotnet run --launch-profile "API + LocalDB"
```

**Terminal C — verify:**

```powershell
Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -in 5600,5601,5602,5603 } |
  Select-Object LocalPort | Sort-Object LocalPort
```

- [ ] All four ports — `5600`, `5601`, `5602`, `5603` — are listening.
- [ ] The **main UI** loads in a browser at `http://localhost:5601`.
- [ ] The **worktree UI** loads in a browser at `http://localhost:5603`.

Two UIs answering on different ports with no collision is the proof of port isolation.

### Confirm distinct databases

Each API created its own database at startup. List them:

```powershell
sqlcmd -S "(localdb)\mssqllocaldb" -h -1 -Q "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE name LIKE 'AHKFlowApp%'"
```

- [ ] Two distinct databases appear: the base `AHKFlowApp` and the worktree's
  `AHKFlowApp_wt_iso_1_<hash>` (matching `AHKFLOW_DB_NAME` from the setup step).

## Scenario 2 — Docker SQL isolation

Requires Docker Desktop running. Start the Docker SQL profile in each checkout, in its own
terminal:

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

### Restart resilience (optional)

- [ ] Run the main checkout's `API + Docker SQL` profile, open the app in a browser, then
  press **Ctrl+C**. The container is Exited but the volume remains.
- [ ] Run the same profile again. The app loads in the browser and the log shows **no**
  `Database 'AHKFlowApp' already exists` (error 1801) — the readiness wait absorbs the
  recovery window.
- [ ] With the app stopped, run `docker rm -f ahkflowapp-sqlserver-1`, then start the
  profile again: it still comes up clean (the volume re-attaches and the readiness wait
  covers recovery).

## Remove the worktree and verify cleanup

Removal runs in a detached watcher and **cannot delete a folder that is still in use**, so
free it first:

- [ ] Press **Ctrl+C** in **both** `dotnet run` terminals (A and B). For the Docker scenario
  this stops the SQL container but **keeps its data volume** — `docker ps -a` shows the
  container Exited, and `docker volume ls` still lists `ahkflowapp_sqlserver-data`.
- [ ] Close every **Windows Explorer** window and **Windows Terminal** tab whose folder is
  inside `.claude\worktrees\wt-iso-1` — these are the most common reason a worktree won't
  delete.

Then remove the worktree. In a Claude Code session inside the worktree, type `/exit` and
choose **remove worktree**. Plain git / Codex / Copilot users instead run, from the main
checkout, `git worktree remove .claude\worktrees\wt-iso-1`, then `git worktree prune` and
`git branch -d wt-iso-1`. Docker teardown (`docker compose -p <project> down -v`) runs only
after the folder and branch are gone.

Cleanup is asynchronous; poll from the main checkout:

```powershell
git worktree list
Test-Path .claude\worktrees\wt-iso-1
sqlcmd -S "(localdb)\mssqllocaldb" -h -1 -Q "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE name LIKE 'AHKFlowApp%'"
Get-Content .claude\worktrees\worktree-removal.log
```

- [ ] The worktree and its branch are gone from `git worktree list` / `git branch`.
- [ ] `Test-Path` returns `False` — the folder is removed.
- [ ] Only the base `AHKFlowApp` database remains.
- [ ] The removal log ends with a completion line.
- [ ] Scenario 2: `scripts/prune-worktree-docker.ps1 -WhatIf` lists only orphaned
  `ahkflowapp_*` projects (never the main base project). Drop `-WhatIf` to remove them.

If the folder is still there, something still holds a lock on it — almost always an open
**Windows Explorer** window or **Windows Terminal** tab pointing inside the worktree. Close
it, re-check `.claude\worktrees\worktree-removal.log`, and let the watcher finish; once the
lock is gone it deletes the folder.
