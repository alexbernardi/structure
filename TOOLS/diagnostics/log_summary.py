"""Summarise a STRUCTURE JSON-lines log: time span, events by type, levels, engine errors, metrics statistics.

usage: python TOOLS/diagnostics/log_summary.py <logfile | -> [--evt EVENT] [--limit N]
  e.g. python TOOLS/cli/structure.py env logs dev --tail 5000 | python TOOLS/diagnostics/log_summary.py -
"""
from __future__ import annotations

import argparse
import collections
import json
import statistics
import sys


def summarise(lines, evt: str | None = None, limit: int = 10) -> dict:
    counts, levels = collections.Counter(), collections.Counter()
    engine_errors, metrics, selected = [], [], []
    first = last = None
    for raw in lines:
        line = raw.strip()
        if line.startswith(("ERROR:", "SCRIPT ERROR:")):
            engine_errors.append(line)
            continue
        if not line.startswith("{"):
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue
        counts[record.get("evt")] += 1
        levels[record.get("lvl")] += 1
        first = first or record.get("ts")
        last = record.get("ts")
        if record.get("evt") == "server.metrics":
            metrics.append(record)
        if evt and record.get("evt") == evt:
            selected.append(record)

    def stat(key, fn):
        values = [m[key] for m in metrics if isinstance(m.get(key), (int, float))]
        return round(fn(values), 3) if values else None

    return {
        "span": [first, last],
        "events": dict(counts.most_common()),
        "levels": dict(levels),
        "engine_errors": engine_errors[:limit],
        "engine_error_count": len(engine_errors),
        "metrics": {
            "intervals": len(metrics),
            "tick_avg_ms_mean": stat("tick_avg_ms", statistics.mean),
            "tick_p95_ms_max": stat("tick_p95_ms", max),
            "cpu_pct_mean": stat("cpu_pct", statistics.mean),
            "rss_mb_max": stat("rss_mb", max),
            "players_max": stat("players", max),
            "net_out_bps_mean": stat("net_out_bps", statistics.mean),
        } if metrics else None,
        "selected": selected[-limit:],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("path", help="log file, or - for stdin")
    parser.add_argument("--evt", help="also print the last N events of this type")
    parser.add_argument("--limit", type=int, default=10)
    args = parser.parse_args()
    stream = sys.stdin if args.path == "-" else open(args.path, encoding="utf-8", errors="replace")
    with stream:
        print(json.dumps(summarise(stream, args.evt, args.limit), indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
