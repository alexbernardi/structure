## {{ROOM_NAME}} system - public interface (see CONTRACT.md).
## Keep it engine-light and deterministic where possible: pure functions or RefCounted state objects,
## no autoloads, no class_name, relative preloads only (the folder is copied into the sandbox on promotion).
extends RefCounted

const VERSION := "0.1.0"


## Example function; replace with the system's real interface.
static func clamp_to_range(value: float, low: float, high: float) -> float:
	return clampf(value, low, high)
