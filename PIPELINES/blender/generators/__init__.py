"""Registered asset generators. Each module exposes build(asset_id: str, params: dict) -> bpy object."""
from . import block

GENERATORS = {"block": block}
