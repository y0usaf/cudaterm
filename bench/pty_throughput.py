#!/usr/bin/env python3
import argparse
import json
import os
import re
import selectors
import statistics
import subprocess
import sys
import tempfile
import termios
import time
import tty
from pathlib import Path

REPORT = re.compile(rb"\x1b\[[0-9]+;[0-9]+R")
PATTERNS = {
    "tabs": b"column\tvalue\r\n",
    "graphics": b"\x1b[32mlqqqqqqk\x1b[0m\r\n",
    "text": b"0123456789abcdefghijklmnopqrstuvwxyz\r\n",
    "ansi": b"\x1b[31mred\x1b[0m \x1b[38;2;10;200;70mgreen\x1b[0m\r\n",
    "unicode": "Latin é Ελληνικά 日本語 😀\r\n".encode(),
}


def write_all(fd, data):
    view = memoryview(data)
    while view:
        view = view[os.write(fd, view):]


def barrier(selector, fd, timeout):
    write_all(sys.stdout.fileno(), b"\x1b[6n")
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


def payload(workload, size):
    if size == 0:
        return b""
    pattern = PATTERNS[workload]
    if workload == "graphics":
        return b"\x1b(0" + pattern * max(1, (size - 6) // len(pattern)) + b"\x1b(B"
    return pattern * max(1, size // len(pattern))


def child(args):
    data = payload(args.workload, args.payload_bytes)
    fd = sys.stdin.fileno()
    previous = termios.tcgetattr(fd)
    tty.setraw(fd)
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(fd, selectors.EVENT_READ)
            write_all(sys.stdout.fileno(), b"\x1b[2J\x1b[H")
            barrier(selector, fd, args.timeout)
            time.sleep(args.settle_seconds)
            geometry = os.get_terminal_size(fd)
            samples = []
            for _ in range(args.iterations):
                started = time.perf_counter_ns()
                write_all(sys.stdout.fileno(), data)
                barrier(selector, fd, args.timeout)
                samples.append(time.perf_counter_ns() - started)
                if os.get_terminal_size(fd) != geometry:
                    raise RuntimeError("terminal geometry changed during a sample")
    finally:
        termios.tcsetattr(fd, termios.TCSANOW, previous)
    return {"barrier_ns": samples, "payload_bytes": len(data),
            "cols": geometry.columns, "rows": geometry.lines}


def launch(args, command, result_path):
    argv = [sys.executable, str(Path(__file__).resolve()), "--child", "--result", str(result_path),
            "--iterations", str(args.iterations), "--payload-bytes", str(args.payload_bytes),
            "--timeout", str(args.timeout), "--workload", args.workload,
            "--settle-seconds", str(args.settle_seconds)]
    process = subprocess.run(command + argv, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                             timeout=args.settle_seconds + args.timeout * (args.iterations + 1) + 10)
    try:
        result = json.loads(result_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        result = {"error": "no result file"}
    if process.returncode or "error" in result:
        stderr = process.stderr.decode(errors="replace").strip()
        raise RuntimeError(f"terminal exited {process.returncode}: {result.get('error', '')} {stderr}".strip())
    expected = (args.expected_cols or result["cols"], args.expected_rows or result["rows"])
    if (result["cols"], result["rows"]) != expected:
        raise RuntimeError(f"terminal geometry {result['cols']}x{result['rows']} "
                           f"does not match expected {expected[0]}x{expected[1]}")
    return result


def run(args):
    command = [args.terminal, *args.terminal_arg]
    results = []
    with tempfile.TemporaryDirectory(prefix="pty-throughput-") as directory:
        for index in range(args.warmup + args.repeat):
            result = launch(args, command, Path(directory) / f"{index}.json")
            if index >= args.warmup:
                results.append(result)
    barriers = sorted(ns for r in results for ns in r["barrier_ns"])
    return {
        "terminal": command,
        "workload": args.workload,
        "payload_bytes": results[0]["payload_bytes"],
        "cols": results[0]["cols"],
        "rows": results[0]["rows"],
        "median_ns": int(statistics.median(barriers)),
        "p90_ns": barriers[max(0, -(-9 * len(barriers) // 10) - 1)],
        "min_ns": barriers[0],
        "max_ns": barriers[-1],
        "launches": [r["barrier_ns"] for r in results],
    }


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--terminal", default="foot")
    p.add_argument("--terminal-arg", action="append", default=[])
    p.add_argument("--workload", choices=sorted(PATTERNS), default="text")
    p.add_argument("--repeat", type=int, default=5)
    p.add_argument("--warmup", type=int, default=1)
    p.add_argument("--iterations", type=int, default=10)
    p.add_argument("--payload-bytes", type=int, default=65536)
    p.add_argument("--timeout", type=float, default=10.0)
    p.add_argument("--settle-seconds", type=float, default=0.2)
    p.add_argument("--expected-cols", type=int)
    p.add_argument("--expected-rows", type=int)
    p.add_argument("--child", action="store_true", help=argparse.SUPPRESS)
    p.add_argument("--result", help=argparse.SUPPRESS)
    args = p.parse_args()
    if (args.repeat < 1 or args.iterations < 1 or args.timeout <= 0 or args.payload_bytes < 0
            or args.warmup < 0 or args.settle_seconds < 0
            or any(v is not None and v < 1 for v in (args.expected_cols, args.expected_rows))):
        p.error("repeat, iterations, timeout and expected sizes must be positive; "
                "payload-bytes, warmup and settle-seconds nonnegative")
    if not args.child:
        print(json.dumps(run(args)))
        return
    try:
        result = child(args)
    except Exception as error:
        result = {"error": f"{type(error).__name__}: {error}"}
    Path(args.result).write_text(json.dumps(result), encoding="utf-8")


if __name__ == "__main__":
    try:
        main()
    except (TimeoutError, EOFError, subprocess.TimeoutExpired, RuntimeError) as error:
        sys.exit(f"pty_throughput: {error}")
