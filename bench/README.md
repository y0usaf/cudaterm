# PTY throughput benchmark

`pty_throughput.py` measures an end-to-end terminal PTY path with only Python
standard-library dependencies. It starts a fresh terminal for each measured
sample. The child writes `--payload-bytes` printable bytes, sends the terminal
query `CSI 6 n` (`ESC [ 6 n`), and waits for the terminal's cursor report
(`ESC [ row ; column R`). That report is a parser barrier: the terminal has
consumed the query and generated a response after consuming the preceding
payload. JSON contains every barrier duration and per-launch duration so runs
can be aggregated by a caller.

Examples:

```sh
python3 bench/pty_throughput.py --terminal foot --terminal-arg=-e --json
python3 bench/pty_throughput.py --terminal /home/y0usaf/dev/sandbox/monstar/result/bin/monstar --terminal-arg=-e --json
```

The terminal must have a working graphical session. For a terminal that uses
a server/client split, pass its normal fresh-window or standalone invocation.
The benchmark process exits when the child exits, so no terminal window should
remain open.

This measures PTY writes, terminal input, parsing, state updates, and response
generation. It does not measure compositor scheduling, GPU rendering, frame
presentation, or human-visible input latency. A fast cursor response therefore
does not by itself prove a lower displayed latency. Results are affected by
window-system load, terminal configuration, font, size, and whether the
terminal coalesces output internally; keep those fixed when comparing runs.

The protocol is deliberately small so it can be embedded in an orchestrator:
launch the terminal with the child command, wait for its JSON result file, and
retain the output as an artifact. The child writes its result only after all
barriers have completed.

Use `--workload text`, `--workload ansi`, or `--workload unicode` to select the
payload. The payload is rounded down to whole patterns so escape sequences and
UTF-8 are complete at the end. The child puts its PTY in raw mode and restores it
on exit; no newline is required in the cursor response. A synthetic-PTY test is
run by the Nix build to verify that property. The benchmark records actual PTY
geometry because a compositor can override the requested window size.
When expected dimensions are supplied, the parent checks every sample's grid
as well as the final grid. A launch that starts at a different size and settles
to the expected size is rejected even if the resize falls between samples.

## Application write-chunk sweep

`--write-chunk N` limits each application payload write to N bytes. The default
zero passes the whole payload to `write_all`, which still retries partial writes.
There is one cursor query after all payload chunks, with no added sleeps or
barriers between chunks. UTF-8 and escape sequences may cross write boundaries.
This controls application writes, not the terminal's realized PTY read sizes.

JSON records `write_chunk` and `sample_payload_write_ns` aligned with
`sample_barrier_ns`. Payload-write time includes Python slicing/looping, system
calls, scheduling, and PTY backpressure; it is not pure blocking or parser time.
The remaining barrier time also includes writing the query, receiving its reply,
and the post-reply geometry check. Compare raw distributions and retain both
metrics. All chunk sizes in a comparison should use this same instrumented
benchmark because the additional timestamp has a small measurement cost.

```sh
python3 bench/pty_throughput.py --terminal ./result/bin/cudaterm \
  --terminal-arg=-e --workload text --write-chunk 4096 \
  --expected-cols 318 --expected-rows 89 --json
```

## Cursor-query-only PTY baseline

Pass `--payload-bytes 0` to send only `CSI 6 n` during each timed sample. The
initial clearing/settling/query handshake stays outside timing. No printable
payload or DEC-graphics framing is emitted, regardless of workload. JSON records
zero realized payload bytes; its byte-throughput values are consequently zero
and not useful. Compare the raw barrier durations instead.

This estimates fixed PTY scheduling, parser/query, and reply transport costs.
It still includes any rendering/scheduling that the terminal performs while
handling queries. It is not GPU-only timing or displayed latency, and subtracting
its median from another workload's median does not isolate parser execution.
The Nix synthetic-PTY test verifies both positive and zero-payload cases.

## Headless engine feed benchmark

`engine_bench.cu` measures the completed `ct::Engine::feed` call directly. The
timed region includes the host-to-device copy, parser kernel, and completion
synchronization, and does not inspect engine state on the host. Defaults are a
small 80×24 grid, 4096 bytes, one warmup, and five raw samples. Configure them
with `--cols`, `--rows`, `--bytes`, `--warmup`, and `--repeats`; `--workload`
accepts `text`, `ansi`, `unicode`, `graphics`, `tabs`, `emoji`, `marks`, or `query`.

```sh
nix run .#bench -- --workload unicode --cols 80 --rows 24 --repeats 5
```

