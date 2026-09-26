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
history capture, and explicit LF clearing before acceptance.

Across three CUPTI kernel traces, setup and warmup included, `plain_scatter`
totals 560,294 ns and `plain_wrap_metadata` 256,962 ns over 75 launches each;
instrumented time is not an acceptance benchmark.
`prepare_history` and `styled_paint` are larger aggregate costs than
`plain_wrap_metadata`, so fusion is only a profiling-guided secondary target.

Compare before/after binaries in reversed paired rounds with equal realized
payloads and no concurrent GPU work. If Nsight is available, profile the
headless engine benchmark (`nix run .#bench -- --bytes 65536`) with
`nsys profile` for kernel launch timing and `ncu --kernel-name
plain_wrap_metadata` for achieved occupancy and memory throughput; do not use
desktop windows for this profile.
