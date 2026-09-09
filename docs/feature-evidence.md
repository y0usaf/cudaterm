# Feature evidence: Foot 1.27.0 and Monstar 1.1.0

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

The latest German-layout comparison proves a keypad Separator gap and its
retained fix: both references emit numeric comma; Foot emits application SS3
`l`, while Monstar retains comma. The retained increment follows Foot for application and
Ctrl/Alt separator forms. All 544 German cases pass the frozen exact-byte gates,
and all 884 previous US cases remain unchanged. Repeated held-key and following
ordinary-character checks pass 72 cases per layout. These are US/German private
Wayland observations, not full layout/IME or keyboard-protocol parity. See
`bench/keypad-layout-evaluation.json`, `bench/keypad-repeat-{us,de}-evaluation.json`
and [progress](progress.md) for current integration status and configuration-probe
evidence; an earlier environment-only attempt remained US and was not accepted
as German evidence.

## Current keypad runtime comparison

`bench/keypad-evaluation.json` records a Nix-zero evaluation of repeated private
headless fixtures against the pinned binaries below: 408 unmodified cases match
both references, and 299 required modified cases match at least one nonempty
reference. Two application Ctrl+Alt-minus cases have no reference output and
remain unknown/local interception. NumLock-off digits navigate; mode 1035 defaults
on and masks application-keypad mode until cleared. Modes ESC = / ESC >, private
66/1035, reset and application-cursor combinations are exercised through actual
keyboard-to-PTY bytes, with exact F12 sentinels and repeated-order checks.

Numeric-text/Equal modifier behavior remains partial: 68 of 175 cases differ from
at least one reference; six numeric Ctrl+Alt operator cases match neither. Foot
font bindings were disabled for the modifier oracle; Monstar has local hardcoded
font shortcuts. Empty bytes do not prove missing protocol support. Layout is US
only. See [progress](progress.md) for provenance and current integration status;
these byte comparisons do not establish keyboard or latency parity.

This is a local evidence ledger for four interactive features. “Documented”
means an installed README or source comment/API describes the behavior. It is
not a runtime result. “Recorded runtime” means a checked-in benchmark or test
result actually exercised that behavior. The original ledger was documentation-only; the runtime follow-up below
records the later private-compositor evidence.

## Binaries and provenance

The available Foot binary is
`/nix/store/ls22769pvdl3c28rg16gqc5psckf6kxx-foot-1.27.0/bin/foot`.
Its SHA-256 is
`b59004701fa4b34584eca3cbfd7017e8da516e4faf11262ade73e39ec3ead314`.
The installed documentation is under
`/nix/store/znlba1clza8n1d0xvrzb8na8xgd6n9gv-foot-1.27.0/share/doc/foot/`.
The recorded matched runs identify the same store path in
`bench/foot-matched-text.json` and the other `bench/foot-matched-*.json`
files.

The available Monstar binary is
`/nix/store/h8q9vhbxzpsla7m2hqgqygyw6wd0pjny-monstar-1.1.0/bin/monstar`.
Its SHA-256 is
`cf5000df68e9e2e9db5e74f622a837eac5a54407f276351d222e1d8a1ada5653`.
`/home/y0usaf/dev/sandbox/monstar/result/bin/monstar` resolves to that same
store path and has the same hash. The source checkout is currently commit
`e6cfb789eade281076033111e9ef593026bcb96c` (`kitty graphics: pin chunked inline
reassembly with stream tests`), with tag description `v1.0.1-53-ge6cfb78`.
The matching binary hash proves the result symlink and store executable are
identical; it does not prove that the current source checkout was the exact
source used by the Nix derivation.

The historical throughput files are parser/PTY benchmarks, not feature tests:
for example `bench/foot-matched-text.json` and `bench/monstar-matched-text.json`
record `pty-throughput-csi6n` and geometry, with no selection, search, or
resize-reflow assertion. The checked-in cudaterm window records likewise cover
clipboard selection only: `bench/window-selection.json`,
`bench/window-selection-rapid.json`, `bench/window-mouse-selection.json`, and
`bench/window-scrollback.json`.

## Comparison

