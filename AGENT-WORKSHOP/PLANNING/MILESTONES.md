# Milestones

## M0 - Bootstrap foundation (current; 0.1.0)

Workshop, sandbox with the first gameplay loop, dedicated server + containers, persistence, versioning and
snapshots, one system room, one asset pipeline example, automated suites, initial baselines.
Outcome and verification: `../TASKS/0001-bootstrap.md`.

## M1 - recommended next: "Living construction"

Goal: make the loop meaningful over time while keeping the architecture honest. Suggested scope (each through a room):
1. **Construction room**: multi-stage sites with stage requirements and a visible, stacked placeholder "tower";
   tested in isolation, integrated through the gateway (first room that owns persistent data -> first real schema
   migration v1 -> v2 with fixture and test).
2. **Interaction room**: server-side line-of-sight checks and generic interactables (replaces ad-hoc pickup/deposit code).
3. **Networking hygiene**: delta/interest-limited player-state replication (KI-003) with a benchmark proving the gain;
   move saves off the tick (KI-001) only if measurements still show spikes.
4. **Ops**: export a dedicated-server build to shrink the image; CI that runs `structure.py test --skip docker`.

Requires user approval before starting (new systems, schema change).
