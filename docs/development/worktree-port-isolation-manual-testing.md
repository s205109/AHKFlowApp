# Worktree Isolation Manual Testing

A quick **manual** check that the main checkout and one worktree run side by side with
isolated **ports** and **LocalDB databases**. Every step is something you run or click by
hand — there is no automated runner here. Budget about five minutes for the happy path.

The main checkout is the control: it keeps `5600` (API) / `5601` (UI) and the base
`AHKFlowApp` database. The worktree gets the next free pair (`5602` / `5603`) and its
own database, created automatically when its API starts.

## Before you start

- [ ] You are in the **main checkout** root and `git status` is clean.
- [ ] Nothing is listening on `5600` / `5601` (close any running launcher).
- [ ] LocalDB answers: `sqlcmd -S "(localdb)\mssqllocaldb" -Q "SELECT 1"` succeeds.

## 1. Create a worktree

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

## 2. Run main + worktree together (port isolation)

Port isolation covers **both** tiers, so each checkout must start the API **and** the UI. Use
the root launcher profile `API + LocalDB` — it starts both tiers together (running the API
project alone leaves the UI ports `5601` / `5603` dark). Start each checkout in its own
terminal. In Development the API migrates and seeds its database at startup, so no extra
request is needed.

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

## 3. Confirm distinct databases (database isolation)

Each API created its own database at startup. List them:

```powershell
sqlcmd -S "(localdb)\mssqllocaldb" -h -1 -Q "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE name LIKE 'AHKFlowApp%'"
```

- [ ] Two distinct databases appear: the base `AHKFlowApp` and the worktree's
  `AHKFlowApp_wt_iso_1_<hash>` (matching `AHKFLOW_DB_NAME` from step 1).

## 4. Remove the worktree and verify cleanup

Removal runs in a detached watcher and **cannot delete a folder that is still in use**, so
free it first:

- [ ] Press **Ctrl+C** in **both** `dotnet run` terminals (A and B).
- [ ] Close every **Windows Explorer** window and **Windows Terminal** tab whose folder is
  inside `.claude\worktrees\wt-iso-1` — these are the most common reason a worktree won't
  delete.

Then remove the worktree. In a Claude Code session inside the worktree, type `/exit` and
choose **remove worktree**. Plain git / Codex / Copilot users instead run, from the main
checkout, `git worktree remove .claude\worktrees\wt-iso-1`, then `git worktree prune` and
`git branch -d wt-iso-1`.

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

If the folder is still there, something still holds a lock on it — almost always an open
**Windows Explorer** window or **Windows Terminal** tab pointing inside the worktree. Close
it, re-check `.claude\worktrees\worktree-removal.log`, and let the watcher finish; once the
lock is gone it deletes the folder.