Payloads repeat complete patterns, and `bytes` reports the resulting size after
rounding down, keeping ANSI escapes and UTF-8 complete. JSON contains each
`duration_ns` and `ns_per_byte` without aggregates. Build it with `nix build .`; the build also supplies the generated font atlas
and Unicode width data required by the engine.

For fair PTY comparisons, request and verify the same effective columns and
rows for every terminal; the PTY benchmark currently records geometry but lets
the terminal override it. Compare equal realized payload sizes because whole
pattern rounding differs by workload, and report parser barrier and launch
costs separately. A fresh engine or explicit reset between samples would also
avoid later samples measuring a different scroll/state history.

Use `--replies` to time `Engine::feed_and_replies`, including reply transfer and
drain submission. This is mutually exclusive with `--render`; JSON identifies
`engine-feed-replies`. The `query` workload repeats `CSI 6 n`; `--bytes 4` emits
one query, while larger values repeat queries and can reach the existing 4096-byte
reply capacity. Ordinary text workloads with this mode measure empty-reply feeds.
Warmup repeats the same operation. Host wall time covers the completed readback,
but the final reset kernel is queued asynchronously and ordered before the next
sample. Use paired rounds and enough warmup, and compare durations per call.

```sh
nix run .#bench -- --replies --workload query --bytes 4 --cols 318 --rows 89 \
  --warmup 5000 --repeats 30
```

## Headless CUDA raster benchmark

Use `--render` to feed the payload once, then time repeated rasterization of
that fixed screen into a device pixel buffer. CUDA events surround
`Engine::render`, and each sample waits for its ending event. Allocation,
font loading, and the initial feed are outside the timed region. JSON identifies
`engine-render-cuda-event` and reports `duration_ns` and `ns_per_pixel` for an
8×16-pixel cell grid. This excludes PTY transport, OpenGL, compositor work, and
presentation; event intervals can include device scheduling and launch gaps.

```sh
nix run .#bench -- --render --dense --workload unicode --cols 318 --rows 89 \
  --bytes 262144 --warmup 10000 --repeats 20
```

`--dense` requires `--render` and removes CRLF from the repeated pattern so
text wraps across the screen. Use enough bytes to fill the requested grid.
`emoji` repeats U+1F600; `marks` alternates an `e` with U+0301 and an `e` with
U+1D185. These two workloads already contain no CRLF. Missing glyphs and marks
can make older engines render different content, which matters in comparisons.

Warmup counts apply to renders in render mode and feeds otherwise. Short
warmups showed large startup/clock variation in this session, including with
1000 renders. Use repeated rounds with reversed build order, retain raw samples,
and check stability; 10000 warmup renders improved these measurements but do
not guarantee stable clocks on another run. Do not overlap GPU benchmarks with
other benchmarks or correctness/sanitizer runs. Post-process clock snapshots do
not establish clocks during sampling.

## Host-stage tracing

Set `CUDATERM_TRACE=/path/to/trace.csv` when launching cudaterm to record
steady-clock `start_ns,end_ns,stage,bytes` rows. The file is overwritten on each
launch; use one launch per trace. Stages cover PTY engine feeds, graphics mapping,
CUDA rendering/unmapping, texture upload/draw/swap, and event waits. Only byte
counts are recorded, not terminal contents. Tracing is disabled by default.

With the combined feed/reply API, `pty_engine_feed` includes reply-length and
reply-byte transfer as well as feed completion. Older traces taken before that
change ended the interval before `take_replies`; compare their stage durations
only after accounting for this scope difference.

These are host call durations, including any synchronization; they do not
isolate GPU execution or measure displayed latency. Flushing each row perturbs
timing, so keep traced diagnostic runs separate from performance comparisons.

PTY benchmark JSON also includes aligned `sample_start_ns` and `sample_end_ns`
arrays from Python's `perf_counter_ns`; their difference is exactly
`sample_barrier_ns`. On this Linux setup, the benchmark and C++ steady-clock
trace share the monotonic clock. Verify clock compatibility before correlating
timestamps on another platform. For a sample `[a,b]` and trace interval `[s,e]`,
the overlap is `max(0, min(b,e) - max(a,s))`. Sum overlaps by stage; the remaining
sample time includes untraced host work, child execution and scheduling. This
is interval accounting, not a causal attribution of all latency to those stages.

If the benchmark child raises an exception, it writes the exception type and
message to its result file before exiting. The parent reports that diagnostic
alongside the terminal exit status and captured stderr, and rejects the run.
This preserves child failures that would otherwise appear only inside the
terminal window. Abruptly killed children may have no diagnostic to report.

## Selection integration check

