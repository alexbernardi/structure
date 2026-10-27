# Integration checklist: <system> <version>

Automated part: `python TOOLS/cli/structure.py room promote <system>` (see PROTOCOLS/INTEGRATION-GATEWAY.md).
Tick the manual items below in the task note.

- [ ] Gateway output pasted (all automated checks green)
- [ ] Consumers in the sandbox use only the public interface listed in `CONTRACT.md`
- [ ] Interface changes documented in `CONTRACT.md` and the room README changelog; version bumped
- [ ] Protocol / world schema version bumped if messages or saved data changed; migration + fixture added
- [ ] Performance compared with `INVENTORY/PERFORMANCE-BASELINES.md` (no unexplained regression)
- [ ] Manual play check if the change is player-visible (`structure.py play` or `scenario a`)
- [ ] Rollback path noted (commit to revert / previous copy in `.runtime/promotions/`)
- [ ] Known issues updated
