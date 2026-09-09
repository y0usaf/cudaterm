# Full objective remaining evidence matrix — 2026-09-06

Current mark-storage candidate: `bench/mark-pool-v4-checkpoint.json` records
production integration of immutable suffix marks with exact four/16/256-mark
copy/search/prompt/reflow coverage and private clipboard validation. Cell remains
32 bytes; arena capacity is 8 MiB with explicit all-live exhaustion. Current
Nix/core/graphics/private-window/Ekko/Finix checks and the frozen ordinary-feed
regression screen pass. The historical 80-column literal-search p90 gate remains
unmet and its cause is unresolved under variable control timings. The full-arena
serial pause, 78 MB PSS target, ZWJ geometry/shaping and broader original goals
remain open. See `docs/progress.md` for raw evidence and limits.

Pre-integration longer-grapheme evidence: `bench/zwj-investigation-checkpoint.json` records
126 private cursor observations and seven derived engine copy/search/reflow cases.
Six tested ZWJ strings retain exact text despite incorrect width. A four-combining-
mark sequence demonstrably loses U+0323 and fails exact search, before and after
resize. That pre-integration failure is fixed by the current mark-pool candidate; ZWJ width remains unresolved. A finite
RGI trie prototype is not sufficient to solve arbitrary-mark storage or shaping;
these remain explicit implementation requirements, with original resource gates.

Current skin-tone increment: Unicode 17 eligible base+optional VS16+modifier
sequences use one wide cell, with byte-split, exact-copy/search, margin, insertion
and reflow coverage. V2 Nix build/Unicode/search/reflow checks and 31 frozen
private-compositor cursor expectations pass; see `docs/progress.md` and
`bench/skin-tone-v2-feature-parent-evaluation.json`. This supersedes historical
skin-tone cursor failures below for these tested cases. It does not establish
shaping, arbitrary grapheme storage, ZWJ support or full Unicode parity. All 11 final integration commands and the unchanged paired cost screen passed;
`bench/skin-tone-v2-checkpoint.json` captures the retained binary and evidence.
Original competitive performance gates remain open; current private-window PSS
is 81.862–82.006 MB, above 78 MB. Timing variation prevents speedup attribution.

Latest layout increment: candidate German Decimal/Separator bytes pass 544
mode/modifier cases; all 884 prior US mappings remain unchanged. Held-key delivery
and the following ordinary character pass 72 cases in each layout. Core evidence
is `bench/keypad-layout-evaluation.json` and `bench/keypad-repeat-{us,de}-evaluation.json`;
all eight final integration commands passed, including private Ekko and Nix/Finix
checks (`bench/keypad-layout-checkpoint.json`). IME, other layouts,
extended protocols and six pre-existing numeric Ctrl+Alt operator differences
remain open. This supersedes the prior US-only/repeat-untested scope below for
the specific measured keys; original performance targets remain unchanged.

## Latest keypad checkpoint

`bench/keypad-validation.json` records passing Nix build/native input tests, VT
and repeated private keyboard fixtures; `bench/keypad-evaluation.json` passes the
frozen mode/navigation/application byte gates (408 basic cases against both
references, 299 modified cases against a nonempty reference). All 13 broader integration commands passed after access recovery, including
private sync/search, 38 graphics cases, Ekko, Nix checks and Finix preview/evaluation
(`bench/keypad-recovery-integration-20260906-070947/manifest.json`). Original
performance targets remain unchanged; fresh large-window PSS is 80.68–80.99 MB.

Open input work includes numeric Ctrl+Alt operator policy (six cases match neither
reference), two application cases with no reference bytes, non-US layouts, repeat
and IME interaction, remapping and extended keyboard protocols. The comparator
scope must not be promoted to full keyboard parity. Historical tables below retain
their explicitly named checkpoint evidence; [progress](progress.md) tracks later
selection, lifecycle and input increments.

This is a current audit of the full objective in [acceptance.md](acceptance.md).
“Partial” means that a narrower test exists; it is not a parity claim. Historical
artifacts are identified as historical where their executable is not the current
checkout. No row is promoted to complete from source inspection alone.