After `nix build .`, run `python3 tests/window_selection.py --xdotool /path/to/xdotool`
from a graphical X11/Xwayland session. Add `--rapid` to exercise queued mouse
motion and button events. The test creates and closes its own terminal window,
replaces the clipboard with known Unicode test text, and emits a JSON result.
Add `--history` to verify navigation and copying after the test text leaves
the live screen. It is separate from throughput benchmarking.

## Idle parent-process resources

`python3 bench/idle_resources.py --terminal ./result/bin/cudaterm --terminal-arg=-e`
starts three fresh windows, waits for a child prompt and one further settling
second, then samples each terminal parent for three idle seconds. JSON records
PTY geometry, Linux CPU time and RSS, and NVIDIA compute-process memory when
reported for that PID. CPU percent uses one core as 100%; a zero sample means no
accounted CPU tick during that interval. The probe excludes compositor and child
process costs. Missing NVIDIA compute memory is `null`, not evidence of zero GPU
memory. It does not measure GPU utilization. Run it separately from benchmarks
and sanitizers, with equal geometry and terminal settings.

The `graphics` workload exercises DEC Special Graphics with SGR-colored border
characters. It designates G0 once before the repeated lines and restores ASCII
afterward; reported payload size includes both framing sequences. Both PTY and
headless engine benchmarks accept this workload.

`tests/window_selection.py --curses --rapid` draws a small ncurses border and
copies it back into the PTY child, verifying the graphical host, legacy character
mapping, and clipboard integration together.

The `tabs` workload repeats `column<TAB>value<CR><LF>` to exercise horizontal-tab
layout and scrolling. It is available in both headless and PTY benchmarks.

The headless `insert` workload wraps the text pattern in `CSI 4 h` / `CSI 4 l`
to measure insert-mode output. Its requested byte budget includes eight framing
bytes, and it requires space for one complete pattern plus that framing. Use
`nix run .#bench -- --workload insert --bytes 4096 --replies` for a feed/reply
measurement. This case currently exercises ASCII insertion; it does not measure
wide-character insertion or establish interactive application latency.

## Compositor-observed output

`visible_output.py` launches a terminal child that writes an alternating solid
truecolor background. The timestamp is taken in that child immediately before
writing to its PTY. The parent captures pixels using `grim` until the new color
appears; two calibration transitions are excluded. The child stays alive until
observation finishes, and each sample must retain the startup grid geometry.

Example (run in the visible Wayland session, with the terminal covering the
specified compositor region):

```sh
python3 bench/visible_output.py --terminal ./result/bin/cudaterm \
  --terminal-arg=-e --region '40,40 64x16' --samples 20 --load-lines 3000
```

`--load-lines 0` measures a background transition alone; 3000 writes 72,000
application bytes of scrolling text before the marker. The fixture leaves
PTY output processing enabled: ONLCR expands its CRLF endings to CR-CR-LF,
so the terminal receives 75,000 load bytes in this session. This also exercises redundant carriage returns. The marker's new color is absent
from that text. Arguments for other terminals are repeatable
`--terminal-arg=VALUE` options; exact terminal commands are saved in each JSON.
Choose a region entirely inside the terminal and keep it unobscured. Without
`--region`, the probe captures the entire desktop, which adds substantial copy
and decoding overhead. `sample_pixel` is relative to the capture region.

This is **PTY-write-to-compositor-capture observation**, not physical scanout,
photon visibility, or keyboard input latency. Each result includes PTY write
blocking, capture startup, compositor scheduling, transfer, and decoding. Capture
starts after the child finishes writing the payload. The per-capture durations
and attempt counts are retained to expose this overhead. Screenshot polling
perturbs scheduling and samples are phase-correlated; compare distributions
cautiously and do not infer a sub-frame advantage or display parity from them.
The benchmark temporarily changes the terminal background and captures desktop
pixels in memory; it does not save screenshots.

The manual X11/Xwayland test `python3 tests/window_mouse.py --xdotool PATH`
checks exact SGR press, drag, release, and wheel reports received through the
child PTY. `python3 tests/window_selection.py --rapid --mouse --xdotool PATH`
checks Shift-selection and clipboard roundtrip while application tracking is
enabled, including releasing Shift before the mouse button. These tests require
a visible desktop and operate only on the launched terminal window.

`python3 tests/window_keyboard.py --xdotool PATH --count 512` launches an owned
X11/Xwayland window, injects printable keys with `xdotool type --window`, and
checks the exact bytes read by its raw-mode PTY child. Use `--terminal PATH` to
compare Nix-built binaries. JSON records injection-start to child-last-read time,
the separate xdotool duration, timestamps, commands and executable path. The
window stays alive until injection finishes. This measures synthetic event
delivery through the PTY, including timestamp-file writing, process startup and
scheduling; it does not measure physical keyboard or display latency. Single-key
results are particularly sensitive to tool overhead. Run desktop fixtures
serially, without concurrent GPU builds/tests.


