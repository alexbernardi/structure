# Laboratory pipeline

How a system goes from `main` into a laboratory and back: **main -> laboratory -> experiment -> validate -> promote
-> main**. Decision and rationale: [ADR-0010](../DECISIONS/ADR-0010-shared-systems-and-laboratories.md). Commands
run from the repository root of the worktree you are in (`python TOOLS/cli/structure.py ...`); none of them pushes.

## Terms

| Term | Meaning |
|---|---|
| approved system | a package room with a released version (`room list`, `SYSTEM-ROOMS/<room>/README.md`) - today `movement_core` |
| workbench | the laboratory that holds a system's source (`room.json` `package.workbench`); for movement: `utility/movement/flat-plane` |
| laboratory | branch `lab/<name>` in its own worktree with a Godot project `LABS/<name>/` |
| pin | the version of an approved system installed in a project (`<project>/systems/<room>/INTEGRATION.json`, `lab.json`) |

## 1. Create a laboratory

```powershell
python TOOLS/cli/structure.py lab create combat --systems movement_core
```

From the current `main`: a worktree `..\structure-lab-combat` on branch `lab/combat`, a Godot project
`LABS/combat/` (test ground with the approved movement character), `movement_core` installed and pinned, one commit.
`--systems movement_core@1.0.0` pins an older release; `--path` chooses the folder. Then run `setup` once in the new
worktree (it imports the projects) and open `LABS/combat` in Godot.

## 2. Develop independently

- Work only on the laboratory branch, in its worktree. Commit often; the laboratory never touches `main`.
- Build the laboratory's own system inside `LABS/<name>/` (for a future shared system: under
  `LABS/<name>/systems/<new_room>/`, with a package room declaring this lab its workbench).
- Use approved systems through their CONTRACT only. Never edit `LABS/<name>/systems/<room>/`: `check` reports drift.
  If an approved system needs a change, make it in that system's workbench laboratory (or ask for one) - not here.
- To change an approved system itself (e.g. the next movement version): create a laboratory for it, work in its
  workbench (`utility/movement/flat-plane`), keep the workbench's suite green, update the room's CONTRACT / README
  and `room.json` version, and promote as below.

## 3. Synchronise with main

```powershell
python TOOLS/cli/structure.py lab sync                    # in the laboratory's worktree
python TOOLS/cli/structure.py lab sync --update-systems   # also re-pin compatible (same-major) system updates
```

Refuses with uncommitted work (commit, or `git stash push -u -m <tag>`). Merges `main` into the laboratory
(`--no-ff`; history kept, nothing overwritten), then reports each pin against the approved version: `current`,
`behind_compatible` (update when convenient), `behind_breaking` (read the room README's migration notes, re-install,
fix the laboratory). On a merge conflict it stops with the merge in progress and lists the files: resolve them
keeping both sides' intent, `git add`, `git commit` - or `git merge --abort`. Never resolve by taking one side
wholesale when the other side holds valid work; ask for a decision if intent is unclear.

## 4. Validate

```powershell
python TOOLS/cli/structure.py lab validate            # static checks, the lab's tests, its pins
python TOOLS/cli/structure.py room test movement_core # when the laboratory changes movement itself
python TOOLS/cli/structure.py room bench movement_core
```

Automated checks cannot judge feel or looks: say which parts still need a human playtest in the task note.

## 5. Promote into main

```powershell
python TOOLS/cli/structure.py lab promote combat            # validate the merge; main untouched
python TOOLS/cli/structure.py lab promote combat --merge    # and fast-forward main to the validated merge
python TOOLS/cli/structure.py lab promote --branch <branch> --merge   # a branch not named lab/<name>
```

1. Refuses if the laboratory has uncommitted changes, or if git has no author identity for the merge commit
   (`git config user.name` / `user.email`, or the `GIT_AUTHOR_*` / `GIT_COMMITTER_*` environment variables).
2. Creates `integrate/<name>-<stamp>` from the current `main` in `.runtime/worktrees/` and merges the laboratory
   there (`--no-ff`). Conflicts stop it there; `main` and the laboratory are untouched - sync the laboratory and retry.
3. Runs the gates inside the integration worktree: `setup`, then `test check tools import unit rooms utility labs`
   (`--gates` changes the list; add `multiplayer` when the change can affect the server).
4. With `--merge`, and only if every gate passed, the `main` worktree is clean and `main` has not moved meanwhile:
   `main` fast-forwards to the validated merge commit. Records go to `.runtime/promotions/`.
5. If a package system changed: bump its `room.json` version and README table, `room install` it into its declared
   consumers (the sandbox) in the laboratory before promoting, then after the merge run `room release <room>` on
   `main` to tag `<room>/v<version>`. Other laboratories pick it up with `lab sync --update-systems`.
6. Publishing (`git push`) is a separate, explicit step for the user.

## 6. Roll back

- A bad promotion: on `main`, `git revert -m 1 <merge commit>` (keeps everything else that landed since), then
  validate with `structure.py test`. Never reset or force-push `main`.
- A bad system version in one project: `room install <room> <project> --version <previous>` (from its release tag),
  commit, and note it in the room's `integration/README.md`.
- The previous approved state of every system stays available as its release tag.

## Rules

- Only the user approves what becomes `main`; agents promote when asked and report what the gates did not cover.
- One laboratory per system under development; several laboratories may run in parallel on separate branches.
- Contract changes bump the version (minor: additions; major: breaks + migration notes) in the same change.
- Changes to network messages or saves also follow [VERSIONING.md](VERSIONING.md).
