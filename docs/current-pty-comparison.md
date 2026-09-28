# Current private PTY comparison — 2026-09-28

Cudaterm is compared with Foot 1.27.0 and Monstar 1.1.0 in one private Weston 16.0.0 GL compositor (4096×2160, headless seat) on an NVIDIA RTX 4090 (driver 595.91.07). Each interval writes a payload and times until the CSI 6 n cursor report returns. Payloads request 65,536 bytes and round down to whole patterns. Cudaterm runs `--no-config --font-family bitmap`; Foot and Monstar use explicitly configured DejaVu from a pinned fontconfig.

The table shows pooled median / nearest-rank p90 in milliseconds. Each cell pools 30 intervals: two rounds in reversed terminal order, each with one warmup launch and three measured launches of five intervals. The same rounds measured the previous cudaterm (8e8dd4c) beside the current one.

| Grid | Workload | Foot median / p90 | Monstar median / p90 | cudaterm 8e8dd4c | cudaterm current | Current misses better comparator |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| 80×24 | text | 0.566 / 0.657 | 0.841 / 0.948 | 0.351 / 0.636 | 0.342 / 0.580 | none |
| 80×24 | ansi | 0.668 / 0.942 | 1.039 / 1.133 | 0.434 / 0.779 | 0.300 / 0.564 | none |
| 80×24 | unicode | 1.057 / 1.408 | 0.915 / 1.141 | 0.315 / 0.798 | 0.367 / 0.679 | none |
| 80×24 | graphics | 0.969 / 1.668 | 2.391 / 3.010 | 0.649 / 0.862 | 0.450 / 0.843 | none |
| 80×24 | tabs | 0.700 / 1.771 | 2.365 / 3.051 | 0.400 / 0.808 | 0.279 / 0.605 | none |
| 318×89 | text | 1.484 / 1.629 | 3.372 / 4.031 | 0.518 / 0.987 | 0.358 / 0.662 | none |
| 318×89 | ansi | 1.493 / 1.780 | 2.647 / 2.783 | 0.547 / 0.808 | 0.309 / 0.641 | none |
| 318×89 | unicode | 1.690 / 1.844 | 3.281 / 3.726 | 0.709 / 1.102 | 0.505 / 0.853 | none |
| 318×89 | graphics | 2.464 / 4.068 | 5.477 / 7.971 | 0.745 / 1.184 | 0.513 / 0.697 | none |
| 318×89 | tabs | 1.897 / 4.636 | 6.847 / 10.374 | 0.648 / 1.028 | 0.512 / 0.731 | none |

Round by round, the current build meets Foot's median and p90 everywhere except two 80×24 p90s of the first round: text 0.753 against 0.704 and unicode 0.974 against 0.887. Pooled wins do not erase those round-level misses. Foot's 80×24 tabs median moves between rounds (0.302, 0.777); cudaterm's is 0.279 and 0.276.

With five intervals per launch, the first interval dominates cudaterm's p90. After 0.2 s of settling the GPU has been idle, and the first submission after about 200 µs without work completes 0.45–0.75 ms late on this shared GPU; Foot parses on the CPU and does not pay it. Later intervals take 0.2–0.35 ms at 80×24.

Launch to the first buffer committed on the terminal's toplevel surface (WAYLAND_DEBUG, 80×24, 12 warm launches in alternating order, median): Foot 10.2 ms, cudaterm 8e8dd4c 57.1 ms, current 47.7 ms with the bitmap font. In the same period a process that only creates a CUDA context returned from `cudaFree(0)` after 29.3 ms. Peak RSS: Foot 12.9 MiB, cudaterm 127.4 → 120.2 MiB.

Fonts, pixel geometry and history policy are not identical across clients; Monstar history is byte-limited. “Graphics” means DEC special line-drawing characters, not image uploads. CSI 6 n completes a PTY/parser barrier, not a compositor observation or physical display event. This is not display or full performance parity.
