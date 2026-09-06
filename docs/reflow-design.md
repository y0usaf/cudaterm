# Primary resize reflow

## Implemented operation

`src/reflow.cuh` plans primary history and screen text in chronological order on
the GPU. Only positive row-wrap lengths join physical rows. A pending wrap maps
an insertion boundary; it never joins an existing following row. Complete Cell
records are scattered in parallel into fresh primary/history arrays. Parallel
row inspection finds used endpoints and wide-cell flags. Serial row planning
uses arithmetic positions for single-width rows; wide rows retain a per-cell
planning fallback. Wide pairs
move together, with U+FFFD at width one. The alternate grid keeps its physical
layout and remains separate from primary history.

The temporary source-cell map is bounded by `(history_capacity + MAX_ROWS) *
old_columns` integers, plus `(HISTORY_CAP + new_rows)` output wrap lengths and one fixed-size descriptor per source row.
Old arrays remain live through allocation, planning and copying; the final
kernel installs dimensions, row maps, metadata and pointers. Temporary arrays
are freed, and persistent history capacity is rounded to powers of two from
128 through 4096. Allocation failure before commit leaves old state intact;
unrecoverable CUDA errors during commit are not a recoverable transaction.

Explicitly printed spaces carry `Cell.reserved` bit 0 through scalar, cooperative,
plain and styled writing paths. Erased default padding has zero provenance and
can be trimmed while packing hard rows. Styled background cells, combining
marks and explicitly typed spaces are retained. Copy formatting still trims
trailing spaces at hard line endings. This separates layout preservation from
copy formatting without changing Cell size or adding persistent buffers.

## Cursor, viewport and graphics rules

Active primary and saved cursor coordinates map through packing; pending-wrap
boundaries remain pending only at the new right edge. While alternate is active,
the saved primary cursor is reflowed and alternate cursor state is clamped under
its physical-grid policy. Margins reset to the full resized screen as before.
Cursor coordinates that leave the live screen are clamped; exact compatibility
for primary full-screen applications with text below a relocated cursor still
needs broader runtime comparison.

The live-screen start accommodates overflowing packed rows while preserving
mapped primary top position when widening would otherwise pull history into
unused blank space. Height growth can pull older rows into the added area.
A scrolled viewport anchors its previous first physical row to the corresponding
new row and clamps to retained history. Resizing to identical dimensions is a
no-op. Oldest output beyond the 4096-row limit is discarded; widening cannot
restore text already evicted by narrowing.

Primary image anchors use the same source-cell map, preserving intra-cell pixel
offsets and pixel allocations. Blank cells containing visible image anchors are
included in packing. Anchors outside retained history become hidden; alternate
images stay physical. Deleting an image uses the existing release path.

## Evidence and remaining validation

`tests/reflow_test.cu` covers logical joins, hard breaks, pending wrap with an
existing following row, wide/combining cells, typed versus erased spaces,
viewport anchoring, alternate content, cursor continuation and height changes.
Updated existing tests require actual reflow instead of historical clipping.
The optimized CUDA suites, 38 graphics cases, 90 engine-host lifecycle cycles
and zero-finding sanitizer runs are retained in `bench/reflow-fast-*.log` and
`bench/reflow-fast-lifecycle.json`. Resize request distributions and the passed
incremental median/p90 gates are in `bench/reflow-fast-cost-validation.json`.
They compare against the measured initial functional reflow implementation;
matched comparator resize performance remains unknown. Wide-row serial
planning remains a measured cost. See `docs/progress.md` for final integration
status, retention numbers and remaining compatibility questions.

## Comparator provenance

The installed Foot package exposes its binary, README, and man pages at
`/nix/store/ls22769pvdl3c28rg16gqc5psckf6kxx-foot-1.27.0`; source files are not
present in that store path, so this audit makes no claim about Foot's internal
resize algorithm. The local Monstar checkout is
`/home/y0usaf/dev/sandbox/monstar`; its `src/Config.zig:112` says the configured
scrollback limit affects startup because libghostty-vt does not resize live
scrollback. The bundled libghostty source contains a separate reflow-capable
`Screen.resize` implementation and tests, including explicit saved-cursor and
pending-wrap cases (`src/terminal/Screen.zig` and `Terminal.zig`), but that is
implementation-reference material, not proof that the installed Monstar binary
uses every path. Its terminal resize code documents primary reflow and
alternate-screen no-reflow as separate policies. These sources support the
primary-only design choice while leaving runtime comparator behavior to a
matched test.
