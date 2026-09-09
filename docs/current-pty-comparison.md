# Current private PTY comparison — 2026-09-06

The retained vjw4 checkpoint is compared with the pinned Foot 1.27.0 and Monstar 1.1.0 builds in one private Weston 16.0.0 GL compositor (4096×2160). NVIDIA RTX 4090/595.91.07 and exact executable/helper/fontconfig hashes are recorded in `bench/current-pty-matrix.json`. No user-desktop windows were opened.

Two reversed terminal orders, both grids and five workloads yield 900 measured barriers across 180 measured launches plus 60 warmup launches. Each invocation has one warmup launch, three measured launches and five intervals per launch. Payloads request 65,536 bytes and round down to whole patterns; each raw file records the actual count. Geometry remains stable at the requested character grid for every recorded sample.

The table shows pooled median / nearest-rank p90 in milliseconds (30 intervals per cell). `bench/current-pty-summary.json` also retains each round, each five-sample launch, extrema, raw hashes, fixed historical comparisons and the current better-comparator checks. Launch durations include the workload and settling; they are not startup measurements.

| Grid | Workload | Foot median / p90 | Monstar median / p90 | cudaterm median / p90 | Cudaterm misses current pooled comparator |
| --- | --- | ---: | ---: | ---: | --- |
| 80×24 | text | 0.571 / 0.649 | 0.809 / 0.861 | 0.284 / 1.099 | p90 |
| 80×24 | ansi | 0.607 / 0.674 | 1.087 / 1.171 | 0.384 / 1.283 | p90 |
| 80×24 | unicode | 0.806 / 0.877 | 0.915 / 0.976 | 0.426 / 1.161 | p90 |
| 80×24 | graphics | 0.639 / 1.181 | 2.009 / 2.109 | 0.424 / 1.301 | p90 |
| 80×24 | tabs | 0.305 / 1.372 | 2.049 / 2.210 | 0.394 / 1.264 | median |
| 318×89 | text | 1.563 / 1.778 | 2.568 / 2.775 | 0.347 / 1.265 | none |
| 318×89 | ansi | 1.491 / 1.687 | 2.700 / 2.832 | 0.336 / 1.377 | none |
| 318×89 | unicode | 1.665 / 1.796 | 2.458 / 2.669 | 0.467 / 1.369 | none |
| 318×89 | graphics | 1.452 / 3.111 | 5.338 / 5.815 | 0.528 / 1.453 | none |
| 318×89 | tabs | 0.647 / 3.802 | 6.495 / 7.048 | 0.522 / 1.373 | none |

All five large-grid workloads meet the contemporaneous better-comparator median and p90 in both rounds. At the small grid, text/ANSI/Unicode/DEC-graphics p90 misses persist in both rounds; tabs median misses both rounds and tabs p90 misses the second. Pooled wins do not erase those round-level misses.

Fixed historical gates remain unchanged. At the historical 318×89 grid, only Unicode meets both archived median/p90 limits; the other four workloads miss both. The new compositor, configuration and sample distribution differ from the archive, so contemporary and historical checks remain separate. The 80×24 historical-reference numbers are comparisons only, not a matched historical small-grid baseline.

Fonts, pixel geometry and history policy are not identical across clients: Foot/Monstar use explicitly configured DejaVu, cudaterm uses its bitmap atlas; Monstar history is byte-limited. Loaded fallback glyphs remain unverified. “Graphics” here means DEC special line-drawing characters, not image uploads. CSI6n completes a PTY/parser barrier, not a compositor observation or physical display event. This is not display or full performance parity.

## First-interval diagnostic

Across the uninstrumented matrix, all 60 first cudaterm intervals exceed 1 ms, versus four of the remaining 240 intervals. One additional instrumented small-grid text launch (`bench/current-pty-burst-trace.json` and `.csv`) has a 1.131 ms first barrier, including 0.560 ms overlap with `gl_texture_swap`, 0.387 ms with feed processing and 0.013 ms with event waiting. Later barriers span 0.213–0.371 ms. The trace writes synchronously and is diagnostic, not an acceptance run.

The helper sends an initialization cursor query after settling. The trace shows a four-byte feed for that query, followed by a render/texture update/draw/swap that overlaps the first payload. `src/main.cu` marks every nonempty feed dirty; this supports investigating redundant query-triggered redraw. It does not prove all tail latency has one cause. Engine feeds also invalidate selection and content generations, so merely skipping presentation based on byte count could leave visible state stale. A fix must use CUDA-derived state information and preserve selection/search, split-input and synchronized-update behavior.

## Follow-up experiment

The GPU-derived query-redraw candidate was rejected and the retained vjw4
checkpoint restored. Its separate 900-barrier matrix and unchanged-limit
evaluation are in `bench/query-redraw-pty-summary.json` and
`bench/query-redraw-evaluation.json`. The first reply improved while rendering
cost moved into the next reply; most pooled medians rose and fixed targets
remained unmet. The trace is diagnostic, not a display measurement. Further
scheduling work requires paired parser and frame-submission evidence.

The baseline helper bytes now live in `bench/current_pty_matrix_baseline.py`.
Regenerate this report's JSON with `nix develop --command python3
bench/current_pty_summary.py --matrix bench/current-pty-matrix.json --helper
bench/current_pty_matrix_baseline.py --output <new-summary.json>`. Use the
refactored `bench/current_pty_matrix.py` for candidate summaries and new runs.