| Requirement | Current authoritative evidence | Missing proof | Next action |
| --- | --- | --- | --- |
| Reproducible build and correctness | `bench/reclaim-retained.json` records the retained current executable hash; `bench/reclaim-retained-build.log`, `bench/reclaim-retained-flake-check.log`, and `docs/progress.md` record passing `nix build` and `nix flake check`. CUDA unit suites are listed in the same progress record. | A final release checkpoint still needs the complete current command set captured together after remaining changes. | Run and archive one final Nix build, flake check, and all test targets against the release executable.
| Shell, command execution, PTY resize and cleanup | `bench/word-wrap-functional.json` records private-window sync, search, resize, and child lifecycle passing; `tests/test_window_cleanup.py` passes natively and is wired into Nix. `src/main.cu` owns PTY/pidfd cleanup. | Interactive behavior across long sessions and cleanup with varied descendant/process-group cases is not a soak. | Run a repeated shell/editor/child lifecycle matrix, retaining exit status, descendant cleanup and descriptor results.
| CUDA streaming VT parser/state | `tests/{plain,styled,vt,csi,reference,unicode}_test.cu`, `bench/vt-status-validation.json`, and the current sync logs cover split feeds, cursor/erase/scroll/margins, SGR, alternate screen, UTF-8, queries and normal CSI 5 n (`ESC[0n`). | Full VT compatibility, broad query/error coverage and application corpus coverage remain incomplete; CSI 5 n is a narrow increment. | Re-run the current binary's five workload corpus with split boundaries and add missing query/VT cases before any compatibility claim.
| CUDA rasterization and displayed output | `tests/unicode_test.cu`, `tests/test_graphics.py`, `bench/word-wrap-functional.json`, and `bench/vt-status-ekko.log`/`bench/vt-status-sync.log` provide CUDA glyph/graphics and private Weston checks. | Same-machine comparator glyph/color/cursor/resize/Unicode/scrollback output has not been captured; sustained animated/shared-image/scaling workflows are not covered by the current graphics protocol assertions. | Build a matched visual atlas and graphics workflow matrix with exact font, geometry, GPU and compositor metadata.
| Font quality, Unicode widths, graphemes and emoji | `tests/test_font.py`, `tests/test_widths.py`, `tests/unicode_test.cu`, and `src/engine.cu` scalar width/combining logic cover literal widths and bitmaps. `docs/feature-evidence.md` explicitly limits this to scalar behavior. | The 99-sample private-compositor comparison in bench/grapheme-summary.json now proves cursor-width differences for VS16, skin-tone, ZWJ and keycap sequences. Cluster storage/copy fidelity, shaping, fallback and broad coverage remain incomplete. | Exercise representative Unicode/TUI corpus and document unsupported shaping/fallback; fix only a demonstrated failure.
| Keyboard and paste input | `tests/window_keyboard.py`, `tests/input_test.cpp`, `tests/test_nvim.py`, and `src/input.hpp` cover key sequences, UTF-8 character input, PTY backpressure and Neovim editing. The current sync fixture also passes Ctrl-Space input during a large compressed frame, with a recorded sub-50-ms response. | Keyboard layout/modifier coverage, physical/input-to-display latency, desktop paste integration and full workflow responsiveness over sustained compressed frames are missing. | Run private Wayland/X11 keyboard and clipboard cases under a fixed layout, recording bytes and latency; retain the existing large-frame case as transport evidence.
| Selection and clipboard | `bench/offviewport-checkpoint.json`, `bench/offviewport-clipboard-acceptance.json` and `tests/selection_test.cu` cover retained-history Word/Line expansion, exact private ASCII clipboard bytes, Unicode copy, alternate isolation and bounded copy scratch. | Unicode segmentation/graphemes, drag/autoscroll and desktop clipboard backends remain incomplete; the comparator fixtures cover two ASCII layouts only. | Extend the private exact-byte fixture to Unicode and drag/autoscroll. Preserve the observed difference: Monstar includes the offscreen line prefix on triple-click, while Foot copies the visible suffix plus newline in this fixture. |
| Scrollback navigation and long history | `tests/scrollback_test.cu`, `tests/reflow_test.cu`, `bench/reflow-retention-validation.json`, and current sync/search artifacts cover ring eviction, scroll view, selection, history reflow and resize. | No matched comparator memory/latency soak; no current-binary long-running workload with peak and post-workload retention across repeated navigation. The checked-in reflow lifecycle measurements are incremental/historical evidence. | Run a 10k+ line plain/ANSI/Unicode history soak at both grids, with repeated scroll/search/resize and RSS/PSS/private/device snapshots.
| History search | `tests/search_test.cu`, `tests/window_search.py`, `bench/word-wrap-functional.json`, and `docs/feature-evidence.md` prove current cudaterm search interaction, UTF-8 copy, forward/backward navigation, no-match editing, viewport restore and exact wrapped-copy behavior. The feature ledger records Monstar ASCII history-search and wrapped-copy runtime success; Foot copy remains unresolved. | Unicode normalization, search latency, resize behavior, and comparator Unicode/runtime coverage remain absent. | Extend the existing Unicode/navigation/no-match fixture with normalization, resize and latency cases, then run matching documented bindings on Foot/Monstar where injectable.
| Resizing and reflow | `tests/reflow_test.cu`, `tests/scrollback_test.cu`, and `bench/reflow-fast-cost-validation.json` cover CUDA/history reflow and incremental cost gates. `bench/reflow-fast-lifecycle.json` is historical/incremental lifecycle evidence rather than a current-binary acceptance run. | Display latency, instantaneous peaks, and matched comparator resize/reflow costs remain unmeasured. | Add synchronized resize timing with frame submission/compositor observation and matched comparator runs.
| Graphics workflows | Current `src/graphics.cuh` supports raw/compressed upload plus crop/place/delete; `tests/test_graphics.py`, `tests/test_ekko.py`, `bench/ekko-validation.json`, and `docs/ekko.md` exercise that supported subset and browser integration. | Sustained animation, repeated upload/delete churn, scaling workflows, and comparator graphics resource/presentation behavior are missing from the current assertions. | Run upload/delete/resize/animation lifecycle soaks, recording peak/post-workload host and GPU memory plus frame presentation separately.
| Idle CPU and wakeups | `bench/reclaim-baseline.json` is the current accepted bhsg baseline and records context-switch medians 1354/831 for 80×24/318×89; `bench/idle-event-controlled.json` is an earlier hws checkpoint with 338/339 and settled own waits. Fixed PSS gates still fail. | Longer idle, wakeup counts for all threads, multiwindow idle, and explanation of remaining driver activity are absent. | Repeat settled traces for one and multiple windows at both grids, then pair wakeup attribution with resource samples.
| Allocation churn and retained memory | `bench/pss-maps-summary.json`, `bench/reclaim-evaluation.json`, and `bench/reclaim-baseline.json` provide smaps and controlled candidate gates; scoped `malloc_trim` was rejected and removed. | Same-workload churn distributions, peak-after-output, repeated resize/scrollback/graphics retention, and multiwindow accumulation remain unmeasured. | Make a matched workload/soak matrix with allocation counts, peak and post-idle RSS/PSS/private/device memory; preserve null GPU comparator observations.
| Startup and first usable frame | `bench/reclaim-startup-valid-1.stdout` through `-3.stdout` use the current accepted bhsg executable and record launch timing through first GL texture-swap (roughly 90–93 ms in the associated profiles). | A stable current launch-to-ready/window-visible distribution and compositor-observed presentation timestamp are not established; first GL swap is not physical visibility. | Add explicit start, child-ready, first-submit, first-swap and compositor-observed timestamps for all three binaries.
| Small/large and multiple windows | `bench/current-pty-matrix.json` covers all five PTY workloads at 80×24 and 318×89 on the current vjw4 checkpoint, with stable recorded geometry. Earlier idle resource matrices remain checkpoint-specific. | Simultaneous-window resource/performance and multiwindow lifecycle/churn are unknown; a new current full-window idle/retention comparison is needed. | Run one/three/repeated-window resource cases with per-process plus compositor accounting, preserving desktop isolation. |
| Foot/Monstar parity workloads | `bench/current-pty-matrix.json` and `bench/current-pty-summary.json` provide 900 current vjw4/Foot/Monstar barriers for all five workloads at both grids in reversed rounds. `docs/current-pty-comparison.md` separates current matched and fixed historical gates. | Small-grid tails/tabs and four large-grid historical workload gates remain unmet. These are parser replies; image upload, presentation and physical display comparisons remain absent. | Investigate query-triggered redraw and repeat the unchanged gates after a validated fix; add image and presentation workloads separately. |
| Display latency vs parser barriers | Baseline explicitly labels cursor replies as PTY/parser barriers; `docs/baseline-audit.md` retains only historical compositor capture proxies. | Frame submission, compositor observation, scanout and physical input-to-photon latency are not measured together. | Instrument submit and compositor observation separately; use a dedicated hardware/display method for physical latency.
| Configuration and daily-driver usability | `src/config.hpp` parses only theme colors; CLI options are in `src/main.cu`. `bench/private-idle-controlled.json` controls XDG/fontconfig for comparator provenance; Neovim and Ekko/browser integrations pass their recorded checks. | Effective user configuration, key remapping, font fallback/HiDPI, desktop clipboard, multiplexer/remote-shell and extended uninterrupted use remain incomplete. | Define the supported configuration surface and run a documented daily-driver session/corpus, recording every failure before changing behavior.

