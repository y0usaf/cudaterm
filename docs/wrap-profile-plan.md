# Soft-wrap metadata profiling plan

The retained soft-wrap copy implementation adds a `plain_wrap_metadata` launch
after `plain_scatter`. That kernel assigns one thread to each CRLF-delimited
line and scans the line again to derive logical rows. The scan is linear in the
accepted prefix and duplicates byte traversal already performed by
`plain_scatter`; the launch is a second controllable cost. Styled input uses the
existing line workers and has no equivalent standalone metadata launch.

The conservative optimization candidate is to move the one-thread-per-line
metadata calculation into the line leader in `plain_scatter`. The candidate
must retain `starts`/`advances` logical row mapping and prove one writer per
logical row, rejected-prefix bounds, delayed-wrap handling, early-wide lengths,
history capture, and explicit LF clearing before acceptance. The completed
trace shows `prepare_history` and `styled_paint` are larger aggregate costs than
`plain_wrap_metadata`, so fusion is only a profiling-guided secondary target.

The CUPTI 12.9 injection library was built from the unchanged NVIDIA sample;
the redundant source copy was removed after byte-for-byte comparison.
`bench/wrap-profile-manifest.json` records the pinned sample, build and launch
commands, library and executable hashes, and provenance limitations. The sample
records all kernel activity; `bench/parse_wrap_profile.py` extracts kernel
names, timestamps and correlation IDs and validates duration arithmetic.

The three traces contain 1,359 kernel records, with zero malformed kernel lines
and no dropped-record diagnostic lines. Absence of a diagnostic is not independent
proof of complete collection. Across these traces, `plain_scatter` totals
560,294 ns over 75 launches and `plain_wrap_metadata` totals 256,962 ns over 75
launches. Setup and warmup kernels are included; instrumented wall time is not
an acceptance benchmark. Raw traces and parsed records remain under
`bench/wrap-profile-*`. The exact run-time resolution of the `result` symlink
was not captured; the rebuilt and reference benchmark binary hashes match.

Run before/after binaries in reversed paired rounds, with no concurrent GPU
tests or builds, equal realized payloads, and exact binary hashes. If Nsight is
available later, collect a short headless benchmark with `nsys profile` for
kernel launch timing and `ncu --kernel-name plain_wrap_metadata` for achieved
occupancy and memory throughput; do not use desktop windows for this profile.
