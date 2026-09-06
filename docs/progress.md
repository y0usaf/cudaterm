# Development evidence and recovery state — 2026-09-06

## Current goal status — blocked on environment access

Three consecutive goal turns have confirmed the same external blocker:
NVIDIA runtime access is unavailable and the sandbox denies the Nix daemon
socket. CPU recovery and focused review are finished. Further acceptance work
requires restored access to those services; repeated source reviews cannot
replace the required CUDA, private-window, performance and Nix checks.
`bench/recovery-blocked-audit.json` records the third fresh check.

The full objective is incomplete. The idle candidate remains unaccepted,
all numerical gates remain unchanged, and the last accepted build remains
selected. After access is restored, resume the exact pending checks in
`bench/reboot-recovery-validation.json`, then continue the broader baseline,
performance and daily-driver feature work recorded below.

## Post-shutdown recovery — validation access unavailable

The preceding work made progress through source changes and diagnostic evidence,
but the idle candidate was not accepted before shutdown. Old background jobs
are gone; recovery uses saved files and fresh agents, not old process IDs.
The last accepted app, engine-host and search-test store binaries still match
`bench/search-review-final-validation.json`. Current `src/engine.cu` also
matches that verified engine hash. `src/main.cu` contains an unaccepted event-loop
candidate, with the accepted source retained in
`bench/main.cu.before-event-driven`.

Fresh checks on September 6 find NVIDIA unavailable (`nvidia-smi` exits 9) and
Nix daemon socket access denied by the current sandbox (`nix build
path:/home/y0usaf/dev/developing/cudaterm --no-link` exits 1).
`bench/reboot-recovery-environment.json` preserves exact outputs. No permissions
bypass or system activation is attempted. CPU-side review and recovery can
continue; CUDA/private-window measurements and mandatory Nix/Finix validation
cannot currently run. Earlier passing results do not validate the recovered
candidate. Fixed acceptance gates remain unchanged, and the overall goal
remains active.

Recovery fixed EOF/HUP rearming so a closed PTY is removed from worker polling
while the child pidfd remains watched. The main loop retains fresh-poll output
draining after reaping. New private fixtures cover a closed slave with a live
child, delayed final output and status, delayed DSR wakeup, idle close after the
initial frame, and delayed reading of a large clipboard paste. These graphical
checks are **written but not run** on the recovered candidate.

The fixture cleanup now signals owned descendants through pidfds, waits for
exit before deleting temporary control files, and removes stale PID records.
Three native CPU checks exercise cooperative exit, TERM, and KILL fallback,
verify exit status, and check descriptor release (`python3
tests/test_window_cleanup.py`, exit 0). They are wired into the Nix check phase,
but mandatory Nix validation is still pending. Python syntax checks also
succeed. These native results do not replace CUDA or graphical verification.

`bench/idle-event-recovered.patch` and
`bench/reboot-recovery-validation.json` preserve the recovered changes, source
hashes, exact native checks and remaining validation. `result` still selects
the last accepted store build; the idle candidate remains unaccepted.

A subsequent continuation rechecked both access failures and verified that all
recovery-manifest source hashes still match. A focused CPU-only review found
no further concrete event-loop or fixture defect. This is not runtime proof;
`bench/recovery-access-recheck.json` records the second consecutive goal turn
with the same validation-access blocker. The next required work is the pending
GPU/private-window and Nix verification, not another unmeasured optimization.


## Idle event-loop investigation — in progress

The preceding turn was progress: it added an independent search oracle,
rejected three gate-failing experiments, and established a controlled private
resource baseline. This increment investigates the remaining idle activity.
Raw syscall inspection confirms application-owned 100 ms polling in the PTY
worker and GLFW main-thread wait. The busiest multi-descriptor polling thread
is distinct from the PTY worker. Post-shutdown raw-stack review identifies
388 poll calls in that thread, with representative libcuda frames and seven
NVIDIA-device descriptors (`bench/idle-driver-attribution.json`). This proves
CUDA-driver association, not a settled-idle rate or irreducible CPU cost.
The initial diagnostic agent mislabeled that thread and emitted Python repr
under JSON filenames. Those records are preserved as explicitly legacy-invalid
files, not accepted machine-readable baseline evidence. The corrected traced
capture covers startup through shutdown and is an instrumented attribution
sample, not a settled idle performance measurement.

Before application edits, `bench/idle-event-gates.json` fixed the incremental
acceptance checks against the existing controlled baseline: eliminate repeated
application-owned idle timeouts, preserve per-grid median/p90 CPU and context
switch limits, bound host-memory changes and GPU memory, and pass direct-child
exit, input/backpressure, delayed-frame, search/resize and lifecycle checks.
The better-comparator target of zero observed voluntary context switches over
three seconds remains unchanged; context switches are not wakeups. Existing
host-memory competitiveness targets also remain unmet and unchanged.

A bounded candidate replaces periodic wake checks with pollable control and
child-exit events, preserving CUDA parsing/state/raster and the active decode
input pump. Implementation, corrected settled diagnostics, controlled
measurements and final Nix/Finix validation are pending. No idle optimization
has yet been accepted.

## Search optimization review and controlled baseline — validated increment

Three search pruning candidates were rejected against the unchanged four-case
median/p90 gates. Candidate one pruned every query; candidate two retained the
original scan below 32 codepoints. All improved repetitive long-query timing
but failed short-query gates. `bench/search-experiment-gates.json` contains
parent-reviewed pooled statistics and raw hashes, using the original linear
p90 definition rather than the nearest-rank values in early agent reports.
A contemporary rerun of the unchanged 80-column hard reference also drifted
above its original gate (median 53,250 ns, p90 65,380.9 ns). This diagnostic
does not replace the fixed baseline or authorize acceptance.

Separate CUPTI runs support prioritizing comparison work: in the 318-column
repetitive case, the original find kernel's median was 28.440 ms across 45
calls versus 0.930 ms in the first rejected candidate. Those instrumented
kernel durations include warmups and are not Engine-call or display latency.
The profiles contain no dropped-record diagnostic lines; that does not prove
complete collection. Raw data remain in `bench/search-prune-*-profile.*`.
The final bounded experiment moved ordinary search initialization to the GPU
and removed its initial state snapshot transfer. Its 80-column hard-case
median/p90 were 55,394/61,514 ns, exceeding the fixed 49,549.5/50,262 ns
limits. It was rejected. Both application source files have been restored to
the exact previously validated hashes; no pruning optimization is accepted.

An independent logical-corpus oracle now checks overlapping matches in both
directions and cyclic continuation against generated source strings, across
hard breaks, soft wraps, wide characters and combining marks. It supplements
the existing direct engine fixtures. The final selected build passes this
expanded suite, memcheck with zero errors and racecheck with zero hazards.

Fontconfig inspection exposed a concrete provenance problem: the inherited
resolver substitutes Departure Mono Ultra Condensed for requested DejaVu Sans
Mono. Resolver output is a proxy, not proof of the font loaded by either
client. The opt-in controlled baseline collector now isolates terminal configuration,
pins fontconfig input and records resolver/font hashes. Six CPU tests pass via
`nix develop --command python3 tests/test_private_baseline.py`, including two
new tests for environment and probe behavior. All 18 controlled private Weston
launches pass stable 80×24/318×89 child geometry checks. Every comparator
resolver probe selects the pinned DejaVu Sans Mono Book file. Actual loaded
client font and equal pixel geometry are not established by this evidence.
`bench/private-idle-controlled.json` preserves raw samples and metadata.

After-idle median RSS / PSS / private memory in MiB, with three launches per
cell grid, are:

| Grid | Foot | Monstar | Cudaterm |
|---|---:|---:|---:|
| 80×24 | 12.574 / 4.379 / 3.570 | 16.031 / 8.624 / 7.445 | 116.664 / 73.469 / 66.805 |
| 318×89 | 29.434 / 13.703 / 5.383 | 51.180 / 35.935 / 26.922 | 116.652 / 73.418 / 66.793 |

One large Monstar launch retains less memory (RSS 34.984 MiB); the raw
variation is retained without an unverified causal explanation. Cudaterm's
attributed GPU memory is 242/300 MiB; comparator GPU attribution remains
unknown. Context-switch counters are not wakeups. This is an idle terminal
parent measurement, not peak memory, startup or display latency. The original
resource targets remain unchanged and unmet.

Final `nix build .`, `nix flake check`, `nix run .#window-search-test`, the Finix
preview build and local Finix evaluator all pass. Exact commands and outputs
are recorded in `bench/search-review-final-validation.json`. The selected
package is `/nix/store/v513niaacn1bz0zn35pv9wsmy5mfiqx0-cudaterm-0.1.0` and the
Finix preview is `/nix/store/6rqkry00nnhd2kl1an2dbc94syyl3hyz-cudaterm-finix`.
No system activation occurred. Parent review confirms app and engine-host
binaries are byte-identical to the prior validated search milestone, so its
15 CUDA suites, 38 graphics cases and 90 engine-host lifecycle cycles remain
applicable; these broader workloads were not rerun for unchanged binaries.
The new oracle and private search-window fixture were rerun on this selected
build. Rejected patches and timing samples remain in `bench/search-*-rejected.patch`
and `bench/search-experiment-gates.json`.

Next work should separate idle CUDA-driver/context cost from controllable
polling, finish startup/multiple-window/retained-memory measurements and
actual comparator resize/search timing, and close the remaining daily-use
Unicode/grapheme and TUI gaps. Actual client-font evidence and graphical
window lifecycle soak remain open. This increment made progress without an
accepted search optimization; the overall goal remains active.

## History search — functional milestone and first cost baseline

The previous goal turn completed reflow validation and Finix integration; it was
progress. History search now scans GPU primary history/live rows or the active
alternate grid. A visible-grid CPU draft was rejected and removed. CUDA
candidates traverse wide/combining cells and soft-wrap boundaries; hard breaks
stop a match. Repeat search wraps in either direction. Feed and resize
invalidate old continuation positions. Matches update selection/viewport
metadata without changing cells or parser/cursor state.

Ctrl+Shift+F opens local incremental search, Enter/Shift+Enter navigate,
Ctrl+Shift+C copies, Ctrl+Shift+V pastes into the query, Ctrl+U clears, and Escape
closes and restores the bounded prior viewport offset. Queries are limited to
256 exact case-sensitive codepoints, without normalization or regex. Copy and
highlight endpoints cover whole cells. A CUDA-rendered bottom-row prompt covers
terminal/image pixels without modifying underlying content; long text is
clipped. `docs/search-design.md` records semantics and remaining limits.

The focused suite proves Unicode/soft/hard boundaries, exact repeat order,
long offscreen copies, feed/reflow invalidation, alternate isolation, eviction,
invalid-input bounds, prompt pixels, text nonmutation and resource release.
Search, reflow and 13 standard CUDA suites pass, as do 38 graphics cases,
90 engine-host lifecycle cycles and zero-finding memcheck/racecheck runs
(`bench/search-validation.json`). Each lifecycle process retains constant
post-cycle RSS 63,916 KiB and private memory 51,372 KiB; PSS spans
54,871–54,959 KiB. These are engine-host samples, not an instantaneous peak or
long graphical-window soak. They do not establish a causal memory comparison
against prior builds.

`nix run .#window-search-test` verifies an actual wrapped UTF-8 history query,
active-match copy after replacing the clipboard with a different marker,
absence of query bytes in the child PTY, and ordinary input/bracketed paste
after closing. A 128-pixel marker in an originally scrolled viewport disappears
while search moves to older text and returns at identical coordinates after
Escape. Captures and exact executable/module hashes are in
`bench/window-search.json` and `bench/window-search-{before,active,restored}.png`.
Earlier failures used an old overridden binary or an unready window; those
failed fixture observations are not evidence that the final engine lacks search.

The first cost baseline uses three launches per case, 40 measured calls after
five warmups each. Hard cases contain 5,000 numbered lines and search a rare
six-character literal; soft cases contain a repeated-X stream and search 256
X characters. Values below are wall-clock **Engine calls**, including
snapshot/CUDA work, excluding PTY, compositor and display latency.

| Columns × rows | Case | Median ms | Linear p90 ms | Maximum ms |
|---|---|---:|---:|---:|
| 80×24 | Hard | 0.04955 | 0.05026 | 0.06229 |
| 318×24 | Hard | 0.09805 | 0.13115 | 0.29213 |
| 80×24 | Repeated soft text | 6.81550 | 9.71418 | 11.46606 |
| 318×24 | Repeated soft text | 27.62275 | 28.95075 | 31.70995 |

`bench/search-cost-summary.json` retains raw hashes and pooled distributions
using rank `(n-1)*0.9` interpolation. Query scratch is 1,072 device bytes and
returns to the pre-search allocation count in every cost launch. Prompt
storage is bounded to another 18,432 device bytes and its release is checked.
Before optimizing search, require median and p90 no greater than these exact
fixed baselines for all four cases, plus correctness/resource checks. This is
an incremental guard, not a substitute for missing comparator search-time
measurements. Long repetitive-query comparison work is a measured next target.

`nix build .`, `nix flake check`, the Finix preview build and the current local
Finix evaluator pass; final paths and hash equivalence are recorded in
`bench/search-validation.json`. The final package is `/nix/store/1rn5djnv9hid0mzzg9p6c63wzyn4vyjj-cudaterm-0.1.0`;
the Finix preview is `/nix/store/srj8dv88i933fw1f2vr41210w3np6m13-cudaterm-finix`.
No system activation was performed. The CUDA
architecture and Ekko image behavior remain covered by the regression suites.

Installed Monstar 1.1.0 passes ASCII history search/copy, including a physical
soft wrap (`bench/search-comparators.json`). Foot's copy roundtrip remains
unresolved in this fixture; it is not proof that Foot lacks search. Private
Weston lacks primary selection, and earlier attempts inherited user bindings.
Only embedded JSON observations are preserved reliably for the early diagnostic
attempts; their reused log/capture paths must not be attributed to old runs.

The comparator work also exposed a resource-baseline provenance gap: earlier
private runs inherited configuration without a complete snapshot. CLI family,
grid and history requests do not prove effective fonts or remaining settings.
Existing numerical gates remain unchanged and missed. Controlled configuration/
font baselines, actual comparator resize/search timing, startup/multiwindow and
wakeup attribution, graphemes, broader TUI compatibility and graphical lifecycle
soak remain open. This milestone does not complete the goal or establish parity.

## Primary resize reflow — optimized implementation

Primary history and live text now reflow together on the GPU. Positive wrap
metadata joins rows; hard breaks remain separate and pending wrap alone never
creates a join. Cursor positions, saved cursors, the scrolled viewport and
primary image anchors follow the mapping. Alternate content keeps its physical
clip/pad policy. Wide pairs move together; width one uses U+FFFD. Explicitly
printed spaces survive packing through one existing Cell provenance bit,
without changing Cell size. Old arrays survive until replacement copying is
finished; scratch is bounded and released after commit.

Parallel row inspection and arithmetic mapping for single-width rows remove
the initial implementation's serial padding scan. Wide rows still use serial
cell planning. The smaller alternative, retaining the old clip/pad resize,
cannot preserve logical lines. The initial functional serial implementation was
measured before this optimization; its fixed acceptance gate required median
and p90 request RTT no greater for every blank/hard/soft case and width. All
nine combinations pass. This does not replace the better-comparator targets.

For 5,000 hard lines, request RTT milliseconds are below. Each cell pools
three launches with five cycles per launch; p90 uses linear interpolation at
rank `(n-1)*0.9`. The request includes engine-host IPC and CUDA work, not
compositor observation or display latency.

| New columns | Initial median | Optimized median | Optimized p90 | Optimized maximum |
|---|---:|---:|---:|---:|
| 40 | 124.719 | 5.487 | 10.563 | 11.706 |
| 318 | 57.894 | 7.430 | 10.868 | 12.749 |
| 80 | 488.692 | 7.998 | 11.974 | 13.060 |

Raw samples, memory observations and the gate calculation are in
`bench/reflow-cost-after-*`, `bench/reflow-fast-cost-after-*` and
`bench/reflow-fast-cost-validation.json`. Runs were not interleaved between
builds, limiting causal precision. The older clip/pad baseline is functionally
different. The blank-case maximum at 318 columns increased from 1.786 to 1.887 ms
even though its predeclared median/p90 gates pass. The new wide-stream baseline has roughly
13–14 ms medians and no matched old baseline or acceptance gate. Comparator
resize costs remain unknown.

The optimized build
`/nix/store/37swjdsqvx58grl0bdc6gqkkmcyq0bim-cudaterm-0.1.0`
passes the focused reflow suite and 13 standard CUDA suites, 38 graphics cases,
90 engine-host lifecycle cycles, and memcheck/racecheck with no reported
errors or hazards (`bench/reflow-fast-*.log`). Every lifecycle reset returns
10,600,142 tracked device bytes, history capacity 128 and zero image/transfer
bytes. Post-cycle RSS is 63,804 KiB and private memory 47,356 KiB throughout all
three processes; PSS ranges 51,963–51,999 KiB. These bounded samples do not
measure instantaneous peaks or establish a long graphical-window soak.

The final build `/nix/store/fgfysy0bsdlkjc4wlsrdzy33pgcgx93v-cudaterm-0.1.0`
adds saved-cursor/prompt and incomplete UTF-8/CSI resize regressions. Its terminal
and engine-host binaries match the measured optimized build byte for byte.
Private Weston modes 0–5 pass, including an acknowledged 80×32→40×32 resize
followed by exact UTF-8 logical-line copy and bracketed paste
(`bench/reflow-private-window.json`). `nix build .` and `nix flake check` exit zero, as do the final focused suite
and its memcheck/racecheck runs. Commands, source and executable hashes are in
`bench/reflow-final-validation.json`; GPU suites are separate from flake checks.