| Feature | Foot 1.27.0 evidence | Monstar 1.1.0 evidence | Runtime status in this ledger |
| --- | --- | --- | --- |
| Word/line selection | Installed `/nix/store/znlba1clza8n1d0xvrzb8na8xgd6n9gv-foot-1.27.0/share/doc/foot/README.md:234–242` documents double-click word selection, triple-click quoted row or entire row, and quad-click row selection. | README documents drag and rectangular selection; `/home/y0usaf/dev/sandbox/monstar/src/App.zig:3367–3452` passes `word_boundary_codepoints` to `SelectionGesture.press`, `.drag`, and `.autoscrollTick`, with boundary data at `:236–247`. | Documented for both; no comparator runtime selection capture recorded. |
| Wrapped copying | Installed README documents copying selected text, but the local text does not establish whether a soft wrap is joined or emitted as a newline. | The local README documents copy/paste, and `/home/y0usaf/dev/sandbox/monstar/src/Clipboard.zig` owns clipboard transfer, but neither source nor records establish soft-wrap joining. | Unknown for both. |
| History search | Installed README has a Scrollback search section and key bindings for starting search, moving backward/forward, extending to a word, and copying the match (lines 184–211). | README documents `Ctrl+Shift+F`, incremental search, `Ctrl+N`/`Ctrl+P`, Enter-to-copy, and Escape-to-restore (lines 159–174); source has dedicated `/home/y0usaf/dev/sandbox/monstar/src/ScrollbackSearch.zig` and `/home/y0usaf/dev/sandbox/monstar/src/App.zig` search state. | Documented for both; no headless interaction result recorded. |
| Resize reflow | Installed config exposes `resize-by-cells` and `resize-keep-grid`; the installed changelog records reflow behavior and fixes for double-width glyphs during resize (for example lines 540–542 and 625–626). | `/home/y0usaf/dev/sandbox/monstar/src/App.zig:5563–5600` explicitly labels the resize delegate “resize the terminal (reflow)” and calls `term.resize` when cell dimensions change. `/home/y0usaf/dev/sandbox/monstar/src/Config.zig:112–113` limits its “does not resize live scrollback” statement to the storage limit, so it does not prove scrollback reflow. | Active-grid reflow is source/documented for both; scrollback reflow needs runtime confirmation. |

The installed Foot README is the strongest available comparator evidence for
selection and search. Monstar’s source is useful implementation evidence, but
the source checkout must not be treated as historical binary provenance beyond
the explicitly recorded executable identity above.

## Proposed headless runtime checks

Run each binary under the same private headless Wayland compositor and fixed
geometry, using a child process that emits sentinel text and a compositor-safe
input injector:

1. **Word/line selection:** emit `alpha.beta 123`, double-click each token,
   triple-click a line containing a soft wrap, copy through the terminal’s
   clipboard protocol, and compare exact UTF-8 bytes.
2. **Wrapped copying:** at 80 columns emit 79 ASCII characters, a one-cell
   character, a wide character that wraps, then an explicit CRLF. Drag across
   the physical rows and require the expected joined soft wrap plus one newline
   for CRLF.
3. **History search:** emit unique sentinels separated by enough newlines to
   enter scrollback; start each terminal’s documented search binding, type the
   sentinel, advance/finish the match, and verify viewport or copied selection.
4. **Resize reflow:** emit a long logical line with wide and combining glyphs,
   resize 80→40→80 via the compositor/PTY path, and compare screen dump or
   clipboard text before and after. Include a line older than the viewport to
   distinguish active-grid reflow from scrollback reflow.

Record the exact command, compositor, geometry, binary path, SHA-256, and raw
clipboard/screen output for each run. Until those checks exist, the table’s
“documented” entries should not be promoted to measured feature parity.

## Private history-search runtime follow-up

`bench/search-comparators.json` records installed binary hashes, commands,
actual PTY 40×24 geometry, payloads, copied bytes and input observed by the
child. Monstar 1.1.0 passes ASCII history search and exact copy both within a
physical row and across a soft wrap. This does not establish Unicode,
normalization, navigation, no-match, latency or resize behavior. Foot's copy
roundtrip remains unresolved in the fixture; private Weston lacks its primary
selection interface. Earlier inherited-configuration attempts are retained;
they must not be treated as default-keybinding tests. The installed Monstar
`share/man/man1/monstar.1.gz` independently documents Ctrl+Shift+F, Ctrl+N/P,
Enter, Escape and continuing output, without relying on source provenance.

## Cudaterm word-selection follow-up — September 6

The current word-selection kernel expands across visible soft-wrap joins,
including short joins before wide glyphs, while retaining hard-break and
separator boundaries. `bench/word-wrap-validation.json` records literal UTF-8
copy assertions, history/reflow cases and final binary hashes. The private
window sync fixture's mode 6 double-clicks a wrapped 96-character word and
checks exact clipboard bytes without the following space and END text; its
passing output is `bench/word-wrap-sync.log`.