## Independent terminal-state comparison

`nix run .#reference-test` compares the CUDA engine with the pinned
`libvterm-neovim` 0.3.3 package from this flake's Nixpkgs input. The reference
library is linked into the test executable only. An optional fixture name runs
one case, for example `nix run .#reference-test -- alternate_1049_entry_cursor`.
Unknown names fail.

Each fixture runs whole, bytewise, and in chunks of 7 and 256 bytes. Comparisons
cover cells at each fixture checkpoint, three combining slots, wide/tail structure, RGB colors,
bold/underline/reverse attributes, cursor position, and actual reply bytes.
Palette/default colors are configured to match cudaterm. Blank and wide-tail
storage differ between engines and are normalized explicitly, while predecessor
width remains checked. Fixtures include >512-byte ASCII and styled output,
persistent edits, margins, tabs, Unicode, DEC graphics, 1049 entry/return, and DSR.

This is a bounded independent comparison, not full VT conformance. It does not
compare states inside incomplete control sequences, cursor visibility/shape, resize, history, selection,
mouse, legacy alternate modes, or pixels. Those require separate validation.
Reference behavior is evidence to investigate alongside specifications; it does
not override intentional, documented terminal policies.

The checkpoint fixtures model shell-line editing, margin scrolling, saved cursor
and pen, and delayed wrap. `mixed_edit_checkpoints` uses a fixed seed and 128
operations; every completed operation checks cells, cursor, and replies before
later output can erase evidence. Chunking is applied within each checkpoint.
The original single-payload cases continue to test larger combined input.

Libvterm 0.3.3 clamps vertical cursor movement to screen bounds with origin mode
off, whereas DEC CUU/CUD stop at scrolling margins unless the cursor is already
beyond the relevant margin. Generated differential moves therefore use full-screen
margins; dedicated literal VT tests verify the DEC behavior. The observed
reference difference is saved in `reference-cursor-margin-difference.json`.

`cursor_line_moves` adds independent checkpoints for CNL/CPL (`CSI E`/`CSI F`)
column reset, counts, clipping, and output after delayed wrap. Literal VT tests
cover their split sequences and margin/origin behavior.

## History-search evidence

`nix run .#search-test` checks GPU search semantics and resource release.
`nix run .#window-search-test` uses a private headless Weston instance to check
UTF-8 history search/copy, local query input and restoration of a previously
scrolled viewport. Its screenshots and trace are recorded in
`bench/window-search.json`; these are functional assertions, not display-latency
measurements.

`nix run .#search-cost -- 80 hard` emits 40 raw wall-clock Engine-call samples
after five warmups. Supported columns are 80 and 318; `hard` uses 5,000 numbered
lines with a rare six-character query, while `soft` uses a 1,310,720-byte
repeated-X stream with a 256-character query. Run three separate launches for
each combination with owned GPU tests/builds idle. Preserve raw JSON and the
actual executable/source hashes. The initial evidence is
`search-cost-{80,318}-{hard,soft}-{0,1,2}.json`; pooled medians, linear p90s,
maxima and allocation release are in `search-cost-summary.json`. Engine-call
latency excludes PTY transport and compositor/display latency. No comparator
search-time distribution or parity is claimed.

## Controlled private idle resources

`nix develop --command python3 bench/private_baseline.py --weston /nix/store/bym3mrisbsrph2654wj5bhc1x5ijhv0q-weston-16.0.0/bin/weston --seat /nix/store/gjy7nxx5l52l9nfc6yw1bxvm0yppg586-cudaterm-headless-seat/lib/seat.so --cudaterm /nix/store/1rn5djnv9hid0mzzg9p6c63wzyn4vyjj-cudaterm-0.1.0/bin/cudaterm --foot /nix/store/ls22769pvdl3c28rg16gqc5psckf6kxx-foot-1.27.0/bin/foot --monstar /nix/store/h8q9vhbxzpsla7m2hqgqygyw6wd0pjny-monstar-1.1.0/bin/monstar --controlled-config --fontconfig "$PWD/bench/controlled-fonts.conf" --output bench/private-idle-controlled.json --seconds 3 --repeat 3` reproduces the controlled private Weston resource run. It uses only the private headless compositor, validates child geometry at 80x24 and 318x89, and records resolver-proxy font identity; it does not prove the client loaded that font or measure GPU parity. Raw results and grouped per-geometry summaries are `private-idle-controlled.json` and `private-idle-controlled-summary.json`.