`nix build --impure --file nix/finix-preview.nix --out-link result-finix`
builds `/nix/store/q46mb95npb4sagdgwq8spfvzvy9bv20m-cudaterm-finix`.
The evaluation harness now replaces the cudaterm flake input used by Finix's
existing import, avoiding duplicate option declarations. It checks the current
local module, proves the configured package equals the rebuilt preview, and
passes NVIDIA-guard, desktop-default, Framework-default and explicit-override
assertions (`bench/reflow-final-finix-evaluate-current2.log`). Earlier failed
harness attempts remain in separate logs. No system activation was performed. The initial parser pair compares the pre-reflow build to the serial functional
build, not the final optimized build. Pooled ANSI samples have median
156.22→160.43 µs and p90 166.65→174.94 µs (80 samples per side, the same
linear percentile method; `bench/reflow-feed-summary.json`). The regression
remains unexplained and is not cancelled by other workload improvements.

Memory comparator gates remain missed. Matched resize/compositor baselines,
startup, multiwindow measurements, wakeup attribution, broader primary-TUI
cursor compatibility, grapheme handling and history search remain open. This
is a feature/performance milestone, not completion or a parity claim.

## History-copy candidate rejected after measured regression

The preceding resource-baseline turn and this implementation/validation turn
made progress; neither was a blocked wait. A candidate mapped each
`prepare_history` CUDA block to logical rows, preserving snapshots and wrap
metadata while removing flat cell-index division. It passed selection, plain,
styled, scrollback and independent reference suites and 90 repeated engine-host
cycles (`bench/history-row-*.log`, `bench/history-row-lifecycle.json`).

Before timing, the incremental gate required pooled median and p90 feed times
no greater than the fixed reference for text, ANSI and Unicode. Two reversed
rounds of 40 samples at 318×89 and 80×24 failed Unicode tails. A longer
confirmation used 200 samples per round and again failed at 318×89:
Unicode median 162,659.5 → 168,480 ns (+3.6%), p90 171,450 → 290,140 ns
(+69.2%). Text improved at both sizes, and all three workloads improved in the
longer 80×24 run, but these wins do not cancel the failed large-window gate.
The cause of the Unicode tail remains unresolved; do not claim it is a single
outlier or attribute it to a specific kernel from feed timing alone.

The candidate is **reverted**. `src/engine.cu` again matches the fixed reference
source; `bench/history-row-rejected.patch` preserves the experiment. Raw
`history-row-paired-{318,80,8}.json` and `history-row-confirm-{318,80}.json`
retain exact before/after binaries and every sample. Existing comparator gates
are unchanged. There is no accepted application speedup from this experiment.

The retained regression fills all history slots with real soft continuations,
verifies joined copied text, then replaces them with one 5,000-hard-line burst
and requires hard line breaks on copy. It directly exercises the fast path and
recycled wrap metadata. `nix build .`, the selection suite through `nix develop`, and
`nix flake check` all exited zero. `bench/history-row-final-validation.json`
records commands and hashes; the final terminal/host/benchmark binaries in
`/nix/store/6vqjrx4nmz9h5kw9859mfj0bkma2ldiy-cudaterm-0.1.0` match the
reference byte for byte. `bench/history-row-performance-summary.json` retains
separate initial and confirmation distributions plus raw input hashes. Primary-screen resize reflow is implemented in the newer milestone above;
`docs/reflow-design.md` records its rules and source-provenance limits. Pending wrap alone must not join the
next physical row. Alternate-screen policy requires separate compatibility
validation. Full parity, graphical lifecycle soak and remaining baseline metrics
are still outstanding.

## Fresh private-compositor resource baseline

Three launches at each of 80×24 and 318×89 now measure Foot 1.27.0, Monstar
1.1.0 and the fixed wrap-copy build under private headless Weston 16.0.0.
Raw samples, executable hashes, options and geometry histories are in
`bench/private-idle-three-terminal.json`; its summary preserves all host-memory
samples. The earlier blank-screen run is retained separately. Median cudaterm
RSS is 116.0 MiB at both sizes, versus Foot 16.8/28.8 MiB. Cudaterm misses the
new Foot-based RSS/PSS/private gates at both sizes; exact unrounded gates and
limitations are in `docs/baseline-audit.md`. Comparator NVIDIA process memory
remains unknown even with the graphics-inclusive query. Cudaterm's observed
331–434 voluntary context switches per three-second idle interval need thread
attribution; they are not wakeup measurements. No performance optimization was
made from this short baseline. Startup, concurrent windows and sustained
workload comparator retention remain outstanding. Raw per-thread counter sums
reproduce the cudaterm totals: its main thread contributes exactly 30 voluntary
switches per interval, while one non-main thread contributes 241–344; two
other threads contribute 30 each and the remaining thread contributes zero. The raw artifact retains 37 geometry
samples and actual geometry for each interval, and validates every point and
final geometry against the requested grid. No thread role is inferred without
a scheduler trace.

## Repeated engine-host lifecycle evidence

The fixed build completed 90 cycles in three persistent private engine-host
processes (30 cycles per process), including scrollback growth to 4096 rows,
318×89 → 40×12 resize, RGB/RGBA direct and zlib image uploads, full 64×32
pixel checks, deletion, and RIS reset. At the matching reset stage, each
process ended with `device_bytes=10600142`, `history_capacity=128`, and zero
image/transfer bytes; these matched the first warm cycle. Raw evidence is in
`bench/lifecycle-current.json`; the derived per-process first/final allocation
and RSS/PSS/private-memory summary is `bench/lifecycle-current-summary.json`
(raw SHA-256: `3eef0a0a8e1db463b0364af34ebb6306ca911b46a6dea60a59ccc506c9fee3b`).
Samples are stage observations rather than true instantaneous peaks. This is a
headless engine-host lifecycle check and does not establish graphical-window
lifecycle stability; a repeated graphical soak remains outstanding.

The updated evidence collector also passes its CPU-accounting/GPU-observation
regressions through Nix. `nix build .` and `nix flake check` exited zero;
`bench/private-baseline-build-validation.json` records logs and executable hashes.
The resulting `/nix/store/xlhqbilc5gcbnk7zfs72x43h8v18x7z5-cudaterm-0.1.0`
terminal, engine host and engine benchmark binaries are byte-identical to the
fixed build measured above. This increment changes evidence tooling, not app
behavior.

## Initial CUPTI kernel attribution

Private headless engine traces now contain 1,359 parsed kernel activity records
for text, ANSI and Unicode at 318×89, requested 64 KiB, five warmups and twenty
measured feeds per workload. Raw traces and timestamps are retained under
`bench/wrap-profile-*`, with `bench/parse_wrap_profile.py` validating duration
arithmetic. Instrumentation, setup and warmups are included, so these totals
are diagnostic evidence rather than acceptance timing. In the text trace,
`prepare_history` totals 2.072 ms versus wrap metadata 0.166 ms; in the ANSI
and Unicode traces, styled painting and history preparation dominate kernel
duration. Kernel duration alone does not measure launch overhead or explain
the prior Unicode wall-time tail. Profile those larger costs and the idle
non-main thread before selecting the next optimization; retain paired
uninstrumented gates and all wrap-copy regressions.

## Wrap-aware copying — validated milestone

Luna implemented and investigated bounded subtasks; parent review selected the
row-length design, corrected boundary/copy conditions and integrated validation.
Copies now join actual soft wraps and retain explicit LF/CRLF breaks. Row metadata
stores the number of columns before a continuation, so real edge spaces survive
while early-wide-wrap padding and later resize padding are omitted. Pending wrap
alone is not a continuation. Word/line selection still expands over physical rows.
Resize still clips/pads; this change does **not** implement reflow.

CUDA owns the wrap lengths alongside main, alternate and history rows. Three
bounded allocations total 18 KiB; the host memory estimate includes them. Main
and alternate metadata swap with their grids; history grows/reindexes its ring;
resize installs fresh arrays and releases the old ones. Shared scratch handles
history reindexing without a large per-thread CUDA stack allocation. Plain input
uses a post-scatter metadata kernel; styled and scalar parsing mark actual wrap
transitions. Row insertion/deletion breaks links at changed adjacency boundaries.
Erasing the continuation edge or shifting cells invalidates that row's link;
partial erasure before the boundary preserves it. No CPU parsing or rasterization
fallback was added, and Ekko graphics and Finix integration sources remain intact.

Fixed validated build:
`/nix/store/3gkakr3w1qvs5n0bjgmcvpdg8k15bnnn-cudaterm-0.1.0`.
`bench/wrap-copy-validation.json` records hashes matched against the actual Nix
source input. `nix build .`, twelve GPU suites against that fixed binary
through `nix develop . --command`, and `nix flake check` exited zero. The exact twelve names are in the manifest (the separate CSI suite
was not rerun in this milestone). Earlier mixed-snapshot runs are intermediate
evidence only. Existing flake metadata warnings remain.

The new literal tests cover hard versus soft breaks, delayed wrap, real spaces,
early wide padding, selection endpoints, history growth, width growth/clipping,
alternate-screen retention/clearing, RIS, ECH/ICH/DCH and row insertion. Larger
ASCII and styled payloads compare copied visible/history text against bytewise
feeding. Existing scrollback and reference tests also pass. Private Weston
`nix run .#sync-test -- --terminal <fixed>/bin/cudaterm` passes modes 0–4,
including pointer selection across a true wrap followed by CRLF, exact UTF-8
clipboard bytes and bracketed paste under application mouse tracking. Selection
Compute Sanitizer memcheck reports zero errors; racecheck reports zero shared
memory hazards/warnings. These tools cover exercised paths, not a proof against
all possible global-memory races. Logs: `bench/wrap-copy-final-{build,gpu,window,
memcheck,racecheck,flake}.log`.

### Measured overhead (not a performance win)

`bench/wrap-copy-headless-paired.json` retains two reversed rounds, 2,000 warmups,
40 samples per variant/workload/round, 318×89 geometry, equal realized payloads,
exact binaries/hashes and complete benchmark JSON. No GPU tests or builds
ran concurrently with measurement; unrelated GPU load was not isolated. The
before binary is the word/line-selection milestone. Timings are completed CUDA
engine feeds, excluding PTY, windows, clipboard and presentation.

| Workload | Round 0 median before → after µs | Round 1 median before → after µs |
| --- | ---: | ---: |
| Text | 104.125 → 109.000 | 104.050 → 112.060 |
| ANSI | 155.050 → 162.069 | 160.310 → 161.480 |
| Unicode | 157.175 → 162.564 | 159.434 → 162.864 |

Pooled median increases are 5.7%, 2.0% and 3.4%, respectively. The new plain
metadata launch and metadata writes add work; this is a correctness feature
with measured overhead, not an optimization claim. Unicode round 1 p90 rose
174.860→436.770 µs, with an after maximum of 2.566 ms; its cause is not isolated.
Do not hide that tail behind the pooled median or claim latency parity. A next
profiling milestone should measure and reduce metadata launch/scan costs while
retaining the regression behavior; targets are not relaxed.

The independent 36-case CUDA graphics suite also passed through Nix against the
fixed engine host (`bench/wrap-copy-final-graphics.log`). Three headless EGL
probe launches per variant retained raw stage snapshots in
`bench/wrap-copy-memory-{before,after}-{0,1,2}.jsonl`; parent recomputed the
sample/min/median/max fields in `bench/wrap-copy-final-memory.json` directly
from those files. Engine-stage median RSS rose 116,688→117,284 KiB (+596 KiB),
PSS 75,400→75,996 KiB, and private memory 69,192→69,788 KiB. NVIDIA process
memory was unchanged at 238 MiB after engine construction, 280 MiB after text,
294 MiB after rasterization and 226 MiB after engine destruction in all six
probes. The 18 KiB explicit allocation does not by itself explain the complete
host delta; driver/module allocation effects were not isolated. These snapshots
exclude a real window and are neither peak-memory measurements nor a repeated
in-process lifecycle soak. Broader retained-memory stability remains unproven.

Full completion remains open: reflow, history search, grapheme support, fresh
matched-comparator measurements, broader memory/lifecycle distributions and
physical input/display latency remain missing or unverified. The configured
Finix wrapper still pins its previous terminal build; these source improvements
are validated in the default package, not claimed as deployed to that wrapper.

## Baseline and feature evidence audit

Luna subagents inspected raw local evidence; parent review corrected provenance,
unsupported tolerances, and comparator selection before integration. The new
[baseline ledger](baseline-audit.md) records adopted fixed historical PTY
median/p90, RSS and compositor-observation reference gates, with no added slack.
A scope-matched private-compositor comparison on the final binary is still
required; historical gates alone cannot prove current parity. Text/ANSI/graphics
median and text/ANSI/tabs p90 PTY gates remain unmet in the archived result.
The observation gates use Foot's median but Monstar's loaded p90 where it is the
better comparator. None of these observations establishes physical latency.

`python3 bench/baseline_summary.py bench/pty-block-scan-three-terminal.json`
reproduces the 200-sample distributions for each terminal/workload and identifies
the input SHA-256. The source archive hash is
`2ef2490c8ed267001b2cd4bc267b42a7c99fa43c363abd02210f2baa3d512f05`.
The [feature evidence ledger](feature-evidence.md) records exact available
Foot/Monstar binary hashes and limited source/document evidence for selection,
wrapped copying, search and reflow. Comparator runtime feature checks remain
outstanding; documentation has not been promoted to tested parity.

The validated wrap-copy milestone above supersedes the initial implementation
status. No desktop benchmarking was resumed.

## Resumed full objective: word and line selection

The attachment was reread on 2026-09-05; the active objective includes the full
Foot/Monstar baseline, numerical targets, optimization and prioritized daily-use
feature set. The earlier Ekko/Finix focus does not narrow this completion scope.
The prior worktree and exact installed build were inspected before editing.
Desktop benchmarking remains disabled; this milestone used a private compositor.

Double-click now selects a word and triple-click a physical row. Subsequent
dragging extends by the same unit in either direction, including history.
The CUDA selection kernel computes boundaries from viewed GPU cells; the host
only tracks click timing/coordinates and requests a selection mode. Shift retains
local selection when a TUI enables mouse tracking. Ordinary application mouse
reports retain their existing path. No parser, terminal-state or rasterization
work moved to the CPU. No new GPU allocation or persistent cache was introduced.

Word grouping is explicitly limited: letters/digits/underscore and non-ASCII
base glyphs form a group; identical ASCII punctuation forms a group; spaces form
a group. Combining marks and wide pairs remain attached. This is not Unicode
word segmentation. Rows are physical rows: soft-wrap joining and reflow remain
open. A smaller click-only implementation was rejected because dragging would
immediately collapse the expanded selection back to cells. One mode parameter
on the existing selection operation avoids a separate selection API/cache.

Validated build: `/nix/store/pqajw1ksh35f4l6l8k1pqjglm8z6614x-cudaterm-0.1.0`.
These commands exited zero:

- `nix build .`
- `nix run .#selection-test`
- `nix run .#scrollback-test`
- `nix run .#sync-test`
- `nix flake check`

The CUDA tests check literal expected text for word punctuation, combining/CJK
cells including a wide tail click, reverse and multirow drags, history, physical
rows, whitespace and clamping on a 1×1 grid. Existing tests verify highlighting,
copy-buffer growth and invalidation. Private Weston checks deliver actual double
and triple clicks with Shift under application mouse tracking and verify exact
UTF-8 text through compositor clipboard copy/paste and bracketed-paste framing.
The same suite checks ordinary dragging, large external paste, complete graphics
frames, child exit and keyboard delivery during decoding. Its 0.1 ms keyboard
sample is functional evidence only, not a new latency distribution or target.

Raw logs: `bench/word-selection-{build,gpu,window,flake}.log`. The GPU test log is
empty because successful executables are silent; the sequential Nix command
returned zero. Flake evaluation warns about existing missing app metadata and
unknown `finixModules`; it succeeds. No sanitizer result is claimed for this
milestone. The configured Finix wrapper still references the preceding build;
its integration sources remain intact, but it has not been rebuilt for selection.

Completion audit remains **incomplete**: there are historical matched parser
barrier samples and partial resource/presentation evidence, but these do not
prove the full requested metric/window/workload matrix on the current build.
No numerical acceptance-target table was found in the current progress or
acceptance documents; descriptive completion criteria are not numerical targets.
Before further performance optimization, consolidate baseline distributions and
set numerical gates against the better measured comparator. Unmeasured cases
must remain unknown. Allocation churn, broad retained-memory lifecycle coverage,
current multiwindow comparison and physical input/display latency still need
scope-matched evidence. Existing isolated measurements cannot prove parity.

Next feature work: record soft-wrap metadata consistently in all CUDA parsing
paths and history, then verify wrapped copying/reflow; add history search and
expand grapheme behavior. Revalidate actual comparator features against their
recorded binaries. Preserve Ekko graphics and Finix integration throughout.

## Ekko and memory update

The new [Ekko compatibility report](ekko.md) supersedes older graphics-support
and memory statements below. Real Ekko plus terminal-browser passes CUDA pixel
and input checks; a private Weston capture verifies window presentation. Idle
parent RSS fell from 232 to 115 MiB and NVIDIA GPU memory from 484 to 316 MiB in
the matched private-compositor test. Full Foot/Monstar parity remains open.
Desktop benchmarking remains disabled as requested; these tests are headless.

## Current result

Cudaterm now has three GPU parsing paths: a parallel prefix-scan layout for plain
ASCII/CRLF prefixes, parallel UTF-8/SGR/tab line parsing, and a cooperative warp
interpreter for other controls and UTF-8.
All validation, parsing, screen updates, row clearing, and rasterization stay on
the GPU. The CPU transports PTY/input/window events and retrieves inspection or
response data. It now also reads the GPU classifier result to choose kernel
launches, without inspecting or parsing terminal bytes on the CPU. The warp uses shared parser state and ordered parallel fill jobs;
controls are consumed together until an observable cell update is required.
CSI syntax now accumulates parameters in registers, initializes only used
parameter slots, and commits shared state at sequence or chunk boundaries.
C0 controls and ESC retain the byte interpreter interruption behavior.

This replaces the initial per-scroll whole-screen copy, then the serial row-map
parser. The smaller cooperative-warp optimization was measured but still took
about 7 ms for 64 KiB. GPU prefix scans reduced that headless ASCII measurement to
about 0.234 ms. The fast path preserves delayed wrap, partial lines, existing
screen contents, scrolling and colored pens; unsupported prefixes are processed
by the CUDA interpreter, never a CPU parser.

