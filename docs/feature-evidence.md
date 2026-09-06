# Feature evidence: Foot 1.27.0 and Monstar 1.1.0

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
