# Current private PTY comparison — 2026-09-06

Cudaterm is compared with Foot 1.27.0 and Monstar 1.1.0 in one private Weston 16.0.0 GL compositor (4096×2160) on an NVIDIA RTX 4090 (driver 595.91.07). Each interval writes a payload and times until the CSI 6 n cursor report returns. Payloads request 65,536 bytes and round down to whole patterns.

The table shows pooled median / nearest-rank p90 in milliseconds. Each cell pools 30 intervals: two rounds in reversed terminal order, each with one warmup launch and three measured launches of five intervals.

| Grid | Workload | Foot median / p90 | Monstar median / p90 | cudaterm median / p90 | Cudaterm misses better comparator |
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

All five large-grid workloads meet the better comparator's median and p90 in both rounds. At the small grid, text/ANSI/Unicode/DEC-graphics p90 misses persist in both rounds; tabs median misses both rounds and tabs p90 misses the second. Pooled wins do not erase those round-level misses.

Fonts, pixel geometry and history policy are not identical across clients: Foot/Monstar use explicitly configured DejaVu, cudaterm uses its bitmap atlas; Monstar history is byte-limited. Loaded fallback glyphs remain unverified. “Graphics” here means DEC special line-drawing characters, not image uploads. CSI 6 n completes a PTY/parser barrier, not a compositor observation or physical display event. This is not display or full performance parity.

## First interval

The first interval of every measured cudaterm launch (60) exceeds 1 ms, versus four of the remaining 240 intervals. The harness sent its initialization cursor query after settling, so the redraw for that query overlapped the first payload. This does not show that all tail latency has one cause. `bench/pty_throughput.py` now settles after the query; the comparison, including the 80×24 p90 misses, has not been re-measured.