The host now wakes GLFW from a one-shot PTY waiter instead of waiting for an
8 ms timer. The waiter sleeps when unarmed, coalesces notifications, and has
bounded shutdown. Rendering still has a deadline so the last dirty frame is
painted after output stops. Added Insert/Delete/PageUp/PageDown/Shift-Tab and
control punctuation input mappings.

## Unicode and VT compatibility

The Nix build converts GNU Unifont 17.0.05 into a bitmap atlas with BMP and
supplementary glyphs; CUDA performs
all runtime glyph lookup and rasterization. Glyph data and copyright/license
files are installed under `share/cudaterm`. Unicode 16.0.0 scalar widths, extended
with Unifont combining overrides, support wide base/tail pairs and up to three
combining marks per cell. Wide pairs are repaired when overwritten, shifted,
erased, or clipped by resize. Greek, Cyrillic, CJK, and accents were visually
inspected from a CUDA-rendered image. Missing glyphs display a replacement glyph; grapheme segmentation, shaping, and emoji sequences are
not implemented. ASCII batching remains available after wide-cell output. The bulk path captures
cell flags before scattering text, then repairs orphaned wide pairs from that
immutable snapshot. Short warp runs repair their two boundaries before writing.

Added ICH/DCH/ECH, IL/DL, SU/SD, reverse index, origin and autowrap modes,
configurable tab stops, forward/backward tabs, and saved cursor attributes.
Insert/delete clears only its inserted/vacated cells before repairing orphaned
wide pairs, preserving intact glyphs shifted beside those cells. RIS now returns to a clean
main screen, clears both grids with two bounded fill jobs, and resets modes,
saved state, attributes, and tab stops. A maximum-height regression covers the
fill-job queue capacity.

## Matched-grid throughput

RTX 4090, NVIDIA driver 595.91.07, Linux 7.2.0. Foot 1.27.0 with PGO;
Monstar 1.1.0 from the local sandbox build. Each terminal/workload has 200 measured samples
(two rounds, each five launches × twenty iterations), after one discarded launch
per run. The child waits
one second, completes an initialization cursor query, and rejects geometry
changes. Every terminal reported **318×89 cells**. Payloads contain whole
patterns near 64 KiB, identical across terminals for each workload.

Median PTY-to-cursor-response barrier duration in milliseconds for the build
including bounded scan fusion, input synchronization changes and ASCII insert
batching. All three terminals were rerun with identical benchmark code.

| Workload | Foot | Monstar | cudaterm |
| --- | ---: | ---: | ---: |
| text | 0.272 | 2.043 | 0.316 |
| ansi | 0.279 | 2.496 | 0.407 |
| unicode | 0.543 | 2.266 | 0.411 |
| graphics | 0.428 | 1.955 | 0.455 |
| tabs | 0.401 | 1.900 | 0.359 |

**Overall parity is not established**. Cudaterm is faster than Foot on this
Unicode and tabs sample sets but slower on text, ANSI and graphics. It is faster than
Monstar on these five parser-barrier workloads. Cudaterm's Unicode medians varied
from 0.323 to 0.439 ms between rounds. Graphics and tabs rankings against Foot
reversed between rounds, so aggregate rankings need caution. Samples within a
launch are correlated, and glyph rendering, shaping and emoji support differ.
These measurements do not prove compositor presentation or input-to-photon latency.

Exact commands, versions through store paths, geometry and raw samples are in
`bench/pty-block-scan-three-terminal.json`. A post-run audit checked all 3,000
sample geometries, realized payload sizes across terminals and timestamp
durations. The initial 0.2-second-settling launch failed its geometry check and
was excluded before restarting the complete comparison with one-second settling.
No build or agent GPU tests overlapped the runs; external desktop load was not
isolated. These results do not attribute changes since earlier runs to scan
fusion alone. Preceding comparisons remain in
`bench/pty-short-tail-three-terminal.json` and `bench/pty-current-three-terminal.json`.
Terminal order rotates between workloads and reverses in round two. Each run
uses the protocol above. The earlier row-map comparison remains in
`bench/{cudaterm,foot,monstar}-rowmap-stack-{text,ansi,unicode,graphics,tabs}.json`.
Previous results remain in `bench/cudaterm-parallel-tabs-*.json` and
`bench/{foot,monstar}-matched-*.json`.
Preceding compact history samples are `bench/cudaterm-compact-history-{text,ansi,unicode}.json`. Fixed-stride history
samples are `bench/cudaterm-scrollback-{text,ansi,unicode}.json`. Preceding selection samples
are `bench/cudaterm-selection-{text,ansi,unicode}.json`. The preceding texture results
are `bench/cudaterm-texture-{text,ansi,unicode}.json`, preceded by
`bench/cudaterm-resume-final-{text,ansi,unicode}.json`. Earlier resume
runs are retained as `cudaterm-fragment-resume-*`; preceding Unicode extension
runs are `cudaterm-unicode-final-*`. The paired old-build
ANSI run is `bench/cudaterm-unicode-extension-old-ansi.json`. Initial extension
runs are retained as `cudaterm-parallel-unicode-*`, and the preceding line-parser
measurements as `cudaterm-styled-lines-*`. The
`cudaterm-csi-registers-*` files preserve the preceding measurements. Earlier
`cudaterm-wide-batching-*` files preserve the pre-CSI results. The
`cudaterm-unifont-*` files preserve the pre-batching measurements. Earlier cudaterm matched files
record the pre-Unifont implementation. Font overrides
were needed to attain matching cells under compositor tiling: Foot DejaVu Sans
Mono size 11 / line-height 16px; Monstar DejaVu Sans Mono 17px / cell-height -6.
These are comparison settings, not changes to user configuration.

The `*-initial.json` and `*-rowmap.json` files are historical measurements with
different geometries. `*-before-control-batching.json` record an intermediate
implementation. `cudaterm-prefix-text-concurrent-sanitizer.json` was accidentally
collected during a sanitizer run and is **excluded** from comparisons.

## Verification

- `nix build .`, `nix run .#test`, `nix run .#plain-test`,
  `nix run .#vt-test`, `nix run .#unicode-test`, `nix run .#csi-test`, `nix run .#styled-test`,
  `nix run .#workspace-test`, `nix run .#selection-test`, `nix run .#scrollback-test`, `nix run .#charset-test`, and `nix flake check`
  succeed on the current implementation.
- The main suite has 13 GPU regressions: cursor/erase defaults, colors, streaming
  and malformed UTF-8, margins, alternate screen, modes/replies, resize, raster
  bytes, chunk invariance, and invalid dimensions.
- The parallel-path suite compares 24 seeded scenarios against byte-at-a-time
  execution on 1×1, 7×4 and 80×24 grids. Five additional cases compare
  batching after wide/combining text, overwriting either wide half, partial
  overwrite without scrolling, and scrolling. It checks hidden state through a following
  write/query and a resize, including pending wrap, partial margins, final CR,
  trailing controls, long unbroken runs, colors and pre-existing screen content.
- The VT suite covers editing, reverse scrolling, margins, origin/autowrap,
  tab stops, and saved attributes. The Unicode suite covers decoding, combining,
  wide pair edits and clipping, plus rendered Greek/CJK pixels and accents.
- CUDA 12.9 memcheck reports zero errors on the expanded batching suite.
  Racecheck reports zero hazards and warnings on the Unicode suite after the
  batching changes. The full batching racecheck was interrupted for runtime
  cost without a completion summary; it is not claimed as passed.
- The styled-line suite compares bulk feeds of at least 512 bytes against
  byte-at-a-time feeds, including inherited RGB/indexed colors and attributes,
  blank colored lines, wrapping, scrolling, trailing syntax, wide cells,
  partial margins, autowrap-off, long lines, and unsupported suffix fallback.
  Unicode additions cover mixed scripts and supplementary scalars, early wide
  wrapping, pending wrap, combining marks at line starts and across SGR changes,
  single-column replacement, existing wide tails without scrolling, and
  truncated UTF-8 after an accepted prefix. Resume coverage includes partial
  ESC/CSI, two-/three-/four-byte scalars, OSC terminators, long unfinished OSC,
  fragments consuming an entire feed or leaving a small remainder, split CRLF,
  and leading tab controls.
  CUDA 12.9 memcheck and racecheck completed with zero errors/hazards using
  `cudaterm-styled-test --bulk-only`; that mode instruments the bulk path while
  the ordinary Nix test retains the full reference comparison.
- The CSI suite checks every split position for default/empty parameters,
  private modes, 16/17 parameter limits, large values, embedded C0 controls,
  ESC and CAN cancellation, cells/colors, cursor state, and replies. CUDA 12.9
  memcheck and racecheck both completed with zero errors/hazards on this suite.
- Unicode tests additionally cover every split position for mixed two-, three-,
  and four-byte scalars, combining marks, overlong encodings, surrogates,
  out-of-range values, stray continuations, and interrupted sequences.
- After the reset fix, VT memcheck reports zero errors and VT racecheck reports
  zero hazards and warnings. All six ordinary GPU suites passed again after the parallel line change.
- The Nix package check exercises the benchmark against a synthetic PTY,
  including its initialization handshake and newline-free response.
- CUDA 12.9 memcheck on the parallel-path suite reports `0 errors`; racecheck
  on the main suite reports `0 hazards` and `0 warnings`. These run separately
  from performance measurements and cover the exercised cases only. A
  shared-predicate race found during development was fixed by synchronizing
  before the leader mutates parser state.
- A real-window quiet-PTY smoke test received output before and after a 1.5 s
  pause, preserved both lines in the dump, and propagated child exit status 37.

## Remaining work

1. Parallelize ANSI-heavy and Unicode processing while expanding VT correctness:
   complete control-string handling, reset behavior, and real TUI compatibility
   remain incomplete. Profile and parallelize ANSI/Unicode parsing beyond
   short ASCII runs.
2. Expand grapheme/shaping support and supplementary GPU glyph coverage; improve
   scrollback reflow, richer selection and complete modifier handling.
3. Measure actual presentation and input latency, reduce tail latency, and
   compare idle CPU/GPU/memory use over representative interactive sessions.
4. Expand tests against an independent VT reference and real TUI workloads.

The full user goal remains active. Successful builds and competitive ASCII
throughput are not substitutes for terminal completeness or broad parity.

## Parser optimization experiments

The headless 318×89 ANSI benchmark improved from a median 18.840 ms to 15.154 ms
for about 64 KiB when CSI parameter scanning moved to registers. Raw samples:
`bench/engine-before-csi-registers-ansi.json` and
`bench/engine-csi-registers-ansi.json`. A separate UTF-8 register-accumulation
experiment measured 31.853 ms before and 31.974 ms after, so it was reverted;
its raw samples remain in `bench/engine-{before-utf-registers,utf-registers}-unicode.json`.
These five-sample headless timings are diagnostic and do not measure display latency.

## Parallel styled lines

`src/styled.cuh` parses each UTF-8/SGR line independently, then scans associative
color/attribute transformations and row advances. Painting preserves old cells
outside writes and clears recycled rows using the pen active when each row is
created. Lines longer than 4096 bytes, unsupported syntax, partial parser state,
and unsupported modes use the general path. A supported prefix can be committed
before the interpreter handles its suffix. A bounded GPU resume step now finishes an initial parser fragment or leading
control byte, then reclassifies the remaining input. Unsupported syntax later
in the feed can still send its suffix through the slow path.

The first prototype ran the larger scan for plain text too and regressed its
headless time. Reading the GPU classifier result on the host now selects the
lighter plain path. Final headless medians were 0.103 ms text and 0.863 ms ANSI
for about 64 KiB at 318×89; raw data is in
`bench/engine-styled-selected-{text,ansi}.json`. Earlier prototype results are
retained as `bench/engine-styled-lines-*.json`. The line-summary workspace adds
32 bytes per capacity entry. Workspace is allocated lazily, starting at 65,536
entries and doubling as needed up to the 1 MiB input limit. Line summaries use
up to 32 MiB, two integer arrays add up to 8 MiB, and CUB scratch is additional. Broader latency and resource
comparisons remain outstanding.

The line path now decodes valid UTF-8 and simulates per-scalar cell widths before
scanning row advances. Painting attaches combining marks in place, writes wide
base/tail pairs, and preserves early-wrap erasure colors. Invalid or incomplete
UTF-8 rejects that line so the streaming interpreter retains recovery semantics.
No shaping or supplementary font coverage was added by this optimization.

Paired headless ANSI runs of the previous and extended implementations are in
`bench/engine-unicode-extension-ansi-paired.json`, including executable paths.
The new build was slightly faster in both pairs, despite a larger slowdown in
one windowed sample. Feed-boundary fallback and run-to-run variance remain
important limits on performance conclusions.

## Resuming split input

The classifier marks initial parser fragments for the warp interpreter, which
consumes at most 4096 bytes and stops once parser state becomes neutral. The
host reads only the consumed-byte count and launches classification on the
remaining device bytes. An unfinished longer control string retains its parser
state and uses the general fallback. A leading LF at column zero is handled
directly by the parallel paths, avoiding a resume round trip for split CRLF.
All six GPU suites and `nix flake check` passed after this change; styled bulk
memcheck and racecheck completed with zero errors and hazards.

## Presentation and first-feed latency

A host trace isolated the first-feed delay to presentation after the initial
cursor reply. In `bench/first-feed-trace.csv`, that draw/swap took 6.353 ms;
the following 65,512-byte engine feed took 0.289 ms. Early workspace reservation
and `CUDA_MODULE_LOADING=EAGER` did not remove the delay, so neither setting is
retained. Diagnostic samples are in `cudaterm-reserved-text.json`,
`cudaterm-reserved-eager-text.json`, and `engine-reserved-cold-text.json` under
`bench/`.

The host now uploads the CUDA-rendered shared PBO to an RGBA8 texture and draws
a fullscreen quad. CUDA still rasterizes every glyph. Texture dimensions follow
the framebuffer on both growth and shrink; the PBO retains its capacity. A real
window check confirmed upright top/bottom markers, colors, and multilingual
text after compositor sizing. In `bench/texture-feed-trace.csv`, the comparable
texture upload/draw/swap took 0.872 ms. These host intervals include any GPU
completion waits and are not isolated GPU execution or input-to-photon timings.
The corresponding diagnostic barrier files are `cudaterm-traced-text.json` and
`cudaterm-texture-traced-text.json`. Matched comparisons use untraced launches.

Median complete process lifetimes (including the child's 0.2-second settling
period, all barriers, and shutdown) changed from 294.881 to 275.757 ms for text,
287.118 to 270.428 ms for ANSI, and 286.427 to 270.004 ms for Unicode. These are
not terminal initialization measurements.

All seven GPU suites passed through Nix after this change. The new workspace
suite exercises feeds around the 64 KiB boundary, growth through 1 MiB, and
reuse with smaller colored Unicode scans and resets. CUDA memcheck completed
with zero errors on that suite during workspace development.

## Private mode lists and saved cursor

DECSET/DECRST now process mode 1049 in parameter order alongside the other
private modes. Previously, 1049 only worked in the first position and returned
early, skipping following parameters. Modes such as cursor visibility and
bracketed paste therefore failed when combined with a screen switch. Repeated
1049 entry/exit retains the existing idempotent behavior.

