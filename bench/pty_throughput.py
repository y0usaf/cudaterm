#!/usr/bin/env python3
"""End-to-end terminal PTY throughput benchmark.

The child is run inside a terminal emulator.  For every sample it writes a
known number of bytes, asks the emulator for its cursor position (CSI 6 n),
and waits for the matching cursor report.  Because the report is generated
after the query in the terminal input stream, it is a useful barrier for
terminal parsing.  It does not wait for a compositor frame.
"""

import argparse
import json
import os
import re
import selectors
import subprocess
import sys
import tempfile
import termios
import tty
import platform
import time
import shutil
from pathlib import Path

REPORT = re.compile(rb"\x1b\[[0-9]+;[0-9]+R")


def write_all(fd: int, data: bytes) -> None:
    view = memoryview(data)
    while view:
        view = view[os.write(fd, view):]


def wait_for_report(selector: selectors.BaseSelector, fd: int, timeout: float) -> None:
    response = bytearray()
    deadline = time.monotonic() + timeout
    while not REPORT.search(response):
        left = deadline - time.monotonic()
        if left <= 0 or not selector.select(left):
            raise TimeoutError("timed out waiting for CSI 6 n response")
        chunk = os.read(fd, 4096)
        if not chunk:
            raise EOFError("terminal closed the child PTY")
        response.extend(chunk)
        if len(response) > 65536:
            raise RuntimeError("unexpected input while waiting for cursor reply")