## Current experimental checkpoint and next actions

The provisional coalescing candidate is 055j2; vjw4 remains its retained before
checkpoint. `bench/coalesce-final-validation.json` records current build/Finix
identity and `bench/coalesce-checks.json` records sync/search/Ekko validation.
Older table entries above remain checkpoint-specific historical evidence.

The private persistent capture observer now pairs parser replies with
framebuffer-capture completion and color validation at both grids. The candidate
improves loaded-marker medians from approximately 28 ms to 11 ms, but these
are capture-paced upper bounds, not first presentation or physical display
latency. `bench/coalesce-visible-evaluation.json` retains unmet frozen limits.
Separate 900-barrier current/before matrices and a 720-barrier tabs follow-up
leave target misses and unexplained timing variability; the paired trace/telemetry follow-up now locates most slow-round time in
feed spans correlated with high aggregate utilization/lower SM clocks
(`bench/coalesce-tabs-telemetry-summary.json`). Workload ownership and causality
remain unknown. Do not discard slow rounds; preserve timing acceptance as open.

Current short idle attribution/mapping samples are in
`bench/coalesce-idle-summary.json`: main-thread tick/switch deltas and redraws
are zero at sampled resolution, other-thread activity remains, and candidate
PSS is approximately 82.18 MB, above the fixed 78 MB target. Full window memory
retention, simultaneous-window costs, long lifecycle/soak tests and exact
comparator selection behavior remain open independently of timing uncertainty.