Mode 1048 now uses the same CUDA save/restore operations as DECSC/DECRC,
including pen, origin, autowrap, and delayed wrap. Semantics follow the
[xterm control sequence reference](https://www.invisible-island.net/xterm/ctlseqs/ctlseqs.html).
The VT regressions cover both parameter orders, every split position in combined
entry/exit sequences, repeated switches, ordered origin changes, and save/restore
interoperability with ESC 7/8. Modes 47/1047 and broader alternate-screen
compatibility still need implementation and independent reference testing.

## Modified keyboard input

Navigation and F1–F12 now encode Shift, Alt, and Control with xterm modifier
parameters. For example, Ctrl-Left sends `CSI 1;5 D` and Alt-Ctrl-Left sends
`CSI 1;7 D`. Previously Ctrl was dropped on these keys, Shift had no effect,
and Alt only added an escape prefix. Ordinary cursor keys still follow
application-cursor mode; unmodified F1–F4 retain SS3 in both modes.

`src/input.hpp` contains the GLFW-independent encoder; the host callback maps
keys and transports the resulting bytes. The Nix package check runs CPU-only
literal sequence tests for all 22 unmodified special keys, both cursor modes,
all seven nonzero modifier combinations, and modified key families. These tests
verify encoding, not delivery of physical keyboard events through the compositor.
Broader modifier handling, keypad modes, selection, and scrollback remain open.

Validation after both changes: `nix build .`, all seven `nix run` GPU suites,
and `nix flake check` exited zero. CUDA 12.9 memcheck and racecheck on the expanded
VT suite completed with zero errors, hazards, or warnings. Existing performance
samples predate these compatibility changes; no new performance claim is made.

## Visible-screen selection and clipboard

Left-button dragging now selects an inclusive linear range of visible cells;
Ctrl-Shift-C copies it and the existing Ctrl-Shift-V binding pastes. Selection
normalization, wide-pair endpoint expansion, highlighting, and UTF-8 serialization
run in CUDA. The host handles pointer coordinates and clipboard transport.
Combining marks and supplementary scalars survive copying even when the displayed
glyph is a replacement. Clipboard storage is allocated lazily and retained up to
16 bytes per screen cell plus row separators (about 2 MiB at the maximum grid).
Ordinary feeds incur no selection-clearing kernel when there is no selection.

Nonempty output and resize invalidate selection. Copied text trims unmarked
trailing spaces on each row and preserves physical row breaks. Soft-wrap joining,
word/line selection, scrollback selection, and application mouse reporting remain
unfinished. Pointer coordinates are scaled from window units to framebuffer
pixels; drag anchors use event-ordered positions so a queued later move cannot
replace the press position.

`selection-test` covers forward/reversed/clamped ranges, row-map scrolling,
selection invalidation, trailing spaces and marked spaces, wide endpoints,
Unicode copying, exact highlight colors, and buffer growth/reuse through the
512×256 grid limit. `tests/window_selection.py` exercises an owned X11/Xwayland
window with xdotool, dragging across ASCII, Latin, CJK, and combining text, copying
it, and pasting it back to the raw PTY child. Its rapid mode sends drag events
without pauses. This is a manual graphical integration test, not a headless build
check or a test of native Wayland clipboard behavior.

After selection integration, `nix build .`, all eight GPU suites, and
`nix flake check` exited zero. Selection memcheck and racecheck completed with
zero errors/hazards/warnings. Both paced and rapid real-window clipboard tests
passed; raw results and resolved binaries are in `bench/window-selection.json`
and `bench/window-selection-rapid.json`.

The latest matched-grid text/ANSI/Unicode medians are 0.347/0.497/0.496 ms.
A following adjacent old/new Unicode comparison measured 0.556/0.424 ms medians
and 2.039/2.549 ms maxima. Those runs are retained in
`bench/cudaterm-selection-paired-{old,new}-unicode.json`. The old executable
predates both selection and the preceding compatibility changes. These small
samples do not show a consistent median slowdown, but tail latency and variance
still need broader measurement; they do not prove zero performance cost.

## CUDA scrollback

The terminal retains up to 4096 full-screen primary rows on the GPU. Mouse-wheel
and Shift-PageUp/PageDown navigation move a viewport over history and live rows;
typing or pasting follows live output. New output keeps a historical viewport
anchored until its oldest rows are evicted. Selection and UTF-8 copying use the
viewed rows, while the diagnostic `cells()` API retains its live-screen meaning.
Alternate-screen and partial-margin scrolling do not enter history. RIS clears
history, ED3 clears history without erasing live cells, and ED2 preserves history.

Both parallel parsers retain generated rows, including output that scrolls more
than a screen within one feed. GPU commits reserve ring slots and rotate indices;
a parallel copy reads departing old rows through the inverse rotation before
clearing and painting. Printable output is then routed to retained history or
the live grid by logical row. Plain-text repair handles wide pairs in retained
rows; styled painting preserves glyph widths, combining marks, and pen colors.
The general interpreter captures full-screen newline scrolls separately.

The first history implementation reserved 64 MiB (4096×512 cells at 32 bytes
each), independent of current column count. It now allocates 4096×current-columns
cells: 10 MiB at 80 columns, 39.75 MiB at 318 columns, and 64 MiB at 512 columns. Resize allocates another history buffer temporarily,
preserves chronological slots, clips/pads columns, and removes clipped wide
bases. Reflow, configurable capacity, and a smaller history representation remain
resource and compatibility work. Physical row breaks are still preserved when
copying soft-wrapped text.

The new `scrollback-test` checks anchoring and follow behavior, every viewport
against byte-at-a-time reference parsing for plain, styled Unicode, long wrapping,
and control-fragment inputs, plus overwritten wide pairs, eviction beyond 4096
rows, history resize, alternate-screen exclusion, erasure, and raster output.

Validation: `nix build .`, all nine GPU suites, and `nix flake check` exited zero.
CUDA 12.9 memcheck and racecheck on the complete scrollback suite reported zero
errors, hazards, and warnings. `bench/window-scrollback.json` records the final
real-window test: Shift-PageUp and wheel navigation, rapid dragging over history,
Unicode copying, and pasting back to the raw PTY child all passed on X11/Xwayland.

With scrollback enabled, the latest 15-sample medians are 0.473/0.556/0.522 ms
for text/ANSI/Unicode; raw samples are `bench/cudaterm-scrollback-*.json`. These
are higher than the preceding selection medians (0.347/0.497/0.496 ms), with both
new retention work and run-to-run variability present. History storage/copying
needs further profiling. No performance parity or unchanged-throughput claim is
made from these samples.

## Compact history storage and idle resources

History row stride now follows the column count in every capture, bulk paint,
view lookup, repair, and resize path. Ring slots and retention remain unchanged.
A new regression exercises eviction followed by repeated 1↔512-column resizes,
newly appended rows, and clipped wide glyphs. Narrowing physically releases the
unused columns; widening pads them without resurrecting clipped text.

`bench/idle_resources.py` launches three fresh windows, waits for a prompt and a
further one-second settle, then measures each parent over three idle seconds.
All terminals reported 318×89. Foot 1.27.0 and Monstar 1.1.0 used the same font
and geometry overrides as the earlier throughput runs. Raw samples, commands,
and resolved executables are in `bench/idle-{history-fixed,history-compact,foot,monstar}.json`.

| Terminal | Median parent RSS (MiB) | NVIDIA compute-process memory (MiB) |
| --- | ---: | ---: |
| Foot | 35.64 | unavailable |
| Monstar | 43.69 | unavailable |
| cudaterm, fixed history stride | 213.22 | 560 |
| cudaterm, compact history stride | 213.95 | 536 |

The driver-reported allocation decreased by 24 MiB in every compact-history
sample; RSS remained similar. This is still a substantial resource gap. Missing
compute-process memory for Foot/Monstar does not mean zero GPU memory. The probe
excludes compositor and descendant-process resources and does not measure GPU
utilization. Each cudaterm build recorded one 10 ms CPU tick and two zero-tick
samples; Foot and Monstar recorded zero ticks in all three intervals. At this
short duration, zero means below the accounting resolution, not zero work or
established idle-efficiency equivalence.

Validation after compaction: `nix build .`, all nine GPU suites, and
`nix flake check` exited zero. CUDA 12.9 memcheck and racecheck on the expanded
scrollback suite reported zero errors/hazards/warnings. The rapid real-window
history-copy test passed, recorded in `bench/window-compact-history.json`.

Current matched-grid text/ANSI/Unicode medians are 0.467/0.490/0.582 ms, with
maxima 2.801/2.729/2.674 ms. Raw samples are retained in
`bench/cudaterm-compact-history-{text,ansi,unicode}.json`. These small runs do not
establish a consistent throughput improvement; the measured benefit of this
change is reduced history allocation and driver-reported process memory.

## DEC Special Graphics and real ncurses borders

CUDA now handles G0/G1 ASCII and DEC Special Graphics designations (`ESC ( B`,
`ESC ) B`, `ESC ( 0`, `ESC ) 0`) and SI/SO invocation. All 32 special characters
are stored as Unicode scalars with single-cell advance; non-ASCII UTF-8 remains
unchanged. This follows the character-set controls in the
[VT100 programmer manual](https://vt100.net/docs/vt100-ug/chapter3.html).
DECSC/DECRC, mode 1048, and alternate-screen restoration retain the charset
state; RIS resets it. Unknown designations are consumed without changing sets,
and CAN/SUB/ESC cancellation, intervening C0 controls, and ignored DEL preserve
streaming behavior. G2/G3 and national character sets remain unsupported.

Mapping is present in warp writes, plain scatter, and styled painting; graphics
mode does not disable parallel parsing. The GPU classifier now sends a leading
G0/G1 designation through bounded fragment resume before retrying the remaining
feed. Without that step, a 65,537-byte graphics feed fell entirely through the
interpreter: its five-sample headless median was 182.144 ms. The same actual
payload now measured 5.988 ms. Raw data and executable paths are in
`bench/engine-graphics-{before-resume,resume}.json`. Requested sizes differ
because the benchmark was corrected to include designation framing within the
requested byte budget; both recorded actual payload sizes are identical.

The new graphics PTY workload consists of SGR-colored border characters bracketed
by one graphics designation and one ASCII restoration. At 318×89 cells, with
15 samples per terminal and equal 65,518-byte payloads, medians were cudaterm
0.586 ms, Foot 0.412 ms, and Monstar 5.463 ms. Maxima were 2.108/2.159/6.634 ms.
These are parser barriers, not rendering or presentation timing. Headless and
PTY samples differ in feed chunking and scheduling and are not interchangeable.

`charset-test` checks the entire mapping, every input split for designation and
invocation, saved/reset state, cancellation, bulk/history equivalence, and a
pixel-for-pixel match between DEC and Unicode borders. A real ncurses fixture
uses `NCURSES_NO_UTF8_ACS=0`, renders a border, selects it with a rapid drag, and
copies/pastes it back through the PTY. The old build produced `0Bqq`; the current
build passes with `┌──┐`. The final result is `bench/window-ncurses-border.json`.

After these changes, `nix build .`, all ten GPU suites, and `nix flake check`
exited zero. Charset memcheck and racecheck reported zero errors/hazards/warnings.

## Ordered history copies and parallel tabs

Interpreter history copies now execute through the warp's ordered work queue.
The warp copies each departing row after prior cell edits and before clearing
its recycled storage. Besides parallelizing the copy, this fixes an ordering
bug: an early wide-character wrap could queue an erase of the last cell but copy
the old character into history first. A 3×1 regression writes `ABZ`, moves to the
last column, and writes `中`; history must retain `AB` plus a blank, not `ABZ`.

The parallel styled-line path now processes horizontal tabs using the current
GPU tab-stop table. Tabs advance to the next stop or last column, perform no
cell writes, and cancel delayed wrap. Both layout and painting handle this
operation; custom stops and Unicode/SGR retain the same streaming semantics.
Tests compare all history viewports and raster pixels against byte-at-a-time
execution for ordinary/custom tabs, pending wraps, and leading/trailing tabs.

For 65,534 bytes of tabbed output at 318×89, five-sample headless medians changed
from 241.226 ms with serial history copying, to 35.496 ms with warp copies, to
5.896 ms with parallel tab layout. Raw samples and executable paths are in
`bench/engine-history-copy-{before,warp}.json` and
`bench/engine-parallel-tabs.json`. This still exposes a substantial large-feed
cost and does not establish parity. Headless feed timing is separate from PTY
chunking and presentation latency.

After both changes, `nix build .`, all ten GPU suites, and `nix flake check`
exited zero. CUDA 12.9 memcheck and racecheck on the expanded scrollback suite
reported zero errors/hazards/warnings, including queued-copy ordering and tab
layout across all retained viewports.

For the matched-grid tabbed PTY workload (15 samples per terminal), medians were
cudaterm 0.663 ms, Foot 0.405 ms, and Monstar 6.563 ms; maxima were
2.306/2.161/9.186 ms. The current five-workload samples are
`bench/cudaterm-parallel-tabs-*.json`, with tabbed competitor samples in
`bench/{foot,monstar}-matched-tabs.json`. Parser/PTY improvements do not prove
presentation-latency equivalence; large single-feed cost remains a profiling
target.

## Avoid duplicate history fills

Styled painting now skips a new historical row's serial clear when
`prepare_history` has already filled it with the same foreground and background.
Visible rows and historical rows created with different colors retain their
existing clear. This keeps the change local to `styled_clear`; removing all
clears would lose row-creation colors when SGR changes within a feed.

Paired five-sample headless runs at 318×89 with a 65,536-byte request gave
tabbed medians of 5.704 ms before and 4.129 ms after, and DEC graphics medians
of 4.621 ms before and 3.756 ms after. Actual payload sizes match within each
pair. Raw samples and executable paths are in
`bench/engine-history-clear-{before,skip}-{tabs,graphics}.json`. These small
samples measure feed completion, not display latency or parity with Foot.

A regression alternates red, green, and default backgrounds across tabbed
Unicode lines and compares every history viewport's text and pixels against
byte-at-a-time execution. `nix build .`, `nix run .#scrollback-test`,
`nix run .#charset-test`, `nix run .#selection-test`, `nix run .#vt-test`,
`nix run .#test`, `nix run .#plain-test`, `nix run .#unicode-test`,
`nix run .#csi-test`, `nix run .#styled-test`, `nix run .#workspace-test`,
and `nix flake check` all exited zero.
CUDA 12.9 memcheck and racecheck on the expanded scrollback suite also
completed with zero errors, hazards, or warnings.

## Compositor capture latency probe

The new `bench/visible_output.py` provides a software observation beyond the
existing parser barriers: it detects alternating terminal background colors in
compositor captures. It verifies two calibration transitions, keeps the child
alive through observation, and checks PTY geometry on every sample. Initial
inspection caught a geometry-reporting race before cudaterm's first compositor
resize; final samples wait for startup and all use 318×89. No terminal scheduling
code changed in this step.

On Linux 7.2.0, tomoe 0.1.0, RTX 4090 / NVIDIA 595.91.07, the same Wayland
session and 64×16 capture region at (40,40) gave these 20-sample medians/maxima
in milliseconds:

| Terminal | Transition alone | After 3,000 scrolling lines |
| --- | ---: | ---: |
| cudaterm | 14.468 / 27.448 | 45.079 / 53.142 |
| Foot 1.27.0 | 19.586 / 32.332 | 31.519 / 46.381 |
| Monstar 1.1.0 | 29.684 / 32.966 | 32.553 / 35.087 |

Raw timestamps, exact executable paths and terminal arguments, geometry, capture
durations, and attempt counts are in `bench/visible-{cudaterm,foot,monstar}-{0,3000}.json`.
Font overrides match the earlier 8×16 grid comparisons; glyph rendering differs.
The application writes 72,000 load bytes before the marker; PTY ONLCR
expansion makes these 75,000 bytes received by the terminal. Capturing itself took roughly
13–18 ms per attempt and polling affects scheduling, so these results cannot
rank physical display latency or prove idle parity. They do expose a worse
capture-observed result for cudaterm under this output burst, warranting traced
investigation of feeding and frame scheduling. The fixed 8,333 µs post-swap
frame delay remains another latency candidate; swap return is not presentation.

`nix build . && nix flake check` exited zero with the new binary-capture
regressions included in the Nix check phase. A Luna read-only review found no
blocking measurement or cleanup issue. The fixed capture region must remain
inside the fixture window; calibration is an operational check, not an OS-level
proof of pixel ownership.

A separate five-sample diagnostic with `CUDATERM_TRACE` is retained in
`bench/visible-load-trace.csv` and `bench/visible-cudaterm-load-traced.json`.
Summing host feed intervals overlapping each measured workload gives
23.953–25.916 ms across two to four feed calls. This points back to parsing or
history processing as a substantial contributor, rather than attributing the
whole gap to the frame cap. Wait intervals also include time after submission
while the observer captures pixels; they cannot all be counted as scheduling
delay. Trace flushing perturbs the run, and these diagnostics are not mixed
into the untraced comparison table.

## Parallel layout for repeated carriage returns

The visible-load fixture revealed a fallback trigger: its child writes CRLF
with PTY ONLCR enabled, so the engine receives CR-CR-LF. Both parallel validators
previously rejected the first CR, leaving the output burst to the interpreter.
`styled_lines` now accepts a bounded run of carriage returns only when followed
by LF. Painting already stops at the first CR; repeated resets of the cursor
column have no additional layout effect. Runs ending at a chunk boundary or
followed by text still use the interpreter, preserving overwrite behavior.

A paired 20-sample compositor-capture rerun at 318×89 reduced the median from
47.424 to 28.679 ms and the maximum from 59.005 to 32.270 ms. Exact binaries and
samples are in `bench/visible-repeated-cr-paired-{before,after}.json`. An initial
post-change run (`bench/visible-cudaterm-repeated-cr-3000.json`) gave 29.213 ms.
The earlier same-session Foot/Monstar medians were 31.519/32.553 ms. Capture
polling overhead and phase correlation still preclude a physical-display parity
claim, and the competitors were not rerun in this latest pair.

Separate traced diagnostics in `bench/visible-repeated-cr-trace.csv` and
`bench/visible-repeated-cr-traced.json` show total host feed intervals of
0.709–1.221 ms per burst, compared with 23.953–25.916 ms before. The new trace
confirms 75,000 load bytes plus the 30/31-byte color marker. This is evidence that
the fallback was a substantial contributor; traced timings remain separate from
the comparison samples.

Regressions cover colored Unicode history, blank lines, delayed wrap, CR runs
followed by overwritten text, incomplete runs, split runs, and the 4096-byte
line-scan boundary. History text and all viewport pixels are compared against
byte-at-a-time execution. A Luna read-only review confirmed the layout reasoning.
`nix build .`, `nix run .#scrollback-test`, `nix run .#charset-test`,
`nix run .#selection-test`, `nix run .#vt-test`, `nix run .#test`,
`nix run .#plain-test`, `nix run .#unicode-test`, `nix run .#csi-test`,
`nix run .#styled-test`, `nix run .#workspace-test`, and `nix flake check`
all exited zero.
CUDA 12.9 memcheck on the styled suite and racecheck on the scrollback suite
also completed with zero errors, hazards, or warnings.

## Grow history storage from a smaller initial allocation

History now starts with 128 allocated rows and doubles as needed to the existing
4096-row retention limit. Before each feed, the host adds twice its byte count
to a capped reservation bound; it does not inspect or parse terminal bytes. A
single byte can finish malformed UTF-8 and then emit another glyph or newline,
which can scroll twice on a one-column grid. Reserving before the feed covers
that case. The cumulative bound is conservative and reaches full capacity after
2048 input bytes even when much of the input does not scroll.

Growth copies valid history chronologically on the GPU, updates the ring head,
and preserves the browsing offset. Resize retains the allocated row capacity
while changing its column stride. Full retention, eviction, and history semantics
are unchanged. There is no shrinking after RIS/ED3 or after a burst; this targets
fresh idle windows rather than sustained-output memory use.

Three-launch measurements in `bench/idle-growing-history-{before,after}.json`
show NVIDIA compute-process memory of 536 MiB before and 498 MiB after in every
sample at 318×89. Parent RSS medians were 213.543 and 214.281 MiB. The initial
history allocation falls from 39.75 MiB to about 1.24 MiB, consistent with the
38 MiB reported reduction after driver accounting. The remaining CUDA resource
gap is substantial; these figures do not establish parity with Foot or Monstar.

Paired five-sample headless medians (ms) for 65,536-byte requests were:

| Workload | Before | After |
| --- | ---: | ---: |
| Text | 1.597 | 1.380 |
| ANSI | 2.533 | 2.467 |
| Unicode | 2.353 | 1.940 |
| Tabs | 4.065 | 1.242 |

Raw samples are `bench/engine-growing-history-{before,after}-*.json`. Warmup
includes growth to full capacity. These short runs show no sampled steady-state
regression; allocation latency is not measured by them and the apparent speedups
need more evidence before attributing them to this memory change.

New regressions cover anchored browsing through growth, resize and subsequent
append, plus malformed UTF-8 producing two scrolls from one byte. Existing
bulk-versus-bytewise history comparisons also exercise different growth timing,
full-ring eviction, selection, and rendering. Luna independently reviewed the
reservation bound and ring indexing. `nix build .`, `nix run .#scrollback-test`,
`nix run .#charset-test`, `nix run .#selection-test`, `nix run .#vt-test`,
`nix run .#test`, `nix run .#plain-test`, `nix run .#unicode-test`,
`nix run .#csi-test`, `nix run .#styled-test`, `nix run .#workspace-test`,
and `nix flake check` all exited zero.
CUDA 12.9 memcheck and racecheck on the expanded scrollback suite completed
with zero errors, hazards, or warnings.
A real-window 20-sample loaded capture run after the change gave a median
of 28.502 ms and maximum 31.639 ms at 318×89, retained in
`bench/visible-growing-history-3000.json`. The first measured burst includes
history growth; capture overhead still limits this observation.

## Application mouse reporting

The engine now parses DEC mouse tracking modes 1000 (buttons), 1002 (button
motion), and 1003 (all motion), with independent SGR encoding mode 1006. GPU
code filters events, suppresses same-cell motion and wheel releases, clamps
coordinates to the grid, and serializes reports into the reply buffer. The CPU
translates window events to cell coordinates and transports the resulting bytes.
The protocol follows [XTerm Control Sequences](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h2-Mouse-Tracking).

Shift preserves local selection and wheel scrollback. A local drag remains
local if Shift is released before the mouse button. The host retains event-ordered
pointer coordinates and held-button state; fractional vertical wheel movement
accumulates into whole application ticks. Reporting does not request redraws.
Browsing history suppresses application reports so selection remains available.
Legacy reports suppress coordinates beyond 223 rather than wrapping their bytes;
SGR supports the full current grid. Pixel coordinates, horizontal wheel reports,
focus reports, and other extended tracking modes remain unsupported.

`tests/mouse_test.cu` checks literal SGR reports, legacy encoding, split mode
sequences, modifiers, tracking resets/RIS, motion filtering, coordinate limits,
resize clamping, and history browsing. Parent review corrected initial test
expectations for the zero-based legacy limit and the explicit held-button API.
Luna contributed the host callbacks and protocol tests. Parent review also fixed
fractional wheel handling, Shift motion bypass, and unnecessary redraws.

Real X11/Xwayland fixtures passed: `bench/window-mouse.json` contains exact
press, drag, release, and wheel reports received by the child PTY;
`bench/window-mouse-selection.json` verifies rapid Shift-selection/Unicode
clipboard roundtrip with application tracking enabled; and
`bench/window-mouse-scrollback.json` checks ordinary history selection/paste.
These are functionality checks, not mouse-latency measurements.

`nix build .`, `nix run .#mouse-test`, `nix run .#scrollback-test`,
`nix run .#charset-test`, `nix run .#selection-test`, `nix run .#vt-test`,
`nix run .#test`, `nix run .#plain-test`, `nix run .#unicode-test`,
`nix run .#csi-test`, `nix run .#styled-test`, `nix run .#workspace-test`,
and `nix flake check` all exited zero. CUDA 12.9 memcheck and racecheck on the
mouse suite completed with zero errors, hazards, or warnings.

## Remove scrolling row-map arrays from kernel stacks

`cuobjdump --dump-resource-usage` identified 1024-byte temporary arrays in both
bulk commit kernels and a 1104-byte stack in the interpreter. These arrays held
row indices while rotating the screen. A shared device helper now rotates the
indices in place with three reversals, using constant temporary storage. The
same helper handles upward/downward shifts of partial scrolling regions. Luna
independently checked rotation direction and the existing regression coverage.

Compiled sm_89 resource reports in `bench/rowmap-stack-resources-{before,after}.json`
show interpreter stack size falling from 1104 to 80 bytes, and plain/styled
commit stacks from 1024 to zero. Register counts rise slightly. The measurement
command used CUDA 12.9 `cuobjdump`; exact executable paths are retained.

Three fresh idle launches at 318×89 gave NVIDIA compute-process memory of
498 MiB before and 482 MiB after in every sample. Parent RSS medians were
213.324 and 214.457 MiB. Samples are in `bench/idle-rowmap-stack-{before,after}.json`.
This is a measured 16 MiB GPU allocation reduction; substantial overhead remains.

Initial five-sample feed runs improved but showed large clock/run-order variation.
A follow-up alternated old/new builds across three rounds, reversing their order
in the middle round. Each launch used one warmup and five samples at 318×89 with
a 65,536-byte request. Fifteen-sample aggregate medians (ms) were:

| Workload | Before | After |
| --- | ---: | ---: |
| Text | 0.530 | 0.206 |
| ANSI | 0.706 | 0.430 |
| Unicode | 0.688 | 0.440 |
| Tabs | 1.297 | 0.883 |

All runs, ordering, executable paths and individual samples are retained in
`bench/engine-rowmap-stack-interleaved.json`; initial runs are
`bench/engine-rowmap-stack-{before,after}-*.json`. These headless results support
keeping the change but do not establish PTY or display parity with competitors.

Existing suites cover partial-margin insert/delete/scroll operations and bulk
history across many screen rotations. `nix build .`, `nix run .#mouse-test`,
`nix run .#scrollback-test`, `nix run .#charset-test`, `nix run .#selection-test`,
`nix run .#vt-test`, `nix run .#test`, `nix run .#plain-test`,
`nix run .#unicode-test`, `nix run .#csi-test`, `nix run .#styled-test`,
`nix run .#workspace-test`, and `nix flake check` all exited zero.
CUDA 12.9 memcheck on the VT suite and racecheck on the scrollback suite also
completed with zero errors, hazards, or warnings.

## Refreshed terminal comparisons and reply-length transfer

The matched PTY table near the top of this document now uses fresh samples from
all three terminals after the row-map stack change, with terminal order rotated
between workloads. Cudaterm remains slower than Foot for four of the five tested
parser-barrier workloads, despite improved headless kernel results. All payloads
match within each workload and all runs verify 318×89 geometry.

A separate 20-sample compositor-capture rerun gave these medians/maxima (ms):

| Terminal | Transition alone | After 3,000 scrolling lines |
| --- | ---: | ---: |
| cudaterm | 15.104 / 16.898 | 28.145 / 31.724 |
| Foot | 27.927 / 45.005 | 32.115 / 35.054 |
| Monstar | 20.235 / 33.016 | 32.613 / 35.257 |

Raw observations are `bench/visible-rowmap-stack-{cudaterm,foot,monstar}-{0,3000}.json`.
Captures use the same 64×16 region and include screenshot scheduling and transfer
overhead. They do not establish physical display or keyboard latency parity.

A subsequent host change makes `take_replies` copy only the GPU reply-length
integer instead of the whole `DeviceState`; the reply buffer's device address
is already owned by the host implementation. Reply bytes and reset ordering
remain unchanged. Two rounds with reversed old/new order, each containing
15 samples per variant and workload, are in `bench/pty-reply-length-paired.json`.
Text aggregate medians were 0.445 ms before and 0.406 ms after; ANSI medians were
0.486 and 0.503 ms. Per-round ANSI results varied, so there is no general
throughput improvement claim. The matched three-terminal table above is the
preceding build, explicitly identified by its saved executable path.

`nix build .`, `nix run .#mouse-test`, `nix run .#csi-test`,
`nix run .#vt-test`, and `nix flake check` exited zero after the reply-transfer
change. These suites exercise reply generation, draining, and reset behavior.
The read-only Luna audit also confirmed major remaining work in independent
VT/TUI validation, supplementary glyphs and grapheme handling, and presentation
verification; self-comparison of parser paths cannot prove full compatibility.
CUDA 12.9 memcheck on the mouse and CSI suites completed with zero errors.

## Supplementary Unifont glyphs

The atlas now includes 59,295 supplementary glyph records from the bundled
Unifont 17.0.05 `unifont_upper` hex source, covering supplied glyphs in planes
1, 2, 3, and 14. BMP glyph indices remain direct. Supplementary lookup uses
a 4352-entry page table and 481 allocated pages of 256 indices; missing entries
retain the replacement-glyph behavior. CUDA performs lookup and rasterization.
Combining placement offsets now cover all Unicode scalar values rather than
only the BMP. The three-mark limit, scalar width model, and lack of shaping or
emoji-sequence composition remain unchanged. These are monochrome Unifont glyphs,
not color emoji or complete Unicode coverage.

The CTFONT02 build format contains all bitmap rows and widths followed by sparse
lookup tables. The loader validates dimensions, widths, replacement availability,
page references, and glyph indices before uploading. Luna implemented the builder
and format tests; parent review corrected invalid-scalar and hex-whitespace
validation. GPU regressions compare literal Unifont pixels for U+1F600, U+10300,
U+20000, and the U+1D185 combining mark, and verify missing U+10FFFD falls back.
The inspected CUDA-rendered sample is `bench/unicode-supplementary.png`
(original `bench/unicode-supplementary.ppm`).

The new atlas and expanded offsets add about 3.35 MiB of device font data.
Three fresh idle launches at 318×89 reported 482 MiB before and 486 MiB after
in every NVIDIA compute-process sample. Parent RSS medians were 214.727 and
213.152 MiB. Raw measurements are `bench/idle-supplementary-{before,after}.json`.
This is a deliberate small memory cost for broader visible correctness; the
remaining CUDA resource gap is still substantial.

The initial matched Unicode PTY run gave 0.454 ms before and 0.597 ms after.
Two follow-up rounds reversed execution order, giving aggregate medians of
0.505 and 0.580 ms across 30 samples per variant. The individual
after-round medians varied from 0.526 to 0.672 ms, versus 0.509/0.500 ms before.
Raw results are `bench/pty-supplementary-{before,after}-unicode.json` and
`bench/pty-supplementary-paired-unicode.json`. This flags a possible performance
cost that needs isolated rasterization timing; it is not a no-regression claim.
The glyphs rendered also differ intentionally between builds.

`nix build .`, `nix run .#unicode-test -- --ppm bench/unicode-supplementary.ppm`,
`nix run .#mouse-test`, `nix run .#scrollback-test`, `nix run .#charset-test`,
`nix run .#selection-test`, `nix run .#vt-test`, `nix run .#test`,
`nix run .#plain-test`, `nix run .#csi-test`, `nix run .#styled-test`,
`nix run .#workspace-test`, and `nix flake check` all exited zero. CUDA 12.9
memcheck and racecheck on the expanded Unicode suite completed with zero errors,
hazards, or warnings.


## Isolated supplementary glyph timing

Added `--render` to the existing headless engine benchmark to isolate CUDA-event
rasterization of a fixed screen. `--dense` removes pattern CRLF; `emoji` and
`marks` exercise supplementary base glyphs and combining marks. Reusing the
benchmark avoids a separate executable and timing protocol. No renderer
optimization was made in this step.

The saved pre-supplementary engine and font were rebuilt against identical
benchmark code. `bench/raster-baseline-build.json` records the old source/font,
Nix expression and derivation, and immutable benchmark source and checksum.
Two rounds reverse old/new execution order at 318×89, with 262144 requested
payload bytes, 10000 warmup renders, and 20 measured renders per run. Aggregate
medians across 40 samples per variant/workload were:

| Fixed dense screen | Before (µs) | After (µs) |
| --- | ---: | ---: |
| Text | 22.608 | 22.528 |
| Mixed Unicode | 24.544 | 24.576 |
| Emoji | 27.648 | 29.696 |
| Combining marks | 26.416 | 28.560 |

Raw samples are in `bench/render-supplementary-long-warmup.json`. Earlier runs
in `bench/render-supplementary-paired.json` and
`bench/render-supplementary-warmed.json` showed large initial variation with
5 and 1000 warmups respectively. The longer-warmup artifact includes GPU clock
snapshots taken after each process exits, not measurements during sampling;
clocks were not locked. The old engine displays replacements or skips missing
supplementary marks, so rendered content intentionally differs.

Separate warmed feed measurements, also with reversed order, used 1000 warmup
feeds and 30 samples per run. Aggregate medians for 4096 requested bytes were
110.790 µs before and 108.420 µs after; for 65536 bytes they were 160.880 and
158.305 µs. Raw results are `bench/feed-supplementary-warmed.json` (60 samples
per variant/size). These describe repeated headless feeds, not PTY chunking or
window scheduling.

Mixed Unicode raster timing is effectively unchanged in this experiment;
dense emoji and marks add about 2 µs. These isolated measurements do not
reproduce or explain the larger PTY difference reported above. That difference
remains unresolved; this is neither a general no-regression result nor evidence
of presentation parity. Supplementary glyph support is retained.

`nix build . && nix flake check` exited zero after the benchmark changes.
The flake emits existing missing-app-meta warnings and reports zero separate
flake checks; the package build supplies its CPU checks. `nix run .#bench -- --render --dense --workload emoji --cols 80 --rows 24
--warmup 5 --repeats 3` and `nix run .#bench -- --workload unicode --warmup 2
--repeats 3` both exited zero. Their JSON parsed successfully with three positive
timings each; feed durations retain integer nanoseconds. Engine code was not
changed, so the preceding full GPU correctness and sanitizer results remain
the relevant engine validation.


## Legacy alternate-screen modes

Added CUDA parsing for private modes 47 and 1047 using a shared pointer/row-map
switch. Mode 47 retains alternate contents; mode 1047 clears the active alternate
buffer before returning to primary. Both preserve the current cursor and pen.
The clearing distinction follows [xterm control sequences](https://www.invisible-island.net/xterm/ctlseqs/ctlseqs.html).
Reusing only the old 1049 wrapper would incorrectly clear, home, save, and
restore state for legacy requests, so buffer switching is now a separate helper.
No CPU parser or additional screen allocation was introduced.

The existing 1049 save/restore behavior remains. A validity bit prevents an exit
through 1049 after a legacy entry from restoring stale main state; legacy exits
invalidate that saved entry and do not restore it. This mixed-request policy is
covered by explicit fixtures, but is not a claim of complete xterm equivalence
for arbitrary combinations with DECSC/DECRC or 1048. A Luna audit identified the
need to separate switching from saved state; primary-source review corrected
its proposed 1047 clearing point from entry to exit.

VT regressions cover every byte split of both legacy set/reset sequences,
repeated requests, retained contents, clear-on-exit, cursor/pen behavior,
legacy/1049 mixed requests, resizing while alternate is active, and RIS.

`nix build . && nix run .#vt-test && nix run .#scrollback-test &&
nix run .#charset-test && nix flake check` exited zero for derivation
`/nix/store/2fh1lkm1gfmkkl7drm2h1gl0f1lbv1iy-cudaterm-0.1.0.drv`.
CUDA 12.9 Compute Sanitizer memcheck on its `cudaterm-vt-test` exited zero with
zero errors. These are compatibility checks; no new performance or overall
terminal parity claim follows from this change.


## Combined PTY feed and reply completion

The host PTY path now calls `Engine::feed_and_replies`. It enqueues the same
CUDA parser/state work, then uses the blocking reply-length transfer as the
completion wait. Previously it called `feed` (ending in device synchronization)
and immediately `take_replies` (another blocking transfer). The existing public
`feed` keeps its synchronous contract; a private enqueue helper shares the code.
Intermediate classifier/consumed-count transfers and history/workspace allocation
ordering remain. No host parsing or asynchronous host-input lifetime was added.
Luna reviewed the default-stream ordering and the reset-before-next-feed path.
The completion reasoning follows NVIDIA's [CUDA copy synchronization rules](https://docs.nvidia.com/cuda/cuda-runtime-api/api-sync-behavior.html).

A pre-edit text run is retained in `bench/pty-feed-replies-before-text.json`
(median 0.345 ms). The subsequent comparison used two reversed-order rounds,
three measured launches per variant/workload, five parser barriers per launch,
and one discarded warmup launch at verified 318×89 geometry. Raw samples and
exact commands/executables are in `bench/pty-feed-replies-paired.json`.
Each aggregate below contains 30 samples:

| PTY workload | Before median / max (ms) | After median / max (ms) |
| --- | ---: | ---: |
| Text | 0.456 / 2.745 | 0.429 / 2.075 |
| ANSI | 0.481 / 3.115 | 0.489 / 2.708 |
| Unicode | 0.556 / 2.552 | 0.481 / 3.018 |

Text and Unicode medians improved in both rounds; ANSI did not. The earlier
single text run and Unicode maxima show substantial variation. Retain the
redundant-wait removal, but do not infer a general latency advantage, explain
the whole earlier supplementary-font difference, or claim Foot parity. These
are PTY/parser barriers, not display observations. No benchmark overlapped GPU
correctness or sanitizer work. `pty_engine_feed` trace intervals now include
reply transfer; `bench/README.md` records that scope change.

The added CSI fixtures exercise combined feeds with no replies, split queries,
small and bulk ASCII, styled input, parser continuation before bulk input,
back-to-back query draining, and an empty feed draining a previous reply. They
check literal replies and resulting cells.

`nix build . && nix run .#csi-test && nix run .#plain-test &&
nix run .#styled-test && nix run .#mouse-test && nix flake check` exited zero
for `/nix/store/vbjdrqs2sxym3pws6i14nvn897xblh77-cudaterm-0.1.0.drv`.
CUDA 12.9 Compute Sanitizer memcheck on the expanded CSI suite exited zero
with zero errors.


## Independent VT reference and 1049 entry correction

Added `nix run .#reference-test`, linked against the flake-pinned
`libvterm-neovim` 0.3.3. The production executable has no `libvterm` dynamic
library dependency (verified with `readelf`); the CPU reference exists only in
the test executable. CUDA remains the production parser/state implementation.
Luna authored the initial harness and fixtures; parent review corrected a
compilation error, wide-tail normalization, actual reference reply comparison,
unknown-fixture handling, and expanded persistent-edit fixtures. This closes
part of the independent-validation gap, not full terminal conformance.

The harness compares final cell scalars, up to three combining marks, wide/tail
structure, RGB colors, bold/underline/reverse attributes, cursor coordinates,
and reply bytes. Every fixture runs whole, bytewise, and in 7/256-byte chunks;
large ASCII/styled fixtures exceed 512 bytes to exercise bulk paths. Defaults and
palette match cudaterm. Empty cells and libvterm's sentinel/stale wide-tail pen
are normalized explicitly. Scope and exclusions are in `bench/README.md`.

Source review exposed an incorrect shared assumption in the existing engine and
its tests: 1049 entry homed the cursor, reset margins, and canceled delayed wrap.
Entry now preserves them while clearing/switching the alternate buffer and
saving main state. This follows [xterm's 1049 definition](https://www.invisible-island.net/xterm/ctlseqs/ctlseqs.html),
which specifies cursor save, buffer switch, and clearing rather than cursor
homing. Existing literal tests were corrected, and new fixtures exercise
nonzero cursor position, origin/margins, and delayed wrap at entry.

The identical reference harness was rebuilt against the saved pre-fix engine.
All three targeted entry fixtures fail on that engine and pass after the fix;
`bench/reference-alternate-1049.json` retains exact binaries, reference package,
old source, baseline Nix expression, exit codes, and diagnostic output.
The pre-fix engine writes `A` or `Z` at cell (0,0), where the reference expects
a blank. This verifies that the new comparison detects an actual prior defect.

`nix build . && nix run .#reference-test && nix run .#test &&
nix run .#vt-test && nix run .#scrollback-test && nix run .#charset-test &&
nix run .#selection-test && nix flake check` exited zero for derivation
`/nix/store/xb6bvc13kn3rpbmwmhqsgj2kspyx9i8z-cudaterm-0.1.0.drv`.
CUDA 12.9 Compute Sanitizer memcheck on the reference suite exited zero with
zero errors. No performance improvement is claimed from this compatibility fix.


## Intermediate reference checkpoints

The independent harness now compares screen cells, cursor position, and actual
reply bytes after every specified operation, rather than only the final state.
Added five multi-step fixtures: shell-line edits, margin scrolling/line edits,
saved pen/cursor, delayed wrap, and a deterministic 128-operation editing
sequence. Each runs with whole, bytewise, 7-byte, and 256-byte chunking inside
checkpoints. Original single-payload fixtures retain bulk-path coverage.
Luna reviewed the operation set; parent implemented the harness changes.

The new margin fixture exposed a reference limitation rather than a production
bug. With margins at rows 2–3 on a four-row screen, a 99-line CUD from row 1
ends at row 4 in libvterm 0.3.3 and row 3 in cudaterm. The [DEC CUD](https://vt100.net/docs/vt510-rm/CUD.html)
and [CUU](https://vt100.net/docs/vt510-rm/CUU.html) definitions support cudaterm's
existing behavior: stop at the relevant margin unless already beyond it.
`bench/reference-cursor-margin-difference.json` saves the exact test binary,
command, failing output, and source links. Dedicated literal VT tests now check
both directions starting above/below the margins. Generated differential moves
use full-screen margins, and the explicit margin fixture resets margins before
its boundary-crossing moves. This exclusion is documented, not a weakened
production behavior to satisfy the oracle.

No production code changed and no performance improvement is claimed. The
comparison still does not establish full VT conformance, intermediate behavior
inside incomplete controls, pixel correctness, or presentation latency.

`nix build . && nix run .#reference-test && nix run .#vt-test &&
nix flake check` exited zero for derivation
`/nix/store/7qq4l5krf0r0qp1gincblj7b7qk3j6wp-cudaterm-0.1.0.drv`.
The reference suite now has 22 named fixtures, including the five checkpoint
sequences. Engine code is unchanged from the preceding validated build.


## Cursor next/previous line margin correction

`CSI Pn E` (CNL) and `CSI Pn F` (CPL) now reuse the existing vertical movement
limits while resetting the column to zero. Previously their separate handlers
clipped to the whole screen whenever origin mode was off, allowing them to cross
scrolling margins that CUU/CUD respected. The shared implementation removes two
net lines and adds no state. Xterm's [CursorNextLine and CursorPrevLine](https://github.com/ThomasDickey/xterm-snapshots/blob/master/cursor.c)
likewise call CursorDown/Up followed by carriage return. Missing/zero counts
still mean one, and pending wrap is canceled through the common CSI handler.

Luna added independent reference checkpoints for full-screen movement, counts,
column reset, and subsequent writes. Parent added literal tests for every split
of omitted/zero/two-line forms, unchanged screen contents, margin/origin limits,
delayed wrap, and no scrolling at screen boundaries. Margin tests remain literal
because libvterm 0.3.3 has the previously documented clipping difference.

`nix build . && nix run .#reference-test && nix run .#vt-test &&
nix run .#csi-test && nix run .#styled-test && nix flake check` exited zero
for `/nix/store/hcb3awnb0cs6qz9whfl7hi96419n81jh-cudaterm-0.1.0.drv`.
The independent suite now contains 23 named fixtures. No new performance claim
is made; this change corrects a cursor-movement compatibility edge case.


## Current matched throughput and fixed query cost

Refreshed all five workloads against Foot 1.27.0 PGO and Monstar 1.1.0 using
current cudaterm `/nix/store/a48z1dlnfp5nbjd11gkz8xa80nw95fhb-cudaterm-0.1.0/bin/cudaterm`.
Two rounds reverse the rotated terminal order, producing 30 samples per
terminal/workload at verified 318×89. `bench/pty-current-three-terminal.json`
contains every sample, command, terminal path, GPU/driver, and geometry. The
current table near the top of this document now uses this comparison.
Cudaterm remains slower than Foot on text, ANSI, graphics, and tabs, and faster
than Monstar on all five parser-barrier workloads. Unicode medians are close,
with cudaterm lower in the aggregate. This is not overall or display parity.

Added `--payload-bytes 0` to the PTY benchmark. Timed samples then contain only
the cursor query, with the startup clearing/settling handshake outside timing.
The synthetic-PTY test now exercises both 380-byte and zero-byte payloads,
verifying raw output, empty timed payloads for zero, completed replies without
newlines, and positive recorded durations. Luna authored that test extension;
parent reviewed it and the benchmark implementation. Production code is unchanged.

Query-only comparison uses the same three executables and geometry in two
reversed-order rounds, each three launches × 20 samples after a discarded
warmup launch. Raw samples are `bench/pty-query-only-three-terminal.json`.
These characterize the fixed PTY/query/reply path, including scheduling and
any rendering triggered by query handling. They cannot be subtracted from bulk
medians to produce a parser time. History is not reset between samples in the
bulk experiment; raw PTY mode prevents ONLCR payload expansion. A matching-shaped
cursor reply is a completion barrier, not validation of the reported position.

`nix build . && nix flake check` exited zero for derivation
`/nix/store/rhsyjp53bik5j1r6yx4flrb5bv9jgdx4-cudaterm-0.1.0.drv`, including the
expanded CPU PTY test. Benchmarks ran serially and did not overlap test runs.

Query-only medians/maxima across 120 samples per terminal:

| Terminal | Median (µs) | Maximum (µs) |
| --- | ---: | ---: |
| cudaterm | 46.730 | 1505.927 |
| Foot | 11.360 | 32.200 |
| Monstar | 15.335 | 59.960 |

This exposes a fixed-cost and tail gap worth investigating alongside the bulk
results. The next targeted experiment is PTY read-size/stage tracing and a
controlled write-chunk sweep, to distinguish per-feed CUDA/reply synchronization
from host/render scheduling. Query handling currently marks the window dirty
like other nonempty feeds; its contribution needs measurement before changing
that path.


## Single-transfer reply buffer

Query-only tracing recorded 102 combined feed/reply calls with a 21.495 µs
median and four texture/swap calls with a 764.889 µs median (1508.747 µs max).
Raw trace and query samples are `bench/query-stage-baseline.csv` and
`bench/query-stage-baseline.json`. Trace flushing perturbs timing; these stage
figures guide investigation and do not prove the cause of every query outlier.

Reply storage now includes a length header followed by the existing 4096-byte
payload. CUDA reply producers keep their shared parser count and publish the
header after appending bytes; the drain reset clears both counts. The host
copies the 4100-byte buffer once, validates its length, and returns only its
valid prefix. This replaces separate length and payload transfers for nonempty
replies. Construction initializes the buffer; RIS and resize preserve pending
replies. Luna audited producers, ownership, and default-stream ordering. New
CSI tests cover saturation/truncation, draining, fresh replies, and pending
replies across RIS/resize; mouse and reference suites cover other producers.

The benchmark gained `--replies` and a `query` workload to measure both empty
and nonempty drains using the same API as the host. The old engine was rebuilt
with identical benchmark code; `bench/reply-buffer-headless-paired.json` records
exact commands/binaries and the baseline Nix expression. Two reversed-order
rounds used 5000 warmups and 30 samples per run, giving 60 samples per variant:

| Feed + reply workload | Before median (µs) | After median (µs) |
| --- | ---: | ---: |
| Text, 4096 requested bytes, empty reply | 55.930 | 56.865 |
| Text, 65536 requested bytes, empty reply | 102.100 | 102.270 |
| One cursor query, 4 bytes | 22.305 | 18.775 |
| Repeated queries, 4096 bytes, capped replies | 1204.018 | 1167.383 |

The larger copy has a measurable small cost for empty replies. Paired PTY runs
in `bench/reply-buffer-pty-paired.json` used verified 318×89 and reversed order:

| PTY workload | Before median / max (µs) | After median / max (µs) |
| --- | ---: | ---: |
| Query only, 120 samples per variant | 47.235 / 2354.507 | 41.810 / 1060.109 |
| Text, 30 samples per variant | 439.639 / 2946.396 | 434.940 / 2811.436 |
| ANSI, 30 samples per variant | 515.149 / 2743.126 | 485.609 / 2129.447 |

Query medians improved in both rounds. Text and ANSI changed direction between
rounds; their aggregate differences are not a general throughput improvement
claim. Retain the query-cost reduction with the documented empty-reply tradeoff.
The three-terminal table above identifies the preceding build; no new overall
Foot/Monstar or displayed-latency parity follows. Benchmark and sanitizer runs
were separated.

`nix build .`, `nix run .#csi-test`, `nix run .#mouse-test`,
`nix run .#reference-test`, and `nix flake check` exited zero after the engine
change. After the benchmark extension, `nix build .`, `nix flake check`, and
`nix run .#bench -- --replies --workload query --bytes 4 --warmup 5 --repeats 3`
exited zero; the smoke JSON contains three positive integer durations. Final
derivation is `/nix/store/gpz13d0pn1fhnlahdngx23dcrgynkq05-cudaterm-0.1.0.drv`.
CUDA 12.9 memcheck on its CSI and mouse suites exited zero with zero errors.


## Rejected query-only redraw suppression

Tested a conservative CUDA visual-change hint for feeds under 256 bytes, carried
back in the existing reply transfer. Query syntax/replies could leave the hint
false; ASCII, controls, invalid UTF-8, and selection clearing marked it true.
The host ORed the hint into its pending dirty flag. Larger feeds conservatively
remained dirty, avoiding hint loss across bulk/resume phases. Luna reviewed the
ordering and false-negative risks. The experimental CSI/reference/selection/mouse
suites passed, including split query and selection-removal cases.

The experiment reduced swaps in one 1000-query trace from 11 to 2, but traced
query medians varied (38.225 µs before, 47.580 µs after). Raw artifacts are
`bench/query-dirty-{before,after}.csv` and `bench/query-dirty-traced.json`.
In untraced, reversed-order paired runs at 318×89:

| PTY workload | Before median (µs) | Experimental median (µs) |
| --- | ---: | ---: |
| Query only, 120 samples per variant | 43.710 | 41.420 |
| Text, 30 samples per variant | 441.409 | 727.024 |
| ANSI, 30 samples per variant | 469.474 | 682.349 |

Both rounds showed the large bulk regression. These samples are retained in
`bench/query-dirty-pty-paired.json`. Headless 4096-byte feed/reply comparisons
(`bench/query-dirty-headless.json`) did not reproduce it: text per-round medians
were 64.935/64.800 µs before/after, then 56.730/56.705; ANSI was 98.755/105.840,
then 106.255/106.070. Compiled resource reports in
`bench/query-dirty-resources-{before,after}.txt` show no new interpreter stack or
shared-memory allocation (80/17600 bytes); register counts changed from 48 to 40.
These do not identify a causal mechanism for the PTY regression.

Separate text traces (`bench/text-dirty-{before,after}.csv` and
`bench/text-dirty-traced.json`) showed different feed partitioning: the baseline
used 11 calls including startup, while the experiment used 7, with all five
payloads delivered as 65516-byte feeds. Tracing perturbs timing, and fewer reads
alone do not imply lower latency. Host/PTY scheduling and chunk-size interactions
remain the next investigation; reducing query redraws in isolation is not an
acceptable tradeoff for the measured bulk slowdown.

**Reverted the experiment completely.** The earlier packed reply-buffer change
is retained. `bench/query-dirty-experiment.json` identifies the rejected Nix
derivation and its artifacts. After reverting, `nix build . &&
nix run .#csi-test && nix run .#reference-test && nix flake check` exited zero
and resolved back to the prior derivation
`/nix/store/gpz13d0pn1fhnlahdngx23dcrgynkq05-cudaterm-0.1.0.drv`.
No production change or new performance improvement is retained from this step.

### Application write sizes and PTY coalescing

`bench/pty_throughput.py --write-chunk N` now limits each application payload
write to N bytes (zero preserves the whole-payload behavior), with one final
DSR barrier. Each sample also records payload-write elapsed time, which includes
Python slicing, system calls, scheduling and backpressure; it is not a direct
parser or blocked-write measurement. Synthetic PTY tests check exact payloads,
query counts, zero-payload operation and timing alignment.

`bench/pty-write-chunk-sweep.json` records two reversed/rotated rounds, 30 samples
per terminal/workload/chunk, at checked 318×89 geometry. Median barrier µs:

| Workload | Write chunk | Cudaterm | Foot | Monstar |
|---|---:|---:|---:|---:|
| text | whole | 416.875 | 287.365 | 2597.661 |
| text | 4096 | 395.904 | 287.885 | 2571.366 |
| text | 256 | 541.564 | 370.640 | 2824.206 |
| ANSI | whole | 464.959 | 316.809 | 2737.946 |
| ANSI | 4096 | 443.539 | 301.234 | 2731.196 |
| ANSI | 256 | 623.464 | 426.865 | 2926.325 |

These use the retained packed-reply production binary, before the short-tail
experiment below. Small writes are not uniformly faster. Separate diagnostic
traces (`bench/pty-write-chunk-traced.json`, `bench/write-chunk-*.csv`) show that
256-byte application writes can coalesce into whole 65 KiB engine feeds, while
whole application writes can arrive in multiple reads. Tracing perturbs timing;
these traces do not establish a scheduling cause or justify a batching change.
The benchmark additions passed `nix build . && nix flake check` with derivation
`/nix/store/6dhqa10am4ic4vym5rf0n7k6lg7rxg0h-cudaterm-0.1.0.drv`.

### Skip the styled scan for a short suffix after bulk ASCII

The classifier already reports the length of the plain prefix. When that prefix
is at least 256 bytes and the rejected suffix is shorter than 256 bytes, the
engine now skips the styled-line scan, commits the prefix through the existing
plain path and interprets the suffix. This avoids scanning a whole ASCII payload
as styled text merely because it ends in a cursor-position query. The host still
uses only GPU-produced counts; it does not parse terminal bytes. A smaller
unconditional skip was rejected because long styled suffixes need the parallel
styled path. No new parser, buffer or host batching policy was added.

Independent libvterm fixtures cover a bulk prefix followed by a query, SGR and
Unicode/combining text, and prefix/suffix lengths on both sides of 256. Existing
chunking checks replay these at whole, 1-, 7- and 256-byte feed boundaries. A Luna
review checked classifier initialization, resumed parser state and fallback
ordering, and independently reviewed the benchmark additions.

The initial paired comparison (`bench/short-tail-pty-paired.json`, 30 samples
per variant/case over two reversed rounds) was mixed. Median barrier µs:

| Workload | Application write chunk | Before | After |
|---|---:|---:|---:|
| text | whole | 358.325 | 387.260 |
| text | 256 | 564.205 | 483.804 |
| ANSI | whole | 484.139 | 505.760 |
| Unicode | whole | 520.764 | 492.905 |

A larger text confirmation (`bench/short-tail-text-confirmation.json`, two
reversed rounds, five launches × ten barriers per round, 100 samples per
variant/case) improved in both rounds: whole-write medians were
390.935→334.759 µs and 389.475→338.909 µs; 256-byte-write medians were
517.074→429.794 µs and 544.055→442.429 µs. Aggregated medians were
389.475→337.119 µs (13.4% lower) and 530.920→435.880 µs (17.9% lower).
All runs checked 318×89 geometry and ran without concurrent GPU tests. Both
artifacts retain commands, executable paths and individual timings. Keep the
initial conflicting whole-write result visible: scheduling/clock variability
remains, and the initial ANSI/Unicode results do not establish a general gain.
This is PTY-to-reply timing, not presentation latency or a new three-terminal
parity comparison. The bounded optimization is retained.

`nix build . && nix flake check && nix run .#reference-test &&
nix run .#plain-test && nix run .#styled-test` exited zero with derivation
`/nix/store/lwfmc6l0jlsxl7xdbq193kibkpdim3bk-cudaterm-0.1.0.drv`.
Additional validation `nix run .#vt-test && nix run .#unicode-test &&
nix run .#scrollback-test && nix run .#csi-test` exited zero. Compute Sanitizer
memcheck on the Nix-built `cudaterm-reference-test ascii_bulk_short_tail`
reported zero errors.

### Rejected plain-scan bypass after styled parsing

The refreshed three-terminal results at the top of this file use
`bench/pty-short-tail-three-terminal.json`: two rotated/reversed rounds, 30
barriers per terminal/workload, matched 318×89 geometry, current packed-reply
and short-tail binary. They still show a Foot gap on four of five workloads.

A Luna-assisted review identified redundant plain scans after styled parsing
when the GPU classifier reports fewer than 256 plain prefix bytes. An experiment
ran the existing styled commit/history/paint sequence, then called the fallback
with only `styled_done` and returned. This bypassed two CUB scans and the plain
advance/commit/history/clear/scatter/repair launches. The condition deliberately
preserved plain acceleration for longer prefixes: styled parsing can reject a
long line while a substantial plain prefix remains usable. Added independent
reference cases for that long-line case and an early unsupported erase followed
by bulk text; those tests are retained.

The experimental build passed `nix build . && nix flake check` and
`nix run .#reference-test && nix run .#styled-test && nix run .#plain-test &&
nix run .#unicode-test && nix run .#scrollback-test && nix run .#charset-test`.
Its derivation was `/nix/store/y9v7zrydcvmf9hmwda70dypkqz9s17a4-cudaterm-0.1.0.drv`.

Headless feed/reply measurements (`bench/plain-bypass-headless-paired.json`)
used 2000 warmup feeds, 30 measured samples per case per round and two reversed
rounds. Median µs before/after:

| Workload | 4 KiB before | after | 64 KiB before | after |
|---|---:|---:|---:|---:|
| text | 59.375 | 56.715 | 102.710 | 102.770 |
| ANSI | 105.654 | 83.070 | 161.220 | 139.505 |
| Unicode | 113.180 | 92.355 | 161.135 | 145.930 |
| graphics | 135.680 | 113.220 | 207.299 | 191.850 |
| tabs | 106.120 | 91.440 | 202.265 | 178.865 |

All styled cases improved in both rounds; the 4 KiB text change was confined to
round one. However, the initial PTY comparison (two reversed rounds, 30 samples
per variant/workload, `bench/plain-bypass-pty-paired.json`) gave:

| Workload | Before µs | After µs |
|---|---:|---:|
| text | 340.925 | 300.250 |
| ANSI | 489.634 | 413.310 |
| Unicode | 347.714 | 448.440 |
| graphics | 540.244 | 465.104 |
| tabs | 488.974 | 454.584 |

A larger confirmation (`bench/plain-bypass-pty-confirmation.json`, two reversed
rounds, five launches × ten barriers per round, 100 samples per variant/case)
confirmed both ANSI's improvement (436.834→308.940 µs) and Unicode's regression
(351.724→425.909 µs). Unicode regressed in each round, 347.405→409.650 µs and
363.065→442.299 µs. All GPU benchmarks ran serially without GPU test contention.

Diagnostic traces (`bench/plain-bypass-unicode-traced.json` and the matching
before/after CSV files) showed lower median feed intervals, 189.759→172.939 µs,
but 26→27 feed calls and 4→5 swaps, including startup. Tracing perturbs timing,
and this single trace pair does not identify the regression's cause. Removing
GPU work is insufficient evidence of improved interactive throughput.

**Reverted the production bypass.** The previous short-tail optimization stays.
The reproducible Unicode PTY slowdown needs an explanation before this otherwise
promising launch reduction can be retained. Correctness fixtures, raw samples
and the current three-terminal comparison are retained.
After reverting, `nix build . && nix flake check && nix run .#reference-test`
exited zero with derivation
`/nix/store/8ah1bx7djl0bha4q50hjk118y8j6lg4g-cudaterm-0.1.0.drv`.

### Correlating child barriers with host traces

The PTY benchmark now records monotonic start/end timestamps for every sample,
with aggregate arrays aligned to barrier durations. The subtraction exactly
matches each recorded duration; synthetic PTY tests verify this and ordering.
The anchors preserve the existing payload/write/query/geometry timing scope.
`nix build . && nix flake check` exited zero with derivation
`/nix/store/8rgf316xdk1gav3jcn0pwqh1x923gyc3-cudaterm-0.1.0.drv`.
No production parser or host scheduling behavior changed in this step.

`bench/unicode-timeline-isolated.json` correlates each of 50 barriers per launch
with host trace intervals for the retained short-tail binary and rejected
plain-scan-bypass binary, in two reversed rounds. Exact executable commands,
Python clock information, sample anchors and per-sample stage overlaps are
recorded; corresponding `bench/unicode-timeline-isolated-*.csv` files retain the
original intervals. An earlier diagnostic set (`bench/unicode-timeline.json`)
ran during a CPU-only Nix build; use the isolated set for the comparisons below.
The isolated runs had no concurrent build or GPU test workload.

On this Linux setup Python perf_counter and C++ steady_clock use the monotonic
time base. Each stage is charged only its intersection with the child's sample
interval. Time outside the traced intervals remains unassigned; it includes
child writes/reads, scheduling, PTY transport and untraced host operations.
The trace records call elapsed time, not isolated GPU execution or physical
presentation. Median components cannot be added to reconstruct median totals.

The isolated traced samples had the following median barrier µs, grouped by
number of engine feeds intersecting each sample (counts in parentheses):

| Round / variant | One feed | Two feeds | Three feeds |
|---|---:|---:|---:|
| 0 retained | 341.109 (19) | 554.794 (22) | 767.709 (9) |
| 0 bypass | 278.830 (19) | 491.549 (21) | 669.544 (10) |
| 1 bypass | 326.620 (19) | 441.929 (23) | 1202.748 (8) |
| 1 retained | 352.899 (22) | 588.889 (17) | 728.679 (10) |

Round 1 retained also had one four-feed sample at 564.489 µs. Overall medians
favored the bypass in these traced runs (524.905→466.910 µs and
541.635→465.009 µs), reversing the untraced regression from the preceding step.
The differing trace overhead and longer 50-barrier launches preclude treating
this as a replacement performance verdict. The bypass remains reverted.

The timeline exposes substantial repeated feed cost for split reads, but does
not establish why the untraced Unicode ranking changed. A bounded bulk-read
coalescing experiment is now justified by observed feed fragmentation; it must
be tested against small-input latency and capture latency as well as throughput,
and must not introduce host terminal-byte parsing or indefinite render starvation.

### Deferred bulk-read coalescing experiment

The host was experimentally changed to wait for more PTY bytes only after a
read returned EAGAIN with at least 4096 bytes already accumulated. One absolute
50 µs deadline bounded all subsequent waits; the existing 65536-byte buffer
bounded the batch. Reads below 4096 bytes, EOF and hard errors did not wait.
`ppoll` used the remaining deadline after each retry; scheduler delays can exceed
the requested timeout. No terminal bytes were parsed on the CPU. A Luna audit
reviewed deadline reuse, EINTR, HUP/EOF, size bounds and latency tradeoffs.

`nix build . && nix flake check` passed for experimental derivation
`/nix/store/3358c1q7d4wl81lfppvsjad15a5nfjww-cudaterm-0.1.0.drv`.
A real-window smoke check of the Nix-built executable wrote an 8192-byte burst
and a final marker, immediately exited the child, and verified the marker in the
host's final screen dump. It passed, confirming that this fixture drained output
at EOF. This does not by itself verify batching latency or every signal case.

`bench/coalesce-pty-paired.json` retains two before/after rounds across all five
bulk workloads. These are **not a clean performance verdict**: concurrent desktop
activity was observed, with CPU processes at 620%, 296% and 111%, GPU utilization
31%, and SM clock 705 MHz at one snapshot. Two other terminal windows and other
GPU applications were also active. Those external processes were left alone.
The last baseline tabs launch exited 1 and was retried; the artifact records the
failure. A subsequent baseline query-latency launch also exited 1 before a
comparison completed. Only an accessibility-bus warning appeared on terminal
stderr, so the underlying child failure was unavailable. The capture comparison
was not reached. Do not infer an improvement or a regression from these runs.

The production host change was reverted because the throughput/latency evidence
is incomplete. `bench/coalesce-experiment.patch` and
`bench/coalesce-experiment.json` preserve the exact experiment, store executable,
parameters and validation limits for a controlled follow-up. After reverting,
`nix build . && nix flake check` exited zero and returned to derivation
`/nix/store/8rgf316xdk1gav3jcn0pwqh1x923gyc3-cudaterm-0.1.0.drv`.

The interrupted baseline runs exposed a benchmark diagnostics gap: exceptions
inside the PTY child were visible only in the terminal and disappeared when its
window closed. The child now serializes ordinary exceptions to its result file
before re-raising; the parent includes the diagnostic with the terminal exit
status/stderr and rejects the run. A synthetic PTY timeout verifies serialization,
and a parent test verifies propagation alongside an unrelated GTK-style warning.
A subsequent real-window DSR-only diagnostic run completed; the earlier launch
failure did not reproduce, so its cause remains unknown. No past failure has
been retroactively classified as a timeout or geometry change.
The diagnostic change and its CPU tests passed `nix build . && nix flake check`
with derivation `/nix/store/5y5h1m152fx41flc6gqv8vx5fjx0cbx1-cudaterm-0.1.0.drv`.

### GPU control-string cancellation and SOS suppression

Review found that the shared control-string skip state swallowed CAN/SUB, so
ordinary text and queries after a cancelled string could remain hidden. ESC X
(SOS) was also unrecognized and its payload could leak onto the screen. The GPU
byte interpreter now leaves string mode on CAN/SUB and enters the existing skip
state for SOS. This adds no host parsing, state allocation or kernel launches.
The smaller fix reuses the current streaming state rather than introducing a
separate string parser.

The literal CSI regression failed on the old engine via `nix run .#csi-test`
(`control_string_recovery: unexpected CSI result cell`, derivation
`/nix/store/w5ympr55s8ar0sydqah4wgh2mw8z6vqd-cudaterm-0.1.0.drv`). It checks
visible cells and exact DSR bytes for OSC/DCS/APC/PM/SOS cancellation, including
CAN/SUB after ESC, at every two-chunk split. It also checks ST-terminated SOS.
Luna-added independent libvterm fixtures compare direct cancellation, split
ESC cancellation, SOS termination and 400-byte hidden bodies across whole,
1-, 7- and 256-byte feeds. C++ fixture cancellation bytes use bounded octal
escapes so following A–F characters cannot extend a hexadecimal escape.

[XTerm's control-sequence documentation](https://www.invisible-island.net/xterm/ctlseqs/ctlseqs.html)
identifies ESC X as SOS. The independent libvterm 0.3.3 parser explicitly returns
to normal state on CAN/SUB before dispatching string contents; its source is
pinned by the existing Nix reference dependency. This change covers suppression
and recovery, not execution of OSC/DCS/APC/PM/SOS commands. The existing common
BEL/ST termination policy and broader string-protocol compatibility still need
separate review. No new throughput or presentation improvement is claimed.
The fixed build passed `nix build . && nix flake check && nix run .#csi-test &&
nix run .#reference-test && nix run .#styled-test && nix run .#vt-test` with
derivation `/nix/store/ld6wmy13madgpq3r6cpxppl53gsp9irx-cudaterm-0.1.0.drv`.
Compute Sanitizer memcheck on the Nix-built
`cudaterm-reference-test string_cancel_bulk_resume` reported zero errors.
The README's obsolete plain-text-comparability sentence was also replaced with
the current measured workload gaps, consistent with the retained results table.

### ANSI insert/replace mode on the GPU

Added ANSI IRM (`CSI 4 h` inserts, `CSI 4 l` replaces), as documented in
[XTerm's control sequences](https://www.invisible-island.net/xterm/ctlseqs/ctlseqs.html).
The mode is GPU-resident and defaults off; RIS clears it. Cursor saves and
alternate-screen switches do not save/restore this global mode. Positive-width
characters shift the rest of the current line right by their cell width before
being written; combining marks attach without shifting. Off-edge cells are
clipped, and the existing wide-pair repair removes orphan halves.

The implementation factors the existing ICH shift into one helper reused by IRM.
It keeps cell copies, updates and repair on the GPU. Plain-prefix, styled-line
and warp printable-run shortcuts are disabled while IRM is active because those
paths implement replacement. Insert-mode output currently uses the interpreter;
no insert-mode throughput/parity claim is made. The ordinary replacement paths
remain available when the mode is reset.

Literal VT fixtures cover insert/replace toggling, RIS reset, two-cell insertion,
clipped/split wide-pair repair and wrapping into a scroll. Independent libvterm
fixtures cover checkpointed ASCII, bulk feeds with IRM already active, mode
changes across cursor/alternate saves, intact wide-pair movement and combining
marks attached during insertion. Whole, 1-, 7- and 256-byte feeds are compared.

The independent comparison exposed a libvterm 0.3.3 difference for inserting a
wide character: its `src/state.c` calls `scroll(..., -1)` regardless of glyph
width. Inserting 中 between A and B loses B in that reference. XTerm's
[WriteText implementation](https://github.com/ThomasDickey/xterm-snapshots/blob/master/util.c)
computes `visual_width` and passes the resulting cell count to `InsertChar`.
Cudaterm retains width-sized insertion and verifies the B cell explicitly in the
literal VT fixture. `bench/reference-irm-wide-difference.json` records the exact
input and difference; this case is excluded from libvterm equivalence claims.

Final review found an ordering hazard not exposed by live-screen comparisons:
when a glyph wraps at the bottom, scrolling queues a history copy from the
recycled row. A direct insertion shift could mutate that source before the copy
runs. The glyph path now recognizes a newly cleared row and omits the unnecessary
shift there, preserving queued copy-before-clear order. A literal regression
scrolls `abcd` into history and selects it back after insert-mode wrapping.
This complements live cells and cursor checks with actual history contents.
The final implementation passed `nix build . && nix flake check &&
nix run .#vt-test && nix run .#reference-test && nix run .#unicode-test &&
nix run .#styled-test && nix run .#plain-test && nix run .#scrollback-test`
with derivation `/nix/store/j1v6adjs9aprj2xz7kvz3895rdf57p9y-cudaterm-0.1.0.drv`.
Compute Sanitizer memcheck on the final Nix-built `cudaterm-vt-test` reported
zero errors, including insert-mode wide-cell and history fixtures.

### Warp-batched ASCII insertion

Added a headless `insert` workload framing the existing text pattern with IRM
on/off controls. The requested byte count includes that eight-byte framing.
Baseline measurements (`bench/insert-warp-baseline.json`) showed that shifting
one cell at a time for every inserted character was prohibitively expensive:
median feed/reply durations at 318×89 were 88.488 ms for 4 KiB and 1434.509 ms
for 64 KiB, using 20 warmups and 20 samples each. The benchmark/test-only baseline
was built by Nix, with its exact executable and commands stored in the artifact.

The cooperative warp now inserts an ASCII run by shifting the remaining row
once for up to 32 characters, then scattering the new cells. Descending blocks
load all source cells before stores, with warp synchronization between those
steps and between blocks; overlapping moves cannot overwrite unread sources.
The shortcut requires no pending parser state or delayed wrap. If wide cells
have occurred, insertion continues through the existing interpreter/repair path.
The state remains entirely on the GPU. Cell copies preserve colors and combining
marks. The existing scatter completely initializes the inserted cells.

Tests explicitly check shifts of 1, 7, 32, 35 and 64 characters at both 80 and
512 columns, including retained cell colors. Existing tests cover wrapping,
scrollback contents, clipped wide pairs and independent libvterm checkpoints.
A Luna review checked overlap ordering, bounds, synchronization and shortcut
eligibility; the implementation does not modify rows while queued effects are
pending.

`bench/insert-warp-after.json` repeats the baseline headless protocol. Median
feed/reply µs:

| Workload | Bytes requested | Before | After |
|---|---:|---:|---:|
| insert | 4096 | 88487.695 | 1379.058 |
| insert | 65536 | 1434509.411 | 16263.401 |
| text | 4096 | 58.270 | 57.285 |
| text | 65536 | 104.335 | 103.980 |

The reverse-order 4 KiB confirmation (`bench/insert-warp-confirmation.json`,
30 samples per case, 20 warmups for insert and 2000 for text) measured
86153.493→2959.341 µs for insertion and 56.850→56.695 µs for ordinary text.
Insertion remained about 29× faster in the confirmation, though its absolute
after time varied substantially. These are headless timings on the shared
desktop GPU, not an isolated machine or a Foot/Monstar comparison. All benchmark
runs were serial, without concurrent agent GPU tests or builds. They establish
a large improvement in this ASCII insertion workload, not general insert-mode
performance, PTY throughput or presentation parity. The optimization is retained.

`nix build . && nix flake check && nix run .#vt-test &&
nix run .#reference-test && nix run .#unicode-test && nix run .#scrollback-test`
exited zero for derivation
`/nix/store/nkglb6qfwy955frkkxp28m2nfpzh99i4-cudaterm-0.1.0.drv`.
Compute Sanitizer memcheck and synccheck on the Nix-built `cudaterm-vt-test`
both reported zero errors, including the cross-warp insertion fixtures.

### Rejected short-feed CUDA graph

A graph experiment combined a fixed 256-byte pinned-input copy, the existing
interpreter kernel and a complete reply-buffer copy into one submission for
nonempty `feed_and_replies` inputs shorter than 256 bytes. Actual input length
remained a kernel argument; the CPU did not inspect terminal syntax. A later
variant cached that length to avoid redundant kernel-node parameter updates.
Graph launch and completion used the existing default stream, preserving history
preparation, selection clearing and reply resets. New graph ownership was assigned
only after successful initialization/execution, and pinned memory was released
with the graph before engine device allocations.

Luna-assisted tests compare mixed `feed`, `feed_and_replies` and `take_replies`
against the existing synchronous path. They check lengths 1/4/7/63/255 including
255→1 changes, 256-byte fallback, partial CSI, queued replies, empty drains,
selection clearing, resize and mouse reports. These tests are retained as
`short_feed_replies_consistency`. The initial graph passed
`nix build . && nix flake check && nix run .#csi-test && nix run .#mouse-test &&
nix run .#reference-test` (derivation
`/nix/store/s033jqz2ilz1pxrya33v86ci3bzdmsfc-cudaterm-0.1.0.drv`). The cached
variant passed `nix build . && nix flake check && nix run .#csi-test`
(`/nix/store/l58mn9qivfab7phf26wlbj5943a38i3n-cudaterm-0.1.0.drv`).

`bench/small-graph-baseline.json` records the pre-experiment sample. Two reversed
headless rounds in `bench/small-graph-headless-paired.json` and
`bench/small-graph-cached-headless-paired.json` used 2000 warmups and 50 samples
per variant/case. Cached-graph query medians improved 39.500→27.915 µs in round
zero and 18.760→16.035 µs in round one. Short text/ANSI also improved, while the
4096-byte control changed direction between rounds. The large absolute variation
precludes treating one percentage as a stable gain.

The first windowed comparison (`bench/small-graph-pty-paired.json`) did not show
query improvement and had worse Unicode medians. The cached variant's larger
comparison (`bench/small-graph-cached-pty-paired.json`) used two reversed rounds,
five launches per variant/case, 20 query barriers or 10 Unicode barriers per
launch (200 query/100 Unicode samples per variant total), checked at 318×89:

| Round / workload | Before µs | Cached graph µs |
|---|---:|---:|
| 0 query only | 44.150 | 43.490 |
| 1 query only | 44.260 | 44.895 |
| 0 Unicode 64 KiB | 535.110 | 541.129 |
| 1 Unicode 64 KiB | 466.039 | 375.110 |

Query changes were under 1 µs and reversed direction. The headless gain did not
establish a repeatable windowed benefit. Benchmarks ran serially without agent
GPU tests/builds, but on the shared desktop rather than an isolated machine.
These results neither prove a general graph advantage nor a causal Unicode
regression. The graph is **reverted** in favor of the simpler retained path.
`bench/small-graph-experiment.patch` and `.json` preserve the implementation and
exact derivations. This leaves the earlier ASCII insertion batching intact.
After reverting the graph and retaining the API regressions,
`nix build . && nix flake check && nix run .#csi-test` exited zero with derivation
`/nix/store/snkw02724kzvlszsq9j1596f71h0b921-cudaterm-0.1.0.drv`.

### Avoid unnecessary input synchronization

Printable key events previously copied the CUDA terminal state even though only
encoded special keys use application-cursor mode. The snapshot now occurs only
for those keys. Paste reads bracketed-paste mode once for its matching delimiters.
`follow_output` also returns immediately when neither viewport navigation nor
selection could require a change. A conservative host flag records viewport
navigation; output/reset/resize may leave it true unnecessarily, but cannot
create a positive view offset from zero. Selection retains its existing separate
flag. Terminal parsing and state remain on CUDA. Always launching the reset
kernel would avoid this flag but preserve a redundant synchronization for every
ordinary character.

The Luna-assisted keyboard fixture checks exact PTY bytes from window-targeted
synthetic X11 events. `bench/keyboard-baseline.json` records three pre-change
512-character launches. `bench/keyboard-input-sync-paired.json` records two
reversed rounds, three fresh launches per variant and count in each round:

| Round / characters | Before median ms | After median ms |
|---|---:|---:|
| 0 / 1 | 2.351 | 2.097 |
| 1 / 1 | 2.405 | 2.166 |
| 0 / 512 | 33.434 | 32.725 |
| 1 / 512 | 35.905 | 33.437 |

All 24 launches received the expected bytes. These modest improvements include
xdotool startup/event delivery, a timestamp-file write, scheduling and PTY reads;
the injection tool dominates burst timing. The small sample and shared desktop
do not establish physical input latency or competitor parity. The change is
retained for avoiding unnecessary work with these observed results.

`nix build . && nix flake check && nix run .#scrollback-test &&
nix run .#selection-test && nix run .#csi-test` exited zero for derivation
`/nix/store/iqmd9k9mwcbb2jbwpa1q5pixqp5lyaxw-cudaterm-0.1.0.drv`
(output `/nix/store/dk8rawn2cmm20llzyfdn80amvnx0vnjh-cudaterm-0.1.0`).
The new scrollback regression covers following after navigation, resize,
selection, appended output and repeated no-op calls. Manual
`tests/window_selection.py --rapid --history` and
`tests/window_selection.py --rapid --curses --mouse`, using the recorded Nix
xdotool path, both passed clipboard roundtrips on this binary. The latter also
checks Shift-selection while application mouse tracking is enabled.

### Rejected classifier-initialization kernel

Bulk feeds initialize the GPU classifier's rejected-prefix count with a four-byte
H2D copy, including after bounded parser resumption. An experiment replaced each
copy with a single-thread CUDA kernel on the same default stream. Luna review
found the ordering, allocation lifetime and error handling preserved; no parser
logic changed. The experiment passed `nix build . && nix flake check &&
nix run .#plain-test && nix run .#styled-test && nix run .#reference-test &&
nix run .#csi-test` with derivation
`/nix/store/g6q7fv5fby0rwcb41nfgm8gv6gx90636-cudaterm-0.1.0.drv`.

`bench/prefix-init-pty-paired.json` records two reversed rounds, three measured
launches with ten barriers each per variant/workload, at 318×89. Medians in µs:

| Workload | Round 0 before → experiment | Round 1 before → experiment |
|---|---:|---:|
| Text | 417.639 → 388.925 | 330.990 → 363.379 |
| ANSI | 502.624 → 582.169 | 459.500 → 531.090 |
| Unicode | 525.480 → 516.259 | 826.279 → 600.564 |
| Graphics | 453.439 → 625.079 | 582.755 → 603.725 |
| Tabs | 652.489 → 724.579 | 526.465 → 841.799 |

ANSI, graphics and tabs regressed in both rounds; text reversed direction.
Shared-desktop variation is substantial, and these results do not isolate a
cause. Serial headless feed/reply measurements with 2000 warmups and 40 samples
(`prefix-init-baseline.json`, `prefix-init-after.json`) were mostly similar:
64 KiB text 102.745→104.910 µs, ANSI 161.435→156.210 µs and Unicode
169.095→156.855 µs. No builds or agent GPU tests overlapped measurements.
There is no reliable windowed benefit, so the experiment is **reverted**.
`bench/prefix-init-experiment.patch` and `.json` preserve the code and exact
binaries. The earlier input synchronization improvement remains intact.

### Rejected classifier warp reductions

A Luna implementation reduced invalid-byte positions within each 32-thread warp
before updating the global rejected-prefix counter. It preserved the negative
parser-state sentinel, zero mode sentinel and earliest invalid position. Tail
lanes participated with the input length as sentinel. The first variant used
five shuffle/min steps; a second used the native `__reduce_min_sync` instruction
on the existing sm_89 target. Both are **reverted** after windowed measurement.

The shuffle variant passed `nix build . && nix flake check &&
nix run .#plain-test && nix run .#styled-test && nix run .#reference-test &&
nix run .#csi-test` (derivation
`/nix/store/8izsdwm28dwh4v39rwhgp3m97pvs7d94-cudaterm-0.1.0.drv`). The native
variant passed the same commands through `reference-test`
(`/nix/store/rz8f6w1qxszi7qn1kisnfdmwf4qq0l0x-cudaterm-0.1.0.drv`).

`bench/classify-warp-pty-paired.json` contains two reversed rounds with 30
barriers per variant/workload/round. Text slowed in both rounds; initial gains
in ANSI, graphics and tabs reversed. The larger native comparison,
`bench/classify-warp-native-pty-paired.json`, used five launches with twenty
barriers each per variant/workload/round (200 samples per variant/workload):

| Workload | Round 0 before → native µs | Round 1 before → native µs |
|---|---:|---:|
| Text | 344.074 → 358.400 | 370.834 → 369.565 |
| ANSI | 496.959 → 510.224 | 575.454 → 506.879 |
| Unicode | 406.585 → 472.464 | 536.120 → 545.479 |
| Graphics | 575.884 → 469.365 | 600.659 → 476.319 |
| Tabs | 556.489 → 668.979 | 556.385 → 556.069 |

Graphics improved, but Unicode regressed in both rounds and other results were
mixed. Shared-desktop variation remains substantial; no causal claim follows
from these medians. Measurements were serial without concurrent GPU tests or
builds, with checked 318×89 geometry. The changes do not establish a broad
throughput improvement. Raw pre-change headless samples, both experimental
patches and exact binaries are preserved under `bench/classify-warp-*`.

The new `plain-test` classifier boundary cases remain useful independently:
257/513-byte inputs with tabs at offsets 0, 31, 32, 255, 256 and the final byte,
plus pending CSI, insert mode, disabled autowrap and partial margins. Each
compares cells, cursor and replies with bytewise parsing before and after a
continuation. A next experiment can target the two scans and advance-count
kernel together for bounded small inputs, leaving history and painting intact;
that has not yet been implemented or measured.

### Bounded scan fusion

A Luna-assisted implementation combines the two plain-input scans and advance
calculation into one kernel for inputs up to 4096 bytes. A 256-thread block uses
CUB BlockScan with sixteen contiguous items per thread: inclusive maximum for
line starts, the existing newline/wrap advance calculation, then inclusive sum
for advances. Padded items contribute zero. A block barrier separates uses of
shared scan storage. Classification, parser resumption, styled processing,
history, screen updates and repair retain their existing ordering and code;
larger inputs use the original scans. This removes two kernel launches on the
bounded path. Keeping the original path everywhere would avoid approximately
forty lines of kernel code but retain those launches.

The change is retained provisionally, with mixed performance evidence rather
than a claim of universal improvement. `bench/block-scan-pty-paired.json` and
`bench/block-scan-small-pty-paired.json` each record two reversed rounds, five
launches and twenty barriers per variant/workload/round at 318×89. Pooled raw
sample medians (200 per variant/workload) are:

| Workload | 4096-byte before → after µs | 65536-byte before → after µs |
|---|---:|---:|
| Text | 106.025 → 104.480 | 344.049 → 350.844 |
| ANSI | 149.825 → 151.925 | 534.355 → 475.449 |
| Unicode | 167.325 → 163.670 | 549.109 → 457.920 |
| Graphics | 186.679 → 179.500 | 567.169 → 525.574 |
| Tabs | 159.170 → 154.524 | 591.464 → 566.894 |

Several round medians reversed direction: small text 107.209→99.080 then
105.140→107.810 µs; small ANSI 148.380→142.160 then 150.615→155.080 µs;
large text 392.694→354.790 then 315.965→346.150 µs. Small graphics and tabs,
and large Unicode and graphics, improved in both rounds. Pooled medians do not
remove this variation, and the samples within each launch are correlated.
Shared-desktop load was not isolated; GPU tests/builds did not overlap benchmarks.
The data supports a limited optimization candidate, not Foot parity or a stable
percentage speedup. In particular, pooled small ANSI and large text were slower.

Headless feed/reply measurements with 2000 warmups and forty samples are retained
in `bench/block-scan-baseline.json` and `bench/block-scan-after.json`. At 4096
requested bytes, ANSI/Unicode/graphics/tabs fell roughly 5–6 µs while text rose
64.580→66.930 µs. The 65536-byte control remained on the original scan path;
its medians also varied. Exact executable paths and commands are in each file.

`nix build . && nix flake check && nix run .#plain-test &&
nix run .#styled-test && nix run .#reference-test &&
nix run .#scrollback-test && nix run .#workspace-test` exited zero for derivation
`/nix/store/hc2lx65rqjs6kvb9pk4nyamlxarpn70w-cudaterm-0.1.0.drv`
(output `/nix/store/zf0x89viaqc849jzc3bf2hxlyhcr8641-cudaterm-0.1.0`).
New plain-test cases compare 4095/4096/4097-byte inputs against bytewise parsing,
using CRLF at 16/17-byte intervals, inherited colors with pending wrap, nonzero
cursor position, late tab rejection and a subsequent cursor query. Existing
tests also exercise styled prefixes, history scrolling and parser resumption.
Compute Sanitizer memcheck and synccheck on the Nix-built `cudaterm-plain-test`,
filtered with `--kernel-name kns=plain_scan_small --error-exitcode 99`, both
exited zero and reported zero errors. These checks cover the new kernel, not
every kernel in the terminal.

### Refreshed competitor comparison and geometry validation

The matched-grid table above now uses the current scan-fusion binary and 200
samples per terminal/workload. The largest repeatable Foot gap is ANSI:
cudaterm round medians 411.535/382.635 µs versus Foot 285.039/272.520 µs.
Text also trails in both rounds. Graphics and tabs change ranking between
rounds; their pooled medians should not be treated as stable wins or losses.
The comparison establishes remaining PTY/parser gaps, not display or resource
parity. Raw data is `bench/pty-block-scan-three-terminal.json`.

A Luna-assisted audit and regression exposed a benchmark validation gap: the
parent checked the expected grid only against a launch's final dimensions.
It now checks every sample's dimensions as well. The regression simulates early
stable 80×24 samples followed by a final 318×89 grid and requires rejection
when 318×89 is requested. Benchmark code stayed frozen throughout the comparison;
all captured sample geometries were independently checked before making this fix.
`nix build . && nix flake check` exited zero with the new CPU regression for
derivation `/nix/store/c6gzm65996byyi1cr0dc5fx4fxllmra4-cudaterm-0.1.0.drv`.
Terminal implementation code did not change in this step.

### Styled initialization in the classifier

The classifier now initializes the styled eligibility limit alongside the
styled consumed count it already reset. This removes the separate `styled_init`
kernel and one launch for each styled candidate. No state changes occur between
the final classifier and the old initialization site; the bounded parser-resume
path runs the classifier again and therefore recomputes eligibility from the
updated state. Luna reviewed and implemented this change. The eligibility
predicate and styled parser are unchanged.

The simplification is retained, but **no stable ANSI PTY speedup is established**.
`bench/styled-init-pty-paired.json` records two reversed rounds, five launches
with twenty barriers each per variant/workload/round, one-second settling and
checked 318×89 geometry. Median barrier times in µs:

| Workload | Round 0 before → after | Round 1 before → after |
|---|---:|---:|
| Text | 320.360 → 339.130 | 346.359 → 329.145 |
| ANSI | 319.265 → 320.455 | 455.074 → 470.910 |
| Unicode | 479.570 → 463.095 | 448.139 → 511.489 |
| Graphics | 519.375 → 431.165 | 508.719 → 496.929 |
| Tabs | 649.284 → 495.530 | 522.704 → 499.640 |

Graphics and tabs improved in both rounds; ANSI was slightly slower in both,
while text and Unicode reversed. Shared-desktop variation remains large and
these results do not establish causation. No builds or GPU tests overlapped
measurement. `styled-init-baseline.json` and `styled-init-after.json` contain
headless feed/reply samples (2000 warmups, forty samples): 64 KiB ANSI
161.9995→160.890 µs, with mixed changes in the other cases. The removed launch
is established by code; broad throughput improvement is not.

`nix build . && nix flake check && nix run .#styled-test &&
nix run .#plain-test && nix run .#reference-test && nix run .#csi-test &&
nix run .#scrollback-test` exited zero for derivation
`/nix/store/0whfqw28dns6al0fq2l804nwqq692cy3-cudaterm-0.1.0.drv`.
`bench/styled-init-validation.json` records exact binaries and benchmark hash.
Existing tests cover partial CSI/UTF-8/OSC resumption, margins, autowrap, insert
mode and scrolling. The current three-terminal table predates this change.

Code review identified the next bounded experiment: styled-line processing
copies SGR parameters into a second pen and applies the sequence twice, although
only the second pen's flags are used. A shared SGR application with a second
flags word could avoid the extra parameter object and repeated color decoding.
This remains unimplemented and unmeasured; indexed/RGB parameter skipping must
stay in the single parser loop so color components are not treated as attributes.

### Single-pass SGR flag transformation

Styled-line processing now applies each SGR parameter sequence once. The shared
SGR routine accepts a second flags reference; attribute operations update both
words while colors and color-parameter skipping are processed once. Ordinary
parser/paint callers pass their own flags as that reference, preserving the
idempotent set/clear operations. The styled path starts its second word at 15,
replacing the former second pen, copied parameter array and duplicate SGR call.
Luna implemented and reviewed this change.

The compiler resource report (`bench/sgr-shadow-resources.json`) shows
`styled_lines` stack use falling from 160 to 80 bytes and registers from 29 to 26.
`feed_kernel` remains at 46 registers/80 stack bytes and `styled_paint` at
31 registers/80 stack bytes. These are compiler resource counts, not a measured
reduction in total process GPU memory. The change is retained for removing
duplicate work and reducing that footprint; a consistent ANSI speedup is not
established.

Desktop benchmarking was stopped at the user's request because repeated terminal
windows prevented compositor use. **Further work remains headless unless the
user authorizes desktop benchmarking again.** No VM was created. The incomplete
`bench/sgr-shadow-pty-paired.json` is excluded from completed comparisons; its
status is recorded in `bench/sgr-shadow-pty-interruption.json`.

The subsequent `bench/sgr-shadow-headless-paired.json` contains two reversed
rounds, 2000 warmups and fifty samples per variant/workload/size. ANSI feed/reply
medians in µs were:

| Requested bytes | Round 0 before → after | Round 1 before → after |
|---|---:|---:|
| 4096 | 92.285 → 99.395 | 98.670 → 93.110 |
| 65536 | 160.310 → 159.210 | 159.410 → 159.415 |

The 4 KiB result reversed and 64 KiB was nearly unchanged. Other workloads also
varied; small Unicode was slower in both rounds. These headless wall-clock
measurements ran serially, without simultaneous builds or GPU tests, but still
share the desktop GPU. They do not prove PTY or display performance parity.

`nix build . && nix flake check && nix run .#styled-test &&
nix run .#csi-test && nix run .#reference-test && nix run .#vt-test` exited zero
for derivation `/nix/store/gydpz22wi48l3fnca1m4fsq6v37ix70w-cudaterm-0.1.0.drv`
(output `/nix/store/0mymmqy7bn9h84hnzhx27h79354bxil3-cudaterm-0.1.0`).
New literal tests check all supported flag bits, selective resets, inherited
line attributes and indexed/RGB components equal to attribute command numbers,
using whole, one-byte and seven-byte feeds. Compute Sanitizer memcheck on this
Nix-built `cudaterm-styled-test --bulk-only`, filtered to
`--kernel-name kns=styled_lines --error-exitcode 99`, exited zero with zero errors.
