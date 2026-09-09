# History search

## State and matching

`Engine::search` decodes a bounded UTF-8 query on the host, then sends only the
query and small search metadata to CUDA. It does not copy history to the CPU.
`src/search_kernels.cuh` schedules one thread per cell and enumerates actual
codepoint positions, including three inline marks and an immutable overflow
chain. A 64-bit key orders the cell index and mark ordinal. Matching compares
up to 512 query codepoints. Wide tails are
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

Query scratch is 2,120 device bytes, independent of history size (host ABI
check in `bench/mark-pool-search-abi.txt`). The optional prompt uses at most
512 Cells plus 1,024 codepoints (20,480 bytes), with overflow marks in the
shared bounded arena. Closing search releases query/prompt arrays and compacts
the arena to remove unreachable prompt suffixes. Copy output uses an exact byte
count per viewport batch, rejects batches above 64 MiB, and retains at most
64 KiB of output scratch after copying.
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

`bench/search-cost-summary.json` is the frozen pre-mark-pool cost baseline. Three
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
