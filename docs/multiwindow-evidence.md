# Private one/three-window resource baseline

The provisional 055j2 build, pinned Foot 1.27.0 and Monstar 1.1.0 each ran at
80×24 and 318×89 in two reversed terminal orders. Every group uses a fresh
private Weston 16 GL compositor (4096×2160), launches one then three concurrent
processes, samples each populated stage three times, closes all windows and
samples the empty compositor again. All 36 parents exited zero and their child
processes were absent after reaping. Character geometry was verified by the
PTY child; this is not a screenshot or presentation-latency check.

The table shows median aggregate terminal-parent PSS in decimal MB (six
settled samples per cell). Child and compositor costs remain separate in the
raw report. Sum of RSS is not unique physical memory; PSS changes with sharing,
and these snapshots are read sequentially, not atomically.

| Grid | Terminal | One parent PSS MB | Three parents PSS MB | NVIDIA compute MiB, one / three |
| --- | --- | ---: | ---: | --- |
| 80×24 | foot | 5.50 | 12.56 | unknown / unknown |
| 80×24 | monstar | 9.86 | 21.14 | unknown / unknown |
| 80×24 | cudaterm | 80.36 | 223.32 | 242 / 726 |
| 318×89 | foot | 13.84 | 38.12 | unknown / unknown |
| 318×89 | monstar | 22.32 | 78.58 | unknown / unknown |
| 318×89 | cudaterm | 80.79 | 224.07 | 300 / 900 |

NVIDIA's compute-process list is incomplete for graphics clients. Absence for
Foot/Monstar is unknown GPU memory, never zero. The CUDA sum grows from
242/300 MiB for one small/large terminal to 726/900 MiB for three. No device
memory saving or full resource parity is established.

Weston descriptors return from the populated stages to the original 48 in all
12 groups. Post-close compositor PSS does not uniformly return to its baseline:
large-grid Monstar groups retain approximately 55–64 MB more after a 0.5-second
settle; Foot groups approximately 5 MB; cudaterm groups near 0.1 MB. These short
observations do not prove a leak or its allocator/driver owner. Compositor
state and longer settle/churn must be examined before classifying retention.

Raw per-parent/child/compositor memory, CPU counters, descriptor/thread counts,
commands, binary/helper/font hashes, GPU readings and exit status are in
`bench/multiwindow-current/report.json`. Validated distributions and lifecycle
checks are in `bench/multiwindow-current-summary.json`; Nix commands/environment
are in `bench/multiwindow-invocation.json` and `bench/multiwindow-validation.json`.
The helper fixes XDG/fontconfig paths, but font rasterization and history policy
still differ as documented in the PTY comparison. Aggregate GPU load is sampled,
not controlled. These are settled idle snapshots and short process lifecycles,
not peaks, startup timing, long scrollback/resize/graphics workloads, sustained
multiwindow responsiveness, or a full long-running leak test. Existing targets
remain unchanged and unmet.

## History/reset follow-up

`bench/multiwindow-history/report.json` adds three history/reset cycles per
window and a five-second post-close settle. All 36 parents/children exit cleanly
and all 216 operation/geometry acknowledgments pass. The workload sends 10,000
Unicode/SGR lines, then ED3/RIS; it does not verify identical history semantics
or pixels, and does not yet resize or upload images.

At 318×89, three-parent PSS after the third reset is about 132.7 MB Foot,
81.6 MB Monstar and 225.6–225.8 MB cudaterm. Cudaterm's listed GPU compute sum
falls from 1122 MiB after fill to 1002 MiB after reset, above the earlier
900 MiB idle baseline. This listing does not attribute engine versus CUDA/GL
cache/backbuffer costs. After close, compositor descriptors return to 48,
while some compositor PSS remains above baseline after five seconds. No leak
or long-running stability claim follows from these short cycles. See
`bench/multiwindow-history-summary.json` for raw stage totals and
`bench/multiwindow-history-validation.json` for Nix validation.

## Redraw-only follow-up

The recovered `bench/multiwindow-redraw/report.json` completes 12 groups and
36 clean parent/child lifecycles. Three cycles of 60 background updates per
window use parser replies, with reset after each cycle. Before the first reset,
three-parent cudaterm compute allocation rises from 726 to 729 MiB at 80×24 and
900 to 948 MiB at 318×89 in both orders; subsequent resets retain these totals.
History fill is not required for this portion of the increase. Allocation
ownership and complete graphics VRAM remain unknown. All compositor descriptor
counts return to 48 after close.

Each of the 12 cudaterm traces contains 184 lifetime swap events, not proof of
individual presented updates. No redraw command timestamps or pixel validation
are available. See `bench/multiwindow-redraw-summary.json` and
`bench/multiwindow-redraw/validation-restored.json`; both validators exited zero
through Nix. Fresh private-headless Ekko presentation and `nix flake check` also
passed (`bench/recovery-redraw-validation.json`). Resize/image cycles and
long-term retained-memory attribution remain open.

The existing redraw traces also report constant mapped PBO sizes: 983,040
bytes at 80×24 and 14,490,624 bytes at 318×89 across all 184 map events in
each process (`bench/redraw-mapped-buffer-summary.json`, extraction through
`nix develop --command python3` exited zero). These are API-visible buffer
lengths; driver backing storage can differ, so the constant size does not
attribute the extra reported GPU allocation. Source `src/main.cu` reallocates
the PBO when needed size grows or falls below half capacity, and resizes the
texture whenever framebuffer dimensions change. The next resize workload
therefore includes a large-to-small transition to exercise both paths.
