# Blueprints (templates)

Copy, rename, fill in. Keep entries short and factual; link to code, tests and measurements.

| Template | Use for | Where filled copies go |
|---|---|---|
| [FEATURE-PROPOSAL.md](FEATURE-PROPOSAL.md) | proposing new gameplay or tooling work | `../PLANNING/proposals/` |
| [SYSTEM-SPEC.md](SYSTEM-SPEC.md) | cross-cutting specs (rooms use their own `SPEC.md`/`CONTRACT.md` from `SYSTEM-ROOMS/_TEMPLATE`) | `../DOCUMENTATION/` |
| [ADR.md](ADR.md) | architecture decisions | `../DECISIONS/ADR-NNNN-slug.md` + index |
| [API-EVENT-CONTRACT.md](API-EVENT-CONTRACT.md) | network messages, events, public APIs between modules | next to the owning system |
| [BENCHMARK-REPORT.md](BENCHMARK-REPORT.md) | any performance claim or optimisation | task note or room `integration/` |
| [INTEGRATION-CHECKLIST.md](INTEGRATION-CHECKLIST.md) | manual parts of a promotion | task note |
| [KNOWN-ISSUE.md](KNOWN-ISSUE.md) | defects and limitations | `../INVENTORY/KNOWN-ISSUES.md` |
| [EXPERIMENT-REPORT.md](EXPERIMENT-REPORT.md) | outcomes of `experiments/` variants | room `experiments/` |
| [ASSET-INVENTORY.md](ASSET-INVENTORY.md) | asset metadata fields and inventory rows | `COMMON-ASSETS/<category>/<id>/asset.json`, `../INVENTORY/ASSETS.md` |
