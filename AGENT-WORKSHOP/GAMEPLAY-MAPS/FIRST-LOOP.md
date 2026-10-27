# Gameplay map: the first loop

The smallest loop that exercises purpose, survival (resources), cooperation and persistent structure.

| # | Step | Where it happens | Proven by |
|---|---|---|---|
| 1 | A player enters the world | auth (`net/session.gd`) -> `server_app._on_peer_joined` -> welcome snapshot -> `client_app._on_welcome` | `test_two_clients_cooperate_and_observe_each_other` |
| 2 | Locates a resource | seeded scatter (`world_gen.resource_position`), visual = pipeline asset `resource_stone` | `test_config_and_worldgen.gd`, `test_assets.gd` |
| 3 | Interacts and collects it | E -> `pickup` request -> `WorldState.request_pickup` (range 3 m + 1 m slack, not carried, hands empty) | `test_world_state.gd`, cheat suite |
| 4 | Transports it | carried item follows the player (view model / avatar indicator); position validated by speed budget | `test_move_validation_uses_speed_budget` |
| 5 | Deposits it | E near the site -> `deposit` request (horizontal range 4.5 m + 1 m slack) | `test_deposit_increments_progress_and_respawns` |
| 6 | Site progress changes | `resource_deposited` event: progress +1, contribution recorded, replacement resource spawned | same |
| 7 | Visible to all players | event broadcast; `world_view._update_site` stacks one block per deposit (2x2 layers) | both bots report the same final progress |
| 8 | Remembered after restart | save at the end of the tick; reload validates schema/world id | `test_progress_persists_across_graceful_restart`, `test_progress_survives_server_crash`, docker re-creation test |

Resource representation: `{id, kind: "stone", pos, carrier}`; construction site: `{id, pos, deposited, contributors}`.
Clients can never declare ownership or progress: all of it is derived from validated server events.

Natural next steps (not implemented): multiple sites, resource types/recipes, decay or upkeep (structures that can
collapse), and the Tower as a multi-stage site whose stages unlock purposes.
