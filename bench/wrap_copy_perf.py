#!/usr/bin/env python3
"""Deferred headless feed pair for wrap-aware selection work.

This script only runs the CUDA engine benchmark binary. It does not open a
window or use a PTY. Keep raw benchmark stdout in the output for auditability.
"""

import argparse
import hashlib
import json
import math
import os
import pathlib
import subprocess
import sys
from datetime import datetime, timezone


DEFAULT_BEFORE = "/nix/store/pqajw1ksh35f4l6l8k1pqjglm8z6614x-cudaterm-0.1.0/bin/cudaterm-engine-bench"
WORKLOADS = ("text", "ansi", "unicode")


def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def distribution(result):
    values = sorted(sample["duration_ns"] / 1e6 for sample in result["samples"])
    p90 = values[max(0, math.ceil(len(values) * 0.90) - 1)]
    return {
        "n": len(values),
        "min_ms": values[0],
        "median_ms": values[len(values) // 2]
        if len(values) % 2
        else (values[len(values) // 2 - 1] + values[len(values) // 2]) / 2,
        "p90_ms": p90,
        "max_ms": values[-1],
    }


def run(binary, workload, args, round_number):
    command = [
        binary,
        "--workload",
        workload,
        "--cols",
        str(args.cols),
        "--rows",
        str(args.rows),
        "--bytes",
        str(args.bytes),
        "--warmup",
        str(args.warmup),
        "--repeats",
        str(args.repeats),
    ]
    completed = subprocess.run(command, check=False, text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if completed.returncode:
        raise RuntimeError(
            f"benchmark failed ({completed.returncode}): {' '.join(command)}\n"
            f"stderr: {completed.stderr}"
        )
    try:
        result = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError(f"benchmark stdout was not JSON: {error}") from error
    return {
        "round": round_number,
        "workload": workload,
        "binary": os.path.realpath(binary),
        "command": command,
        "stderr": completed.stderr,
        "stdout": completed.stdout,
        "result": result,
        "distribution_ms": distribution(result),
    }


def main(args):
    started_utc = datetime.now(timezone.utc).isoformat()
    for binary in (args.before, args.after):
        if not os.path.isfile(binary) or not os.access(binary, os.X_OK):
            raise SystemExit(f"executable not found: {binary}")
    records = []
    rounds = ((args.before, args.after), (args.after, args.before))
    for round_number, order in enumerate(rounds):
        for binary in order:
            for workload in WORKLOADS:
                records.append(run(binary, workload, args, round_number))
    report = {
        "benchmark": "headless-wrap-copy-feed-pair",
        "started_utc": started_utc,
        "finished_utc": datetime.now(timezone.utc).isoformat(),
        "scope": "CUDA engine feed only; no PTY, window, compositor, or display",
        "geometry": {"cols": args.cols, "rows": args.rows},
        "requested_bytes": args.bytes,
        "warmup": args.warmup,
        "repeats": args.repeats,
        "before": {"path": os.path.realpath(args.before), "sha256": digest(args.before)},
        "after": {"path": os.path.realpath(args.after), "sha256": digest(args.after)},
        "round_order": [[os.path.realpath(binary) for binary in order] for order in rounds],
        "records": records,
        "limitations": "Feed completion includes host/device transfer and synchronization; it is not copy, frame, or display latency.",
    }
    output = pathlib.Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--after", required=True,
                        help="new cudaterm-engine-bench executable")
    parser.add_argument("--before", default=DEFAULT_BEFORE,
                        help="historical cudaterm-engine-bench executable")
    parser.add_argument("--output", required=True)
    parser.add_argument("--cols", type=int, default=318)
    parser.add_argument("--rows", type=int, default=89)
    parser.add_argument("--bytes", type=int, default=65536)
    parser.add_argument("--warmup", type=int, default=2000)
    parser.add_argument("--repeats", type=int, default=40)
    parsed = parser.parse_args()
    if min(parsed.cols, parsed.rows, parsed.bytes, parsed.warmup, parsed.repeats) <= 0:
        parser.error("geometry, bytes, warmup, and repeats must be positive")
    main(parsed)