This establishes Cudaterm behavior for these cases. It does not establish
comparator runtime word-selection behavior, Unicode word segmentation,
off-viewport expansion or logical-line triple-click policy. Existing line mode
continues to select physical rows.

## Unicode cursor advancement — measured September 6

`bench/grapheme-summary.json` indexes 99 valid replies from nine private-Weston
launches of the pinned Foot 1.27.0, Monstar 1.1.0 and retained Cudaterm bhsg
executables. Each case clears/homes, writes literal UTF-8 and requests CSI 6n;
all rows remain 1 and actual PTY geometry remains 80×24. Three repeats agree
for every terminal/case. Fontconfig is pinned, but actual glyph fallback and
pixel shaping are not measured.

| Sequence | Foot cells | Monstar cells | Cudaterm cells |
| --- | ---: | ---: | ---: |
| ASCII A / CJK / base plus combining mark | 1 / 2 / 1 | 1 / 2 / 1 | 1 / 2 / 1 |
| Heart plus text selector VS15 | 1 | 1 | 1 |
| Heart plus emoji selector VS16 | 2 | 2 | 1 |
| Regional-indicator flag pair | 2 | 2 | 2 |
| Emoji plus skin tone | 2 | 2 | 4 |
| Family joined with ZWJ | 2 | 2 | 8 |
| Woman technologist joined with ZWJ | 2 | 2 | 4 |
| Digit keycap sequence | 2 | 2 | 1 |
| Leading combining mark | 0 | 0 | 0 |

These are observed cursor advances, not a general Unicode-conformance oracle.
Even equal advances (such as the flag pair) do not prove cluster storage,
copy fidelity or shaping. Fixes must preserve exact text through copying,
chunked feeds, right-margin wraps and resize/reflow; correcting only the cursor
while dropping scalars would not satisfy the daily-driver objective.

## Unicode margin comparison — 2026-09-06

`nix develop --command python3 bench/grapheme_margin_probe.py` exited zero.
The authoritative final run is `bench/grapheme-margin-20260906-015856-24592.json`;
`bench/grapheme-margin-summary.json` records its hash and the independently
verified 84 exact CPR replies across three launches at stable 80×24 geometry.
Earlier margin runs predate final helper corrections; use the named final run
for reproducibility. No application source changed.

Both tested sequences (heart+VS16 and digit+VS16+keycap) have the following
one-based cursor coordinates. Foot and Monstar agree in every case. Contiguous
input and input with a CPR query between base and suffix also agree for these
cases; this is not proof about arbitrary controls or pure transport splits.

| Starting column | Terminal | After complete sequence | After following X |
| --- | --- | --- | --- |
| 79 | Foot / Monstar | (1,80) | (2,2) |
| 79 | cudaterm | (1,80) | (1,80) |
| 80 | Foot / Monstar | (2,3) | (2,4) |
| 80 | cudaterm | (1,80) | (2,2) |

The following X is necessary to expose pending wrap at column 79. These are
cursor observations, not a visual or clipboard test. The failure requires
correct width promotion and wrapping, with exact text preservation still to be
validated. `docs/unicode-increment-design.md` records source paths, required
regressions and the rejected delayed-base design: output must remain immediate
when the application sends no subsequent scalar. No fix or Unicode parity is
claimed. The next implementation must use sanctioned variation-sequence data,
handle the scalar and styled paths, and retain complete UTF-8 through selection,
search and reflow. Full ZWJ storage/shaping remains a separate unmet requirement.


## VS16 review candidate

The wcp2 candidate now widens sanctioned base+FE0F sequences eagerly, including
heart/keycap, with exact UTF-8 copy/search and reflow covered by CUDA regressions.
`bench/vs16-checkpoint.json` records passing Nix unit and private integration
checks. This supersedes the bhsg width result only for the newly measured
heart/keycap cases; skin-tone/ZWJ, full cluster storage and shaping remain open.
Autowrap-disabled right-edge tracking and one-column presentation remain scalar.
No performance acceptance is claimed: affected styled lines use the streaming
CUDA path, whose cost still needs measurement under the existing gates.


The subsequent vjw4 candidate restores styled processing for complete inline
base+VS16 sequences, while suffixes needing prior-feed state still use the CUDA
interpreter. Whole/bulk and suffix-start regressions pass through Nix. The
237–320× slowdown of unconditional VS16 fallback is removed, but 25 of 32 frozen
median/p90 checks still miss their ceilings; see `bench/vs16-styled-evaluation.json`.
This is an experimental performance improvement, not accepted parity.