def child_main(args: argparse.Namespace) -> int:
    patterns = {
        "tabs": b"column\tvalue\r\n",
        "graphics": b"\x1b[32mlqqqqqqk\x1b[0m\r\n",
        "text": b"0123456789abcdefghijklmnopqrstuvwxyz\r\n",
        "ansi": b"\x1b[31mred\x1b[0m \x1b[38;2;10;200;70mgreen\x1b[0m\r\n",
        "unicode": "Latin é Ελληνικά 日本語 😀\r\n".encode(),
    }
    pattern = patterns[args.workload]
    # Keep escape sequences and UTF-8 intact at the end of each payload.
    framing = 6 if args.workload == "graphics" else 0
    payload = pattern * max(1, (args.payload_bytes - framing) // len(pattern))
    if args.workload == "graphics":
        payload = b"\x1b(0" + payload + b"\x1b(B"
    if args.payload_bytes == 0:
        payload = b""  # Isolate the PTY/query/reply path without output load.
    samples = []
    fd = sys.stdin.fileno()
    previous = termios.tcgetattr(fd)
    tty.setraw(fd)  # DSR replies have no newline; canonical mode would deadlock.
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(fd, selectors.EVENT_READ)
            # Record the actual grid, and remove initial terminal output.
            write_all(sys.stdout.fileno(), b"\x1b[2J\x1b[H")
            if args.settle_seconds:
                time.sleep(args.settle_seconds)
            init_started = time.perf_counter_ns()
            write_all(sys.stdout.fileno(), b"\x1b[6n")
            wait_for_report(selector, fd, args.timeout)
            init_barrier_ns = time.perf_counter_ns() - init_started
            initial_geometry = os.get_terminal_size(fd)
            for _ in range(args.iterations):
                before = os.get_terminal_size(fd)
                started = time.perf_counter_ns()
                if args.write_chunk:
                    for offset in range(0, len(payload), args.write_chunk):
                        write_all(sys.stdout.fileno(), payload[offset:offset + args.write_chunk])
                else:
                    write_all(sys.stdout.fileno(), payload)
                payload_write_ns = time.perf_counter_ns() - started
                write_all(sys.stdout.fileno(), b"\x1b[6n")
                wait_for_report(selector, fd, args.timeout)
                after = os.get_terminal_size(fd)
                if before != after:
                    raise RuntimeError("terminal geometry changed during a sample")
                ended = time.perf_counter_ns()
                samples.append({"bytes": len(payload),
                                "payload_write_ns": payload_write_ns,
                                "barrier_ns": ended - started,
                                "sample_start_ns": started,
                                "sample_end_ns": ended,
                                "geometry_before": {"cols": before.columns, "rows": before.lines},
                                "geometry_after": {"cols": after.columns, "rows": after.lines}})
        if args.result:
            size = os.get_terminal_size(fd)
            result = {"samples": samples, "payload_bytes": len(payload),
                      "cols": size.columns, "rows": size.lines,
                      "initial_geometry": {"cols": initial_geometry.columns, "rows": initial_geometry.lines},
                      "init_barrier_ns": init_barrier_ns}
            Path(args.result).write_text(json.dumps(result), encoding="utf-8")
    finally:
        termios.tcsetattr(fd, termios.TCSANOW, previous)
    return 0


def run(args: argparse.Namespace) -> dict:
    command = [args.terminal, *args.terminal_arg]
    resolved = shutil.which(command[0])
    if resolved:
        resolved = str(Path(resolved).resolve())
    all_samples = []
    launches = []
    with tempfile.TemporaryDirectory(prefix="cudaterm-bench-") as directory:
        for index in range(args.warmup + args.repeat):
            result_path = Path(directory) / f"sample-{index}.json"
            child = [sys.executable, str(Path(__file__).resolve()), "--child",
                     "--iterations", str(args.iterations),
                     "--payload-bytes", str(args.payload_bytes),
                     "--write-chunk", str(args.write_chunk),
                     "--timeout", str(args.timeout), "--workload", args.workload,
                     "--settle-seconds", str(args.settle_seconds),
                     "--result", str(result_path)]
            started = time.perf_counter_ns()
            process = subprocess.run(command + child, check=False,
                                     stdout=subprocess.DEVNULL,
                                     stderr=subprocess.PIPE, timeout=args.timeout * args.iterations + 10)
            launch_ns = time.perf_counter_ns() - started
            child_error = None
            if result_path.exists():
                try:
                    diagnostic = json.loads(result_path.read_text(encoding="utf-8"))
                except (OSError, json.JSONDecodeError):
                    diagnostic = None
                if isinstance(diagnostic, dict):
                    child_error = diagnostic.get("error")
            if process.returncode:
                detail = process.stderr.decode(errors="replace").strip()
                details = [f"terminal exited {process.returncode}"]
                if child_error:
                    details.append(f"child: {child_error}")
                if detail:
                    details.append(f"terminal stderr: {detail}")
                raise RuntimeError("; ".join(details))
            if child_error:
                raise RuntimeError(f"benchmark child failed: {child_error}")
            sample = json.loads(result_path.read_text(encoding="utf-8"))
            geometries = {(item["geometry_before"]["cols"], item["geometry_before"]["rows"],
                           item["geometry_after"]["cols"], item["geometry_after"]["rows"])
                          for item in sample["samples"]}
            if any((before_cols, before_rows) != (after_cols, after_rows)
                   for before_cols, before_rows, after_cols, after_rows in geometries):
                raise RuntimeError("terminal geometry changed during a sample")
            if args.expected_cols is not None or args.expected_rows is not None:
                expected = (args.expected_cols if args.expected_cols is not None else sample["cols"],
                            args.expected_rows if args.expected_rows is not None else sample["rows"])
                if (sample["cols"], sample["rows"]) != expected:
                    raise RuntimeError(f"terminal geometry {sample['cols']}x{sample['rows']} does not match expected {expected[0]}x{expected[1]}")
                if any((cols, rows) != expected for cols, rows, _, _ in geometries):
                    raise RuntimeError("sample geometry does not match expected "
                                       f"{expected[0]}x{expected[1]}")
            if index >= args.warmup:
                all_samples.append(sample)
                launches.append(launch_ns)
    barriers = [s["barrier_ns"] for s in all_samples for s in s["samples"]]
    bytes_per_sample = all_samples[0]["payload_bytes"]
    return {
        "benchmark": "pty-throughput-csi6n",
        "terminal": command,
        "terminal_resolved": resolved,
        "label": args.label,
        "workload": args.workload,
        "host": platform.platform(),
        "geometry": [{"cols": s["cols"], "rows": s["rows"]} for s in all_samples],
        "sample_geometry": [[item["geometry_before"], item["geometry_after"]]
                            for s in all_samples for item in s["samples"]],
        "repeat": args.repeat,
        "warmup": args.warmup,
        "iterations": args.iterations,
        "payload_bytes": bytes_per_sample,
        "requested_payload_bytes": args.payload_bytes,
        "sample_barrier_ns": barriers,
        "sample_start_ns": [item["sample_start_ns"]
                            for sample in all_samples for item in sample["samples"]],
        "sample_end_ns": [item["sample_end_ns"]
                          for sample in all_samples for item in sample["samples"]],
        "write_chunk": args.write_chunk,
        "sample_payload_write_ns": [item["payload_write_ns"]
                                    for sample in all_samples for item in sample["samples"]],
        "sample_launch_ns": launches,
        "barrier_throughput_bytes_per_second": [
            bytes_per_sample * 1_000_000_000 / elapsed for elapsed in barriers
        ],
        "protocol": "payload followed by CSI 6 n; wait for CSI row;column R",
        "settle_seconds": args.settle_seconds,
    }


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--terminal", default="foot", help="terminal executable")
    p.add_argument("--terminal-arg", action="append", default=[],
                   help="argument passed before the child command (repeatable; e.g. --terminal-arg=-e)")
    p.add_argument("--workload", choices=["text", "ansi", "unicode", "graphics", "tabs"], default="text")
    p.add_argument("--repeat", type=int, default=5)
    p.add_argument("--warmup", type=int, default=1)
    p.add_argument("--iterations", type=int, default=10)
    p.add_argument("--payload-bytes", type=int, default=65536,
                   help="requested output bytes; zero measures the cursor query alone")
    p.add_argument("--write-chunk", type=int, default=0,
                   help="maximum bytes per application payload write; zero sends whole payload")
    p.add_argument("--timeout", type=float, default=10.0)
    p.add_argument("--settle-seconds", type=float, default=0.2)
    p.add_argument("--expected-cols", type=int)
    p.add_argument("--expected-rows", type=int)
    p.add_argument("--label", help="metadata label; never executed")
    p.add_argument("--json", action="store_true", help="print JSON only")
    p.add_argument("--child", action="store_true", help=argparse.SUPPRESS)
    p.add_argument("--result", help=argparse.SUPPRESS)
    return p


def main() -> int:
    args = parser().parse_args()
    if (args.repeat < 1 or args.iterations < 1 or args.payload_bytes < 0 or
            args.write_chunk < 0 or args.timeout <= 0 or args.warmup < 0 or args.settle_seconds < 0 or
            (args.expected_cols is not None and args.expected_cols < 1) or
            (args.expected_rows is not None and args.expected_rows < 1)):
        raise SystemExit("repeat, iterations and timeout must be positive; payload-bytes, write-chunk, warmup and settle-seconds nonnegative")
    if args.child:
        try:
            return child_main(args)
        except Exception as error:
            # The child runs inside the terminal, so its stderr is terminal
            # input and is not available to the parent process. Preserve the
            # original failure in the result file before propagating it.
            if args.result:
                Path(args.result).write_text(
                    json.dumps({"error": f"{type(error).__name__}: {error}"}),
                    encoding="utf-8")
            raise
    print(json.dumps(run(args), indent=None if args.json else 2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (TimeoutError, EOFError, subprocess.TimeoutExpired, RuntimeError) as error:
        print(f"benchmark failed: {error}", file=sys.stderr)
        raise SystemExit(1)
