# History search

## State and matching

`Engine::search` decodes a bounded UTF-8 query on the host, then sends only the
query and small search metadata to CUDA. It does not copy history to the CPU.
`src/search_kernels.cuh` gives each candidate a cell/codepoint position, including
three combining slots, and compares up to 256 query codepoints. Wide tails are
skipped. Only positive row-wrap lengths permit continuation to the next row;
padding before an early wide wrap is excluded. Hard breaks stop comparison.
The primary source is chronological retained history plus live rows. Alternate
mode uses only its active grid. Exact codepoint matching does not normalize,
case-fold, segment graphemes or implement regular expressions.

A directional cyclic rank chooses the nearest match with atomic minimum. A
commit kernel updates selection and view metadata without modifying text,
cursor/parser state or image ownership. Whole-cell highlight/copy endpoints
can include a base character or additional combining marks when the query starts
or ends inside a cell. Long matches may extend beyond the visible viewport and
are copied in full. New output or resize invalidates continuation positions;
the UI restarts the query before using them again.

The measured query scratch is 1,072 device bytes, independent of history size.
The optional prompt uses at most 512 Cells plus 512 codepoints (18,432 bytes).
Closing search releases these device allocations. Existing selection-output
storage retains its separately bounded capacity when copying has used it.
The smaller visible-grid CPU draft was rejected because it omitted history and
would move terminal search state off the GPU.

## Interaction and rendering

`main.cu` owns query editing and the saved viewport offset. Search consumes its
keyboard/query-paste input locally. Escape restores the saved offset, clamped
to current history; it is not an enduring logical anchor across concurrent
history eviction/reflow. The bottom-row prompt uses the existing CUDA glyph,
face and theme paths and covers image pixels there without changing cells.
Long prompt text is clipped. Opt-in `CUDATERM_TRACE` records search-open,
found/missing and copy events with byte counts, without recording query text.

## Validation and cost limits

The focused test covers Unicode/soft/hard boundaries, long offscreen matches,
exact forward/backward wrap order, feed/reflow invalidation, alternate isolation,
eviction, invalid input, visible prompt pixels, text nonmutation and allocation
release. The full CUDA, graphics, lifecycle and sanitizer evidence is in
`bench/search-validation.json`. Private clipboard/PTY evidence is in
`bench/window-search.json`; read its individual checks for capture scope.

`bench/search-cost-summary.json` is the first functional cost baseline. Three
launches per case each retain 40 samples after five warmups at 80×24 and 318×24.
Ordinary full-history literal search has medians of 49.55/98.05 microseconds;
a 256-character query in a long repeated-X stream has medians of 6.82/27.62
milliseconds. These wall-clock Engine calls include snapshot/CUDA work but
exclude PTY transport, compositor observation and display latency. They do not
prove competitive search latency.

Before any search optimization, the incremental regression gate requires both
median and linear-interpolated p90 no greater than the exact values in this
fixed baseline for all four cases, plus the full correctness/resource checks.
These gates supplement existing better-comparator targets; comparable Foot
and Monstar search-time distributions are still missing. Repetitive long-query
comparison work is a measured next profiling/optimization candidate.
