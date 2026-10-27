# Known issues and limitations

Format: `../BLUEPRINTS/KNOWN-ISSUE.md`. Keep facts and assumptions separate.

| ID | Area | Severity | Status | Issue | Evidence / workaround |
|---|---|---|---|---|---|
| KI-001 | server | minor | open | Save-on-change rewrites `world.json` inside the tick; on Docker Desktop bind mounts (and Windows) a save takes ~4-10 ms, producing tick p95 spikes of 7-9 ms | `PERFORMANCE-BASELINES.md`. Options when it matters: background save thread, debounce, named volume instead of a Windows bind mount |
| KI-002 | server metrics | minor | open | `cpu_pct` / `rss_mb` are null for native Windows servers (in-process sampling reads Linux `/proc`) | use `bench server --docker` or `env status` (`docker stats`) |
| KI-003 | networking | major (at scale) | open | Player states are broadcast all-to-all at 15 Hz: traffic ~n² (32 players -> ~460 KB/s out) | interest management / delta compression before large player counts |
| KI-004 | authority | major (for public servers) | accepted | Movement is client-predicted; the server validates speed and bounds but not collisions, so a modified client can pass through obstacles at legal speed | ADR-0003; server-side simulation is a future movement-room milestone |
| KI-005 | client | cosmetic | open | ~150 ms hitch on the frame the world is built after joining | build the world over several frames or behind a loading screen |
| KI-006 | server (native) | minor | observed once | One 37 ms tick in a native Windows benchmark, during a save (suspected antivirus/file system stall; not seen in Docker) | re-measure if native servers become important |
| KI-007 | containers | minor | mitigated | The Godot editor binary logs `Unable to load fontconfig` during headless import in minimal images | `libfontconfig1` installed in the build stage; the runtime image needs nothing extra (zero engine errors at runtime) |
| KI-008 | tests | minor | accepted | Bots move in straight lines without collision; they exercise the protocol, not navigation | fine for current tests |
| KI-009 | client | minor | open | Pick-up targeting is a view cone + distance check, without line of sight | add a physics ray when obstacles matter |
| KI-010 | determinism | info | resolved | Movement golden trajectory (generated on Windows) is bit-exact at float32 on Linux too | verified in the tools container (`room test movement`, Godot 4.7.2 Linux build) |
| KI-011 | tooling | minor | open | Native server CPU/RSS, Linux clients and cross-machine networking are not covered by automated tests | see `DOCUMENTATION/TESTING.md` "Not automated yet" |
| KI-012 | security | info | accepted | Unauthenticated identities, unencrypted ENet, editor binary in the image | `PROTOCOLS/SECURITY.md` unresolved risks |
