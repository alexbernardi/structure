# Pillars and architectural direction

Long-term themes: civilisation, institutions, religion, myth, ethics, political authority, survival, emergent
behaviour. The Tower / Stairway to Heaven is the central organising objective - not necessarily an ending.
None of these systems exist yet; this page records how they shape today's architecture.

| Pillar | Meaning | Architectural consequence today |
|---|---|---|
| Purpose | agents and players pursue meaningful objectives | objectives are server-side state with events (the construction site is the first shared objective) |
| Survival | individuals and civilisations obtain and manage resources | resources are authoritative world entities with ownership (carrier) and persistence |
| Emergence | independent systems interact to produce unpredictable outcomes | systems are isolated (rooms) and communicate through events and contracts, so interactions stay observable and testable |
| Structure | institutions, cooperation, infrastructure emerge, persist, transform, collapse | persistent world state with versioned schemas, snapshots and migrations from day one; contributions are recorded per player |

Guidelines for future concept work (keep it gameplay- and simulation-first):
- New concepts start as a short note here or a proposal (`../BLUEPRINTS/FEATURE-PROPOSAL.md`), then a system room.
- Prefer mechanics that create observable state changes other systems can react to (events) over scripted content.
- No art style, detailed environments or elaborate lore until the systems demand them.