Current-checkpoint lifecycle supplement: `bench/vs16-retained-lifecycle.json`
now supplies 15 successful engine-host cycles across three vjw4 processes, with
history fill, resize, graphics pixel checks/delete and reset. Final tracked
device allocation and sampled post-cycle PSS/private memory were stable. This
updates engine lifecycle evidence only; full windows, instantaneous peaks and
matched comparator lifecycle/retention remain outstanding.

Multiwindow supplement: `docs/multiwindow-evidence.md` and
`bench/multiwindow-current-summary.json` now establish short one/three-window
settled resource and process-cleanup samples for current 055j2/Foot/Monstar at
both grids. All 36 parent/child exits pass and compositor descriptors return to
baseline. Peak/resource churn, sustained multiwindow workloads, resize/history/
image cycles and longer post-close compositor retention remain open.

History/reset supplement: `bench/multiwindow-history-summary.json` adds
108 per-window history/reset cycles with 216 parser/geometry acknowledgments
and five-second post-close samples. All exits and descriptor cleanup pass.
Residual host/device/compositor memory remains and requires allocation
attribution; resize, image-upload/delete, pixel correctness and long soaks
are still missing from this multiwindow workload.

Font-staging experiment: `bench/font-map-evaluation.json` rejects temporary
file mappings because paired private savings were only 216 KiB, below the
frozen 1 MiB gate. The original loader/055j2 checkpoint is restored and Nix
checks pass (`bench/font-map-restored.json`). Do not repeat this as an untested
optimization or treat it as attribution of all retained memory.

Allocation-attribution supplement: `bench/history-memory-attribution.json`
separates engine-accounted and process GPU totals. Terminal-sized history feeds
retain 13.26 MB of engine allocations after reset, versus 32.32 MB for a whole
370 kB feed, stable across three cycles. Window-level extra GPU memory still
requires redraw/swapchain attribution; the surfaceless probe cannot prove it.

Redraw-only supplement: `bench/multiwindow-redraw/validation-restored.json`
validates 36 clean window lifecycles and 12 CUDA lifetime traces. Three-parent
compute allocation rises 3 MiB small / 48 MiB large before any history fill or
reset, identically in both orders. This narrows the required attribution but
does not identify the allocation owner or complete graphics VRAM. Private
headless Ekko presentation and flake checks pass after restored-access recovery.
Resize/image multiwindow cycles, peaks, long soaks and frozen target misses
remain outstanding.

