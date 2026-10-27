"""Render a world document (world.json or a snapshot's world.json) as a top-down SVG map.

usage: python TOOLS/visualization/world_map.py <world.json> [-o map.svg]
Shows construction sites (label = progress), resting resources and the contributors table. Seed-derived obstacles
are generated in-engine and are not drawn.
"""
from __future__ import annotations

import argparse
import html
import json
import sys
from pathlib import Path

HALF_EXTENT = 80.0  # matches world_state.gd WORLD_HALF_EXTENT
PX_PER_M = 4.0


def to_px(x: float, z: float) -> tuple[float, float]:
    return (x + HALF_EXTENT) * PX_PER_M, (z + HALF_EXTENT) * PX_PER_M


def render(doc: dict) -> str:
    size = HALF_EXTENT * 2 * PX_PER_M
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{size + 260:.0f}" height="{size:.0f}" font-family="sans-serif" font-size="11">',
             f'<rect width="{size:.0f}" height="{size:.0f}" fill="#6b7566"/>']
    for metres in range(-80, 81, 10):
        p = (metres + HALF_EXTENT) * PX_PER_M
        parts.append(f'<line x1="{p}" y1="0" x2="{p}" y2="{size}" stroke="#5c6658" stroke-width="1"/>')
        parts.append(f'<line x1="0" y1="{p}" x2="{size}" y2="{p}" stroke="#5c6658" stroke-width="1"/>')
    for site in doc.get("sites", []):
        x, y = to_px(site["pos"][0], site["pos"][2])
        half = 3 * PX_PER_M
        parts.append(f'<rect x="{x - half}" y="{y - half}" width="{2 * half}" height="{2 * half}" fill="#9e9e99" stroke="#222"/>')
        parts.append(f'<text x="{x}" y="{y - half - 4}" text-anchor="middle" fill="#fff">{html.escape(site["id"])}: {site["deposited"]}</text>')
    for res in doc.get("resources", []):
        x, y = to_px(res["pos"][0], res["pos"][2])
        parts.append(f'<rect x="{x - 3}" y="{y - 3}" width="6" height="6" fill="#d9853a"><title>{html.escape(res["id"])}</title></rect>')
    lines = [f"world: {doc.get('world_id')}  seed: {doc.get('seed')}", f"schema v{doc.get('schema_version')}  revision {doc.get('revision')}",
             f"saved: {doc.get('saved_at')}", f"resources on the ground: {len(doc.get('resources', []))}", "", "contributors:"]
    for site in doc.get("sites", []):
        for name, count in sorted(site.get("contributors", {}).items(), key=lambda kv: -kv[1]):
            lines.append(f"  {name}: {count}")
    for i, text in enumerate(lines):
        parts.append(f'<text x="{size + 12:.0f}" y="{20 + 16 * i}">{html.escape(text)}</text>')
    parts.append("</svg>")
    return "\n".join(parts)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("world")
    parser.add_argument("-o", "--output", help="SVG path (default: next to the input)")
    args = parser.parse_args()
    source = Path(args.world)
    out = Path(args.output) if args.output else source.with_suffix(".svg")
    out.write_text(render(json.loads(source.read_text(encoding="utf-8"))), encoding="utf-8")
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
