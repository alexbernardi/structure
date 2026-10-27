# Workshop protocol

Every agent task follows these seven steps. Small tasks can be brief, but no step is skipped.

| Step | What to do | Output |
|---|---|---|
| 1. Enter the workshop | Read `START-HERE.md`, the current milestone (`PLANNING/MILESTONES.md`), ADRs touching your area, `INVENTORY/KNOWN-ISSUES.md` | You can state what exists and what constrains you |
| 2. Gather supplies | Identify code, docs, assets, tools, interfaces, tests and reference implementations you need; run `structure.py versions` | List in the task note |
| 3. Map the work | Affected modules, interfaces (`CONTRACT.md`s, protocol, save format), dependencies, integration risks | "Impact" section |
| 4. Prepare a plan | Concise steps, acceptance criteria, validation procedure (which suites/benchmarks) | `TASKS/NNNN-slug.md` from the template below |
| 5. Execute | In the system room or sandbox; one branch (`task/NNNN-slug`) or `git worktree` per task when parallel work is likely | Small, reversible commits |
| 6. Validate | Run the relevant suites (`structure.py test ...`), benchmarks if performance-sensitive; separate verified facts from assumptions | Results pasted into the task note |
| 7. Return to the workshop | Record changes, results, decisions (ADR), open problems (`KNOWN-ISSUES.md`), next steps; update `START-HERE.md` "Current state" if it changed | Completed task note |

## Hard rules

- **Approval needed** (ask the user before implementing): new external dependency or service, engine/tool pin
  change, network or persistence model change, repository layout change, anything contradicting an accepted ADR.
  Propose with `BLUEPRINTS/FEATURE-PROPOSAL.md` and/or `BLUEPRINTS/ADR.md`.
- **No silent side effects**: do not modify unrelated systems "to make integration convenient". Interface changes
  are documented in the system's `CONTRACT.md` and their tests updated in the same change.
- **Isolation first**: complex systems start in `SYSTEM-ROOMS/` and enter the sandbox through
  `PROTOCOLS/INTEGRATION-GATEWAY.md`.
- **Measure, don't assume**: optimisations need a benchmark showing the gain; record it with `BLUEPRINTS/BENCHMARK-REPORT.md`.
- **Known-good builds stay recoverable**: commit before risky changes; never rewrite shared history; keep world
  snapshots before experiments on persistent data (`structure.py snapshot create <env>`).
- **Honest reporting**: never claim an unexecuted test passed; say what could not be verified and why.

## Task note template

```markdown
# NNNN - <title>
Status: planned | in progress | done | blocked     Owner: <agent/human>     Date: YYYY-MM-DD
## Goal
## Impact (modules, interfaces, versions touched)
## Plan and acceptance criteria
## Validation (commands + results, verified vs assumed)
## Outcome (changes, decisions, open problems, next steps)
```