Resize calibration supplement: `bench/resize-geometry-summary.json` validates
54 transitions across six private terminal processes. Shared requested pixel
sizes yield different cell grids; no matched-grid comparison is claimed. CUDA
reported compute allocation returns to 242 MiB at 80×24 after each large resize
and mapped buffers shrink across all three cycles/orders. Multiwindow targeting,
content/reflow pixels, combined history/images and long soaks remain open.

Matched-grid resize supplement: `bench/resize-matched-summary.json` now validates
54 shared-grid transitions across six private processes, with the calibrated
per-terminal pixel requests. Cudaterm's post-cycle PSS remains 79.074–79.123 MB,
above the fixed 78 MB gate; listed compute allocation returns to 242 MiB after
each large-to-small cycle. Combined history/images, multiwindow resize routing,
reflow pixels and long soaks remain unverified by this narrow geometry workload.

Combined history/resize supplement: `bench/resize-history-summary.json` covers
18 same-process cycles across six private windows with exact shared grids,
36 history/reset acknowledgments and clean exits. CUDA post-reset compute is
245 MiB versus 242 MiB at start in both orders; post-reset PSS is 81.36–81.44 MB,
above the fixed target. These are settled post-command samples without content
or allocation-owner proof. Multiwindow combined workflows and image cycles
remain the next missing lifecycle evidence.

Image lifecycle supplement: `bench/image-lifecycle-summary.json` validates
32 uploads plus deletion/failed-replacement checks in four private Monstar/CUDA
processes, with raw/zlib RGB/RGBA image hashes and clean exits. Cudaterm retains
256 MiB listed compute memory after deletion versus 242 MiB initially, and
82.30–82.31 MB PSS exceeds the 78 MB gate. Image pixels, exact allocation release,
Foot Sixel, multiwindow combined workflows and long soaks remain unverified.

Image allocation attribution: `bench/image-history-attribution.json` proves
zero actual history rows despite 4096-row capacity after a large image. RIS
releases exactly 10,158,080 tracked bytes of unused history, leaving input/scan
workspace. Default and diagnostic decode-pump host paths retain identical totals
(`bench/image-engine-memory-summary.json`). Reclaiming this speculative capacity
is a candidate, not implemented or accepted; content preservation and churn/timing
checks must precede acceptance. Full window attribution and image pixels remain open.

Image-history reclaim experiment: `bench/image-reclaim-evaluation.json` rejects
post-commit shrinking despite achieving the memory target and passing the new
preservation regression. Seven of eight timing groups miss frozen guards; no
causal allocator attribution is claimed under shared GPU conditions. The prior
engine/flake/application are restored and Nix checks pass. Avoid repeating this
reclaim-after-upload mechanism as an untested optimization; investigate avoiding
the speculative reservation while preserving GPU parsing and true history growth.

Opaque graphics reservation candidate: `bench/opaque-guard-evaluation.json`
rejects it on four raw-image timing groups despite passing allocation gates and
CUDA correctness. Engine/flake restored exactly; candidate/test/raw samples are
archived. Access and private headless Ekko presentation were revalidated after
permission restoration. Profile raw transfer cost before another memory-path
change; do not treat this rejected implementation as accepted or relax gates.

Raw graphics profile: `bench/image-profile-host-summary.json` and
`bench/image-profile-events-summary.json` locate most raw upload time in the
parser dispatch path, with 11 host graphics services per raw image and 496
measured full feeds needing no service. The latter median 21.30 ms host / 16.25
ms CUDA-event intervals still include scheduling. Next separate fixed dispatch
cost from byte-dependent work with identical wire bytes at different feed sizes;
no production optimization is accepted from these diagnostic measurements.

Feed-size comparison: `bench/image-feed-size-summary.json` records the speed/
workspace tradeoff; 1 MiB improves the measured raw median modestly but retains
61.59 MB tracked device memory versus 20.76 MB at 64 KiB. Feed limits unchanged.
The graphics parameter bitmap passed original gates but failed a fresh paired
10% speed requirement (`graphics-flags-paired-summary.json`); source is restored.
Do not use its original passing run alone as causal optimization evidence.
