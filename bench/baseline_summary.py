#!/usr/bin/env python3
"""Print reproducible distributions from a pty-block-scan archive."""
import hashlib
import json
import math
import pathlib
import statistics
import sys


def percentile(values, fraction):
    values = sorted(values)
    return values[max(0, math.ceil(fraction * len(values)) - 1)]


def main(path):
    raw = pathlib.Path(path).read_bytes()
    data = json.loads(raw)
    print(f"input={path} sha256={hashlib.sha256(raw).hexdigest()}")
    by_key = {}
    for run in data["runs"]:
        # The archive intentionally leaves label null; identify the executable
        # from the recorded command/path instead of guessing from ordering.
        terminal = next(name for name in ("foot", "monstar", "cudaterm")
                        if name in run["terminal_resolved"])
        by_key.setdefault((terminal, run["workload"]), []).extend(
            run["sample_barrier_ns"]
        )
    for workload in ("text", "ansi", "unicode", "graphics", "tabs"):
        for terminal in ("foot", "monstar", "cudaterm"):
            values = by_key[(terminal, workload)]
            ms = [value / 1e6 for value in values]
            print(
                f"{terminal} {workload} n={len(ms)} "
                f"min={min(ms):.3f} median={statistics.median(ms):.3f} "
                f"p90={percentile(ms, .90):.3f} max={max(ms):.3f}"
            )


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} ARCHIVE.json")
    main(sys.argv[1])
