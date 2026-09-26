# Benchmarks

## PTY barrier: `pty_throughput.py`

```sh
python3 bench/pty_throughput.py --terminal ./result/bin/cudaterm \
  --terminal-arg=-e --workload text --expected-cols 318 --expected-rows 89
```

Needs only the Python standard library and a graphical session; give a
server/client terminal its standalone invocation. Each launch starts a fresh
terminal whose raw-mode child clears the screen, completes one `CSI 6 n`
barrier and sleeps `--settle-seconds` (0.2) so startup redraw misses sample 1.
Each of `--iterations` samples (10) times writing `--payload-bytes` (65536; 0
for query only) of whole `text`, `ansi`, `unicode`, `graphics` or `tabs`
patterns plus `CSI 6 n` until the cursor report, which shows the parser consumed
them. `--warmup` launches (1) precede `--repeat` ones (5); `--timeout` (10 s)
bounds each barrier. Geometry must stay fixed within a launch and match any
`--expected-cols`/`--expected-rows`. Output is one JSON line: `terminal`,
`workload`, realized `payload_bytes`, `cols`, `rows`, pooled `median_ns`,
`p90_ns`, `min_ns`, `max_ns`, and raw samples per launch in `launches`.

This covers PTY writes, terminal input, parsing, state updates and reply
generation, not compositor scheduling, GPU rendering, presentation or visible
latency; a fast reply does not by itself prove lower displayed latency. The
query-only case estimates fixed PTY scheduling, query and reply costs but still
includes any rendering done while handling queries, and
subtracting its median does not isolate parser execution. Later samples run
against the history earlier ones left. Keep window-system load, configuration,
font, size and realized payload size equal across terminals; internal output
coalescing also affects results.

## Headless engine: `engine_bench.cu`

`nix run .#bench -- --bytes 65536` drives `ct::Engine` without PTY or display
and needs a GPU. Options: `--cols` (80), `--rows` (24), `--bytes` (4096, max
1048576), `--warmup` (1), `--repeats` (5), and `--workload` from the PTY set
plus `emoji` (U+1F600), `marks` (`e`+U+0301, `e`+U+1D185), `query` (repeated
`CSI 6 n`) and `insert` (ASCII inside `CSI 4 h`/`l`). It prints one JSON object
of raw samples, no aggregates. Samples share one engine, so later ones run
against earlier history. By default each sample is the host wall time of
`Engine::feed` (copy, parser kernel, completion sync) as `duration_ns` and
`ns_per_byte`. `--replies` times `Engine::feed_and_replies` including reply
transfer (empty for non-`query` workloads); its final reset kernel runs asynchronously ahead of the next sample,
and larger `query` payloads can reach the 4096-byte reply capacity. `--render`
feeds once, then times `Engine::render` into 8×16-pixel cells with CUDA events
(`ns_per_pixel`), which can include device scheduling and launch gaps,
excluding PTY, OpenGL, compositor and presentation; `--dense`
drops CRLF so text wraps. Short warmups showed large clock variation: warm up
long, alternate build order across rounds, and run nothing else on the GPU.

## Startup: `startup.py`

```sh
nix run .#startup-benchmark -- --terminal label=/abs/path/bin/cudaterm \
  --args opts.json --output DIR
```

Starts a private headless Weston with the seat module, then launches each
`--terminal` (repeatable) with the `--args` JSON option array and a fixed child
that prints styled text and exits after 0.25 s. `--cold-samples` (2) delete the
label's font cache first; `--samples` (9) warm launches alternate order. Each
launch records time to the end of the first `gl_texture_swap`, CPU time, peak
RSS, `smaps_rollup` memory at least 50 ms after that swap, and `startup_*`
stages. Rows stream to stdout; `DIR` gets `results.json` with rows and medians,
per-launch trace CSVs and `weston.log`. This is launch to first swap return,
not presentation; cold means no font cache, not a cold filesystem or GPU.
`CUDATERM_TRACE=/path.csv` works on any launch and overwrites that file with
steady-clock `start_ns,end_ns,stage,bytes` rows: host durations, including
synchronization, of startup, PTY feeds (`pty_engine_feed` includes reply
transfer), graphics mapping and decoding, rendering, texture swap, event waits
and search, without terminal contents or query text; flushing each row perturbs
timing.

## Headless seat: `headless_seat.c`

`nix build .#headless-seat` builds `lib/seat.so`, which gives Weston's headless
backend a pointer and keyboard. If `CUDATERM_TEST_KEYS` names a FIFO, `uint32`
pairs written to it inject keys, pointer motion and buttons, or resize or close
the focused surface; the encoding is in the source.