## Kitty query runtime qualification

`bench/image-protocol-current/report.json` runs a one-pixel RGB Kitty `a=q`
query and a separate CSI 6 n barrier at 80×24 in both terminal orders. Actual
pinned Monstar and Cudaterm return `i=123;OK` in the APC envelope in both runs.
Foot returns the cursor reply but no Kitty reply within three seconds, recorded
as unknown rather than successful graphics support. The installed Foot README
documents Sixel, which needs separate runtime image qualification. All six
process/child exits and Nix validation pass. This query establishes neither
visible pixels, image retention/deletion, animation nor complete protocol parity.

## Exact private-Wayland word/line selection comparison

`bench/selection-comparators-summary.json` validates 12 fresh private Weston
cases: double/triple clicks for Foot 1.27.0, Monstar 1.1.0 and restored Cudaterm
27k8 in both terminal orders. Every child reports 40×24 and CSI 5;10R; a rendered
truecolor marker determines each client cell's actual dimensions. The clipboard
is seeded to detect failed copies; no gesture bytes reach the child and all
terminal children exit zero. Exact clipboard files, screenshots, commands,
binary hashes and configuration are retained in `selection-comparators-settled`.
An earlier fixture captured startup-faded marker colors and refused to click;
those failed captures remain in `selection-comparators-current` with the exact
helper snapshot. The settled helper waits for exact marker color, not a guessed
window position or cell size.

The fixture is `alpha ` + 80 `W` characters + ` omega`, wrapping over three
physical rows at 40 columns, followed by a hard break and `HARD STOP`. Both test
orders agree:

| Gesture on the wrapped continuation | Foot 1.27.0 | Monstar 1.1.0 | Cudaterm 27k8 before fix |
| --- | --- | --- | --- |
| Double-click | 80 `W` characters | 80 `W` characters | 80 `W` characters |
| Triple-click | Entire logical line plus newline | Entire logical line | Only the physical row: 40 `W` characters |

Thus the installed documentation's word “row” was insufficient to infer Foot's
physical/logical policy. Runtime output proves logical-line expansion for this
fixture. Foot and Monstar differ on the final newline; this is preserved as an
observed difference, not normalized away.

The validated Cudaterm logical-line increment passes four repeated private cases:
double-click still copies 80 `W` characters and triple-click copies the full
logical line without a forced newline, exactly matching Monstar here
(`selection-comparators-logical-line-summary.json`). CUDA selection tests pass
hard-break, wide-wrap padding, real history viewport, reflow and pending-wrap
cases. Final integration status is in `bench/logical-line-validation.json`.
That checkpoint was bounded to visible rows. The subsequent retained-history
increment is described below; neither fixture establishes full selection parity.


## Selection beyond the viewport

The history fixture puts the start of a 1,200-letter ASCII word above the visible
40×24 viewport. `bench/selection-comparators-history-summary.json` records 12
pre-fix cases in both terminal orders with exact clipboard bytes:

| Action | Foot 1.27 | Monstar 1.1 | Cudaterm before history expansion |
| --- | --- | --- | --- |
| Double-click | All 1,200 letters | All 1,200 letters | Visible 846-letter suffix |
| Triple-click | Visible suffix plus newline, 853 bytes | Full logical line, 1,212 bytes | Visible suffix, 852 bytes |

The candidate expands Word/Line endpoints through retained soft-wrap joins,
including rows above or below the viewport, while keeping alternate-screen
selection within that screen. Copy extraction uses batches of at most one
viewport; its GPU scratch allocation does not scale with history length.
`nix run .#selection-test` passes exact ASCII/Unicode copy cases, hard breaks
between batches, viewport/cursor preservation, alternate isolation, ring eviction,
and a first-copy allocation bound of 49,177 bytes at 128×24 with all 4,096 history
rows retained. Repeating that copy adds no tracked device allocation.

Eight candidate private clipboard cases pass: the history fixture now returns
all 1,200 letters / the full 1,212-byte line, matching Monstar's bytes; the visible
fixture retains its 80-letter / 92-byte results. The summaries are
`selection-comparators-offviewport-{history,visible}-summary.json`; exact expected
bytes are asserted by `bench/offviewport-clipboard-acceptance.json` through Nix.
Final integration commands all exited zero; see
`bench/offviewport-integration-validation.json` and `bench/offviewport-checkpoint.json`.
Unicode word segmentation, full graphemes, drag/autoscroll and desktop clipboard
backends remain unproven. The CUDA Unicode case proves copy bytes, not shaping.
