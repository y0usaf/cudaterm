#!/usr/bin/env python3
import json, re, sys

rx = re.compile(r'^(?:CONCURRENT_KERNEL|KERNEL) \[ *(\d+), *(\d+) \] duration (\d+), "([^"]*)", correlationId (\d+)')
out = {"records": [], "kernels": {}, "dropped_diagnostic_lines": 0,
       "malformed_kernel_lines": 0}
for path in sys.argv[1:]:
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = rx.match(line)
            if not m:
                if "dropped" in line.lower(): out["dropped_diagnostic_lines"] += 1
                if line.startswith("CONCURRENT_KERNEL") or line.startswith("KERNEL "):
                    out["malformed_kernel_lines"] += 1
                continue
            start, end, duration, name, correlation = m.groups()
            rec = {"file": path, "name": name, "start": int(start),
                   "end": int(end), "duration": int(duration),
                   "correlation": int(correlation)}
            out["records"].append(rec)
            x = out["kernels"].setdefault(name, {"count": 0, "duration_ns": 0})
            x["count"] += 1; x["duration_ns"] += int(duration)
            if int(end) < int(start) or int(duration) != int(end) - int(start):
                raise SystemExit(f"invalid kernel timing in {path}: {line}")
out["record_count"] = len(out["records"])
if not out["records"] or out["malformed_kernel_lines"]:
    raise SystemExit("no valid kernel records or malformed kernel lines")
print(json.dumps(out, indent=2, sort_keys=True))
