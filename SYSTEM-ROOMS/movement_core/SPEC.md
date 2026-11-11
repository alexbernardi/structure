# SPEC: movement_core

## Responsibilities and scope

The approved player-character movement of Structure, as a reusable package: grounded locomotion (walk, run, sprint,
crouch, stairs, slopes, coyote time, jump buffer), the jump and air jump, and the traversal moves - vault (intentional,
inside a visible window), mantle and climb-over, airborne ledge catch, catch-and-hang, pull-up, shimmy with corners,
the climber's braced hang, crouch slide and crouch flip - plus the capability layer that upgrades or restricts them
(attributes, modifiers, resources) and the authored presentation (Quaternius mannequin, AnimationTree, hand and foot
IK, skeleton view, traversal debug overlay).

Out of scope: cameras (an orbit camera is included as a convenience, not part of the contract), worlds and courses,
tuning UIs and MIDI, networking (see CONTRACT "Multiplayer authority"), combat, vehicles.

## Behaviour

Summarised from the laboratory history, which keeps the measurements: [Movement Lab 3.0](../../AGENT-WORKSHOP/DOCUMENTATION/MOVEMENT-LAB-3.md)
(authored locomotion), [4.0](../../AGENT-WORKSHOP/DOCUMENTATION/MOVEMENT-LAB-4.md) (vault),
[5.x](../../AGENT-WORKSHOP/DOCUMENTATION/MOVEMENT-LAB-5.md) (traversal, hang, corners, IK, climber hang, shuffle).

- One physical action per tick: the traversal controller decides vault > mantle > jump on the ground and ledge catch
  > air jump > buffer in the air, only on a fresh press (no vault from mere contact or a held button).
- The body is a flat-bottomed cylinder `CharacterBody3D`; traversal moves drive it kinematically with full collision
  response; the movement core never knows about traversal.
- A human catches a ledge up to about 3.0 m; reach follows the body (stand height x 1.306) and the jump.
- Effective parameters are the baselines plus modifiers (add, mul, set, cap, floor; grants and revokes); the order
  modifiers are added in never changes the result.
- Presentation never feeds back into physics: with presentation off the body moves identically.
