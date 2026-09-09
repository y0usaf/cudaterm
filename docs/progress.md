# Development evidence and recovery state — 2026-09-06

## ZWJ geometry implemented; broader grapheme and resource gates remain open

The new package is `/nix/store/sfnwmzl1n0clr8cap03nlcjp19csz4sd-cudaterm-0.1.0`.
It uses generated Unicode 17 Extended_Pictographic and GCB Extend predicates
(156/384 merged ranges, 2,848/2,237 code points). Exact source data and full header
regeneration checks are part of the Nix build, with independent malformed-input
and raw-source membership tests. The scalar GPU path checks the existing suffix
chain once in reverse, preserves control barriers, and appends to a local Cell
before two-cell promotion. Arena exhaustion preserves the pending scalar before
cursor/root mutation. Styled lines containing ZWJ or an incoming joining emoji
fall back before commit; prompt layout reserves joined width before truncation.
Cell size and the existing mark-arena bound remain unchanged.

Nix build and Unicode/search/styled/reflow/selection applications exited zero.
The expanded tests cover all 20 frozen boundary cases at every input byte split,
exact copy/search/reflow, 0/4/66/256 preceding Extend marks, arena growth on the
joined scalar, narrow-base bottom/right-margin promotion, chained family emoji,
large styled batches split after ZWJ, and prompt pixels including negative and
truncation cases. Exact commands and logs are in
`bench/zwj-final-validation-20260906T155042Z/manifest.json`.
All 70 packaged src/tests/tools/data files were independently compared with the
worktree in that directory's `parent-packaged-source.json`.

A parent review probe caught a real intermediate regression: a large SGR-only
batch cleared a preceding CUP barrier. Initial package g1 reported zero-based
column 2 instead of 4; qcx reported 4. Raw evidence is
`bench/zwj-sgr-barrier-before.jsonl`. The styled preflight now routes such
control-only fragments through the interpreter. A dedicated regression passes
and the fresh package reports column 4. The earlier package/logs remain retained.

Fresh private-headless comparison collects all 20 frozen cases twice across
Foot, Monstar and cudaterm. Parent raw-byte review confirms all 40 candidate
sequence replies and 40 after-X replies match the frozen Foot expectations;
there were 11 case differences before this change. A separate nine-case
no-autowrap probe collects all replies, but clipped cursor positions do not
prove retained text. Existing clipping guards are retained pending copy evidence.
No desktop was used. These are cursor/state observations, not shaping or latency.

The additional ten-case investigation exposes six remaining Foot differences:
modifiers after a joined component (two cases), nonzero-width GCB Extend
characters U+FF9E/U+FF9F/U+1ADD (three), and zero-width space before ZWJ (one).
Foot and Monstar also disagree for zero-width space after ZWJ. Exact observed
coordinates and payloads are in `parent-extended-review.json` in the validation
directory. These observations require further storage/default-ignorable policy
work; the current change does not claim complete GB11 or UAX #29 conformance.
Sequence shaping, font fallback and the full daily-driver requirements remain.

Static Nix cuobjdump evidence in `bench/zwj-resource-delta-20260906T155312Z/`
finds 58 kernels before and after. Feed registers/shared memory remain 58/20,376
bytes, but feed stack grows 128→144 bytes. Styled scan registers/stack grow
28/80→32/112; prompt registers 26→27 and selection registers 36→38. The
engine-host executable grows 339,968 bytes. These are costs, not runtime-memory
or speed claims. Nix flake check and Finix preview/evaluation exit zero in
`bench/zwj-nix-integration-20260906T155452Z/`; no activation occurred.

Explicit-path CUDA memcheck (Unicode) and initcheck (search) exited zero with
zero reported errors. Private graphics (38 cases), Ekko presentation and sync
checks also exited zero through Nix. Raw commands, target hashes and results are
in `bench/zwj-final-sanitizer-20260906T155621Z/` and
`bench/zwj-final-private-20260906T160351Z/`.

The ordinary-feed screen failed its frozen 1.05 ratio limits: ASCII median
1.0553; Unicode median/p90 1.0680/1.0538. The parent evaluator includes all 480
samples (48 per workload per binary), superseding the retained worker summary
that omitted half. Tracked device and mark growth were zero. Host timing drift
was present, so attribution remains unresolved; it does not erase the failure.
See `bench/zwj-feed-regression-20260906T160756Z/parent-pooled-evaluation.json`.

Two-order private window measurement gives six samples per binary at 318×89.
Median PSS rose from 79,196,160 to 79,729,152 bytes (+532,992); per-process NVIDIA
memory rose from 331,350,016 to 335,544,320 bytes (+4 MiB). This confirms a resource
regression and misses the 78,000,000-byte PSS target. Allocation ownership is not
established by these totals. Raw evidence and parent summary are in
`bench/zwj-window-resource-20260906T161153Z/`.

Derived compiler experiments under `bench/zwj-property-inline-static-20260906T161640Z/`
have not changed production. With the production `-lineinfo` flag, preventing
predicate inlining saves only about 60 KB of embedded CUDA data while increasing
feed registers from 58 to 72; preventing loop unrolling gives no saving. Earlier
experiments omitted `-lineinfo` and are paired prototypes only. Recovery review
also found a truncated font-data path in these experiment records; valid matched
window builds are required before attributing runtime costs to line information.

Restored-access checks in `bench/access-zwj-recovery-20260906T162857Z.json` reached
the Nix daemon, exchanged bytes over an owned Unix socket, and queried the RTX
4090. Five current implementation hashes and both result links match the saved
checkpoint. The pending memory experiment is resuming only on private headless
Weston. Older timing failures, lifecycle/resource comparisons, six extended
Unicode gaps and the full goal remain unmet.

## Restored access and ZWJ boundary baseline — 2026-09-06

Fresh parent checks reached the Nix daemon (2.34.8), exchanged bytes through an
owned Unix socket, and queried the RTX 4090 (driver 595.91.07). Access evidence is
`bench/access-recovery-20260906T153119Z.json`. All 58 packaged source/test hashes
still match qcx; the result links remain unchanged. Desktop benchmarking remains
prohibited. The restarted worker used only a new private headless Weston session.

`env -u DISPLAY -u WAYLAND_DISPLAY LD_LIBRARY_PATH=/run/opengl-driver/lib nix
develop --command python3 .../bench/grapheme_zwj_boundary_probe.py ...` exited
zero. The six terminal runs contain 20 cases each, with 120 sequence CPRs and
120 after-X CPRs. Parent review checked every raw reply against its decoded
1-based coordinates, effective 80×24 geometry, payload identity and repeat
consistency. Exact argv, raw output and comparison are under
`bench/grapheme-zwj-boundary-run-20260906T153118Z/`. Its inner report filename uses
local time; embedded UTC timestamps and command time records are authoritative.
`env -u DISPLAY -u WAYLAND_DISPLAY nix run .#unicode-test` also exited zero.
No production code changed during this recovery increment.

Before implementation, `parent-reviewed-expectations.json` in that directory
freezes Foot 1.27.0 geometry for all 20 cases. Both references agree on 17; qcx
fails 11 of the selected expectations. Direct woman–ZWJ–laptop and either SGR
placement advance two columns in both references, four in qcx. Extend after ZWJ
and repeated ZWJ do not join in either reference; Extend before ZWJ does. The
references disagree after same-position CUP and backspace, and for narrow
copyright–ZWJ–registered at column 80. Choosing Foot behavior in these cases is
an explicit terminal compatibility policy, not a Unicode cursor requirement.
Narrow copyright–ZWJ–registered has width two at column 1 in both references,
so simply taking the maximum scalar width would be insufficient.

Official Unicode 17 GraphemeBreakProperty data is staged with URL/hash in
`bench/zwj-unicode-source-20260906T153141Z/`; it is not yet integrated. Next work
needs generated EP and GCB Extend predicates, validated reverse suffix traversal,
control barriers, two-cell promotion, and matching prompt geometry. A successful
suffix append to a local Cell must precede any cursor/root promotion so pool
exhaustion can retry without partial mutation. Styled ZWJ lines need preflight
fallback before commit. Required regressions include exact copy/search/reflow,
UTF-8 splits, overflow, margin/wrap and prompt behavior. This baseline measures
cursor geometry only; shaping, full grapheme behavior, resource/performance gates
and the full original goal remain incomplete.

## Latest checkpoint: duplicate scan code removed; resource targets unmet

The prior goal turn made progress through code changes and validated checkpoints.
Latest 5lda graphics, private headless presentation, sync, Nix flake checking and
Finix preview/evaluation now pass; see
`bench/mark-pool-final-confirmation-20260906T144608Z/manifest.json`. The initial
sync wrapper pre-created its output directory and failed before exercising the
application; its failed invocation is preserved, and a fresh-path retry exited
zero. No deployment or desktop benchmarking occurred.

Read-only Nix cuobjdump output shows all 48 shared GPU functions have identical
assembly and compiler resource counts between pre-compaction 2yi and latest
5lda. Exact output/hashes are in
`bench/compactor-binary-resources-20260906T144636Z/`. This rules out changed code
or register counts in those functions as a direct explanation, not differences
in host/runtime behavior, scheduling or clock state.

Owned standalone CUPTI runs exited zero; instrumented timings are excluded from
acceptance. First hybrid 64-node serial-fallback launch spent 301,309 ns in the
runtime API, including 281,619 ns of correlated module/function loading, while
the actual kernel took 16,416 ns. The serial baseline launch spent 73,809 ns,
including 56,339 ns of loading; its kernel took 86,433 ns. Coarse global SM-clock
samples ranged 495–2760 MHz during serial and stayed at 2760 MHz during hybrid.
These 100 ms global samples cannot assign clock state to individual kernels or
attribute other GPU activity. See
`bench/compactor-runtime-profile-20260906T145100Z/parent-profile-summary.json`.
The prior failed timing gates remain failed.

The completed follow-up reuses the engine's existing signed integer CUB sum scan
for 0/1 mark-prefix flags (maximum sum 1,048,576). Signed/unsigned corresponding
types may alias; storage, node order and the 8 MiB arena limit remain unchanged.
The stored package is `/nix/store/qcx63462ba02li8gid9h7wjxdy5bzldb-cudaterm-0.1.0`;
`bench/mark-compaction-scan-reuse-checkpoint.json` verifies 58 packaged files and
links the exact patch relative to 5lda. Static review finds exactly two duplicate
unsigned scan kernels removed (60→58 total), no added kernels and no resource
changes in shared functions. The engine-host executable shrinks by 118,784 bytes,
including 110,512 bytes of embedded GPU code. This is verified code-size reduction,
not a claimed runtime-memory or speed improvement.

Fresh production compaction passes all 131 oracle-checked rows, including six
expected malformed cases. CUDA memcheck/initcheck, Unicode/search/reflow/selection,
graphics, private headless presentation/sync, Nix flake checking and Finix preview/
evaluation all exit zero. Temporary scan storage remains 0/767/1791/5119 bytes
by size/path. A benchmark conditional initially omitted the non-production
prototype branch; its exact pre-fix file is archived, and serial/prototype/
production builds all exit zero after correction. No deployment occurred.
The sanitizer command record initially named an executable absent from the Nix
PATH. Explicit-path parent reruns of memcheck and initcheck each exited zero,
checked all 131 rows and reported zero errors. Their reproducible commands,
wrapper/payload hashes and raw output are in
`bench/scan-reuse-sanitizer-provenance-20260906T150529Z/manifest.json`;
the earlier uncertain invocation record remains preserved.
Current 318×89 private-window PSS is 80.337–80.392 MB and NVIDIA compute memory
331,350,016 bytes. One parent CPU interval accumulated 0.01 seconds; zero aggregate
idle activity is not established. The 78 MB PSS gate and all previously failed
timing screens remain unmet. A diagnostic-only engine copy now captures seven
constructor/lifetime stages and vector addresses/capacities, smaps/rollup and
before/after-logging mallinfo2. Three default and three process-local trim-control
runs/analyzers exited zero. Default scope exit unmapped the 4,632,576-byte font
allocation while adding about 2,227,296–2,227,456 free heap bytes with no heap
shrink; the two 1,114,112-byte tables occupied that heap. Trim-control runs mapped
all three and released 6,868,992 allocator mapping bytes. Raw evidence and limits
are in `bench/startup-staging-qcx-summary.json`; instrumentation may alter layout.

This reconfirms earlier constructor evidence, not a newly proven window saving.
The prior `bench/font-map-evaluation.json` already rejected mapped startup data:
paired window PSS reductions were only 224,256/258,048 bytes against a frozen
1,048,576-byte minimum. That stronger end-use counterevidence prevents repeating
the loader experiment on the strength of this engine-only result. No allocator
setting, mapped loader or blanket malloc_trim is adopted. Next work is the
measured emoji-ZWJ cursor-geometry gap using the validated variable suffix pool;
shaping and full grapheme conformance remain separate unmet requirements.

## In progress: hybrid mark compaction; small-pool timing gates unmet

Restored access is verified in `bench/access-recheck-20260906T142634Z.json`:
Nix daemon communication exited zero, an owned Unix socket exchanged bytes, and
NVIDIA reported the RTX 4090 with driver 595.91.07. All graphical work remains
restricted to private headless Weston; no desktop benchmarking is authorized.

The recovered hybrid harness compiled and ran through Nix: serial and candidate
streams each contain 131 checked rows, including six expected malformed cases.
Candidate CUDA memcheck and initcheck exited zero with no errors. Exact commands,
source hashes and raw outcomes are in
`bench/mark-compaction-hybrid-validation-20260906T164500Z/manifest.json`.
The hybrid selects serial compaction when both node and root counts are at most
256, avoiding parallel-launch costs for small collections. The parallel path
uses pointer doubling and stable prefix remapping with bounded temporary storage.

Correctness checks passing does not establish the performance gate. The extended
Nix evaluator exited **1**: eight of 41 case/size screens fail the unchanged
median/p90 limits, including several tiny serial cases and 512-node sparse/empty
collections. All samples remain in
`bench/mark-compaction-hybrid-evaluation-20260906T1428.json`. Earlier 48-case
prototype results passed, but omitted these small sizes. No threshold or target
has been relaxed. Source review found that the serial dispatch relied on the
caller clearing status; it now resets status after successful precondition
validation. Fresh Nix build, Unicode, search and styled tests exited zero for
`/nix/store/q69iza52054mk90c5mwfq6hsrvp1ygcc-cudaterm-0.1.0`.
See `bench/mark-pool-v5-recovery-20260906T170500Z/manifest.json`.
All 58 packaged source/test files match the working tree in
`bench/mark-compaction-v5-source-audit.json`; untracked local files remain preserved.

A freshly compiled engine capacity probe passed three Nix runs. Each retained
1,048,576 nodes in exactly 8 MiB, copied 2,097,159 bytes exactly, released large
copy scratch and rejected an extra mark while preserving prior text. Exhaustion
wall time was 529,858 / 547,178 / 565,768 ns (median 0.547 ms), compared with the
historical single serial sample of 473.327 ms. This is not a contemporaneous
paired comparison or display latency measurement. See
`bench/mark-compaction-v5-capacity-summary.json` and its raw run manifest.
Core reflow/selection/VT/reference/graphics (38 cases), private headless Ekko
presentation and sync checks exited zero; see
`bench/q69-core-private-20260906T143030Z/manifest.json`. Current large-window PSS
is 80.881–80.907 MB, still above the 78 MB target. NVIDIA compute memory remains
331,350,016 bytes. One of three parent CPU intervals accumulated 0.01 seconds;
these limited observations do not establish idle zero activity.

Nix flake checking, Finix preview build and Finix evaluation exited zero, with no
activation. Four ordinary-feed collections exited zero but their unchanged 1.05
median/p90 screen exited **1**: all five workload median ratios fail (1.194,
1.258, 1.383, 2.088, 1.505); ANSI p90 also fails. Tracked device growth is exactly
zero. All 480 samples remain in
`bench/q69-finix-feed-validation-20260906T143230Z/`; no failed samples or gates
were adjusted. Per-host breakdown in
`bench/mark-compaction-q69-feed-order-diagnosis.json` shows large variation for
both baseline and candidate; this does not erase failure or identify its cause.
Final private window-search and six exact mark-clipboard checks exited zero,
including the byte-exact evaluator; see
`bench/q69-final-private-window-20260906T143545Z/manifest.json`.
The functional checkpoint is `bench/mark-compaction-q69-checkpoint.json`, with
an isolated implementation patch relative to v4. Small-pool compaction,
ordinary-feed, historical search and PSS gates remain unmet.

The next draft restores the frozen serial nested-span loop (removing extra
root-index lookup) and uses it for up to 512 nodes with at most 256 roots. No new
algorithm or relaxed gate is introduced. Initial isolated measurements pass 40
of 41 screens, failing 64-node chain p90. Corrected serial/candidate/candidate/
serial measurements each exit zero with 131 checked rows, but the timing
evaluators exit **1**: first pair 14 failures, second pair 19, pooled six samples
per case/binary 18. All outcomes remain in
`bench/mark-compaction-final-streams-20260906T144004Z/`; no favorable pair was
selected as acceptance. Pooled million-node chain host medians are 491.905 ms
serial and 0.990 ms candidate. Small-pool timings vary strongly and remain unmet.

An execution mistake first reran stored 2yi/q69 ordinary-feed hosts instead of
the standalone compactor binaries. Those files remain explicitly marked as
mis-scoped in the archived/corrected nested-validation manifest; they cannot
validate this draft. The corrected four-run manifest names and hashes the exact
serial/hybrid binaries. The simpler nested loop passed fresh Nix build, Unicode/search/reflow/selection,
CUDA memcheck and initcheck (all exits zero, no sanitizer errors). Its package is
`/nix/store/5ldaq77h5j8db2qxxdy734nz45r1invl-cudaterm-0.1.0`;
`bench/mark-compaction-nested-checkpoint.json` verifies all 58 packaged source/test
files and links the exact patch relative to q69. The broader private graphical
and Finix results above belong to q69; they were not rerun for this serial-loop
follow-up. Further threshold tuning has stopped. No background verification jobs
remain. Next investigation must explain timing variation and cold-launch cost
without relaxing frozen targets; latest graphical/Finix confirmation and all
original incomplete feature/resource requirements remain pending.

## Retained pre-compaction candidate: variable-length marks integrated; search latency gate still open

The restored-access run verified the Nix daemon, an owned Unix socket and NVIDIA
access. All window work used private headless Weston. The current local candidate
is `/nix/store/2yi0131q1xp8pggk80mq5d1h5m4lnsnk-cudaterm-0.1.0`; its checkpoint is
`bench/mark-pool-v4-checkpoint.json`, source verification is
`bench/mark-pool-v4-source.json`, and its isolated implementation patch is
`bench/mark-pool-v4-candidate.patch`. All 57 packaged source/test files matched the
working tree at that checkpoint. Existing result/Finix links are unchanged; nothing was activated
or pushed by this recovery run.

The 32-byte cell keeps three inline marks and an immutable overflow head. Parser
retry preserves a decoded scalar across exhaustion, including a scalar at the
last byte and synchronized-frame boundaries. Styled preflight rejects overflow
before commit. Rendering, exact copy/search, prompt and reflow share the arena;
compaction visits primary/alternate/history/prompt roots. Nix Unicode, search,
styled, reflow, selection, VT, reference and graphics checks passed. Six private
clipboard observations preserve exact four/16/256-mark bytes, and current-binary
sync, window-search and Ekko presentation checks passed. Nix build, flake
evaluation, Finix preview build and Finix evaluation also exited zero, with no
failed Finix assertions. See the final manifests in the checkpoint.

The arena starts empty and caps at 8 MiB; all-live exhaustion raises an explicit
error. The full-capacity probe retains 1,048,576 nodes, copies 2,097,159 bytes
exactly and preserves old text after the failed append. It submits supported
16 KiB input chunks and reselects after output invalidates selection. Earlier
fixture failures (oversized input, implicit alternate-screen home, overwrite,
and stale selection) and their corrections are preserved. Copy counts exact
bytes before allocation, rejects viewport batches above 64 MiB and frees output
buffers above 64 KiB. The v4 allocation trace observes 106 application cudaMalloc
calls, peak requested storage 30,129,978 bytes and zero tracked live bytes after
destruction; this excludes driver/context/internal reservation costs. The serial
full-live compaction/exhaustion path took 473.327 ms in one uninstrumented v3
sample. This pause remains a responsiveness issue, not an accepted latency result.

The frozen ordinary-feed screen passes: before/candidate/candidate/before gives
48 samples per workload/binary across five workloads, all median/p90 ratios at
most 1.05, no overflow arena, and exactly 64 bytes of declared fixed metadata.
The initial candidate failed allocation growth by 16,896 extra bytes; removing an
unused LineScan field fixed the issue without changing gates. Timing variation
prevents attributing an isolated speedup. Raw failed and final paired results
remain in `bench/mark-pool-paired-20260906T134234Z/` and
`bench/mark-pool-v4-paired-20260906T134657Z/`.

The separate historical search gate remains unmet: 80-column literal-search p90
was 85.913 us against 50.262 us; the other three search cases pass. All 480 samples
are preserved in `bench/mark-pool-search-cost-20260906T135029Z/`. Four subsequent
controlled-order runs also varied strongly for the unchanged baseline (median
246.529 then 97.295 us; candidates 184.209/184.614 us). These observations do not
isolate a source regression and do not erase the failed absolute gate. Search
scratch is now 2,120 bytes for a 512-codepoint query; prompt arrays are 20,480 bytes,
plus shared suffix storage. Search cleanup returns tracked memory to baseline.

Large private-window PSS is 80.125–80.208 MB, above the unchanged 78 MB target;
NVIDIA compute-process memory is 331,350,016 bytes. Three one-second parent CPU
samples reported no accumulated CPU ticks, which does not establish zero total
activity. ZWJ geometry/shaping, broader font/config/input work, lifecycle soaks,
and original comparative resource/latency targets remain open. Full goal is
incomplete. Next work is controlled search profiling and the measured serial
compaction pause, while preserving the validated exact-text behavior.

## Earlier standalone mark-pool foundation (before engine integration)

The previous turn was progress: it verified ZWJ geometry gaps and a distinct
four-mark copy/search loss. This turn implements a standalone immutable suffix
pool and strengthens the clipboard baseline; production remains at skin-tone v2.
The durable record is `bench/mark-pool-foundation-checkpoint.json`.

Private triple-click clipboard fixtures collected four/16/256-mark inputs twice
per terminal (18 observations), with pinned binaries/fonts, 40×24 geometry and
all terminal/compositor/clipboard exits zero. Nix collection and evaluator exited
zero; raw bytes are retained in `bench/mark-selection-baseline/`. Monstar keeps
exact four/16-mark bytes but only 64 marks from the 256-mark input. Foot composes
A+acute, remains canonically equivalent at four/16 marks, and retains 255 at 256.
Cudaterm keeps only three marks in every case. The evaluator distinguishes exact
bytes from canonical equivalence and separately records Foot's trailing newline.
The first launch failed before compositor creation due to missing Pillow; its log
is preserved, and the successful recovery uses the pinned Pillow environment.

`bench/mark_pool.cuh` retains the 32-byte Cell ABI and first three inline marks,
then uses immutable 8-byte suffix nodes referenced by the high reserved bits.
The explicit-space bit is preserved. A single parser leader appends; allocation
failure changes neither root nor used count. Compaction marks shared chains once,
remaps nodes in old-index order, and rewrites supplied roots only after validation.
It is a standalone component, not a connected engine implementation.

Final compile and runtime both used `nix develop --command` and exited zero
(`bench/mark-pool-parent-final/commands.json`). The GPU harness proves exact
four/16/256-mark reconstruction, immutable 256-to257 branching, shared snapshots,
space-bit preservation across append/compaction, reclamation after roots clear,
repeated fill/compact cycles, FULL status with unchanged root/counter, malformed
index rejection, and rejection of a self-parent cycle without changing root/node/
counter state. Earlier drafts and test runs remain preserved. The test arena has
512 nodes; a 256-mark root uses 253 suffix nodes. No production latency, memory-
retention, actual history/reflow or shaped-glyph claim follows from this harness.

Parent review corrected inline duplication, reversed ordinal lookup and repeated
shared-chain traversal. It also replaced a proposed UTF-8 rewind with a pending-
decoded-scalar integration design: a scalar may start in an earlier feed, so its
bytes cannot safely be retried without retained parser state. Copy output must
count duplicated/shared roots, and search must avoid multiplying every ASCII cell
by a maximum-mark thread count. These decisions and frozen exact-text/Cell-size
gates are in `bench/mark-pool-integration-{decisions.md,gates.json}`.

Next is production integration: pool lifetime/retry, every text consumer including
search prompt, exact-copy batching, and measured compaction/capacity behavior.
The current terminal still loses the fourth mark. ZWJ width/shaping and original
memory/timing targets remain open; no deployment or desktop testing occurred.

## Longer graphemes: verified geometry and copy gaps

The previous turn was progress: the skin-tone v2 increment was retained after
all required integration checks. Current source hashes still match that checkpoint.
This turn adds `bench/zwj-investigation-checkpoint.json`; production is unchanged.

A corrected private Weston probe records 21 cases across both orders of all three
terminals (126 observations), with exact payload/CPR/80×24 geometry and clean exits.
Nix collection and summary commands exited zero. Family and toned family advance
8 cells in Cudaterm versus 2 in both references; technologist, rainbow/pirate flags,
profession and heart-on-fire use 4 versus 2. Actual kiss/couple/toned-kiss sequences
use 8/6/8 versus 2/2/2. Both references preserve joining through SGR and a CUP to
the same cursor position; repeated ZWJ remains separate in all three. The original
18-case fixture mistakenly used standalone kiss/couple scalars; its raw output and
helper are preserved as scalar controls, not evidence for those ZWJ sequences.

A derived current-engine probe, rerun under `nix develop --command` with exit zero,
proves exact copy and search before/after an 80-to-40-column resize for all six
tested ZWJ strings, despite the geometry gap. It independently proves actual text
loss for `A` + U+0301 U+0308 U+0323 U+0332: copied text loses U+0323 and exact search
fails before and after resize. This distinguishes a geometry problem from an
existing arbitrary-mark storage problem. Raw JSONL, source hashes and actual Nix
run argv are in `bench/grapheme-engine-parent-validation/`. Earlier failed compile
attempts and a stale placeholder manifest remain preserved and excluded.

The source-based storage audit is `bench/zwj-storage-options.md`. Global Cell
expansion increases ordinary history memory; wide-tail payloads need a one-column
resize fallback. A CPU-only finite RGI trie prototype validates exact prefix/text
reconstruction in 41,220 serialized bytes under Nix (exit zero), but does not solve
arbitrary combining-mark loss, incomplete/non-RGI strings, or shaping. The original
worker prototype helper was overwritten in a coordination collision; its JSON is
not authoritative. The parent prototype has a separate exact helper/hash and output
(`bench/zwj-trie-parent-prototype.json`). No CUDA allocation/performance is inferred.

Next: implement a bounded variable-length representation with lossless overflow
and lifecycle handling, using these copy and geometry failures as acceptance cases.
Keep the original memory/timing gates and the full grapheme/shaping objective open.

## Skin-tone sequences: validated v2 increment retained

Recovery access recheck: Nix daemon access, an owned Unix socket roundtrip and
NVIDIA enumeration passed; see `bench/access-skin-tone-v2-recovery-20260906T122013Z.json`. Fresh v2 build, Unicode (including the clipped no-wrap copy regression), search
and reflow validation exited zero; see
`bench/skin-tone-v2-recovery-20260906-081915/manifest.json`. All 31 frozen
private-compositor feature expectations pass in
`bench/skin-tone-v2-feature-parent-evaluation.json` (Nix evaluator exit zero).
Engine tests remove display variables; window tests use private Weston.
All 11 final integration commands exited zero, including VT/reference/selection,
private sync/search, 38 graphics cases, private Ekko, flake check, final build,
Finix preview build and evaluation with no failed assertions. The durable record
is `bench/skin-tone-v2-checkpoint.json`; the exact feature patch is
`bench/skin-tone-v2-candidate.patch`. Final application SHA-256 is
`062fb5b7f1fc9af7a7db8fbe3d03a766aa51b542ab517e415c1b2ff1279a37fc`.

The before/candidate/candidate/before cost screen also passed unchanged limits
(48 measured samples per workload per binary; tracked device growth zero).
`bench/skin-tone-v2-paired-evaluation.json` retains all samples. Before-run timings
varied from roughly 22 ms to 12 ms; the lower candidate p90 is not evidence of
an attributable speedup under uncontrolled shared scheduling. Current private
large-window PSS is 81.862–82.006 MB, still above 78 MB; three one-second parent
CPU samples had zero ticks at sampled resolution, not proof of zero wakeups or GPU
activity. Reported NVIDIA compute memory is 331,350,016 bytes. No deployment or
activation occurred, and both existing result links are unchanged.
The v1 Unicode/search/reflow checks, 31-case cursor comparison and paired cost
screen passed (see `bench/skin-tone-feature-evaluation.json` and
`bench/skin-tone-paired-evaluation.json`). Source review then found a clipped
no-wrap cursor could target an earlier cell. V2 guards that ambiguous position
and adds an exact-copy regression. Fresh v2 validation above supersedes v1
for the retained current source; v1 raw results remain preserved.

The previous turn made progress by retaining the German keypad separator fix.
Fresh private Weston cursor probes against that exact h1ic binary and pinned
Foot/Monstar now confirm 72 basic observations: VS16 hearts, VS16 keycaps, keycaps
without VS16, ASCII/CJK/combining controls and regional-flag-pair cursor positions
agree. Skin tone and the two tested ZWJ sequences still differ: Cudaterm advances
4/8/4 cells for toned thumbs/family/technologist versus 2/2/2 in both references.
The flag-pair result proves cursor position only, not cluster storage or shaping.
Raw reports are in `bench/grapheme-current-retained/`; both terminal orders agree.

A 114-observation skin-tone extension separates reference policy differences.
Valid wide modifier bases advance two cells in both references, versus four in
Cudaterm. For narrow bases and base+VS16+tone, Foot uses two cells while Monstar
varies. Both references preserve skin-tone adjacency across SGR and a CUP to the
same cursor position, so a proposed anchor cleared by every escape was rejected.
Invalid ASCII/heart+tone, repeated modifiers and intervening combining marks have
different reference behavior; these cannot justify a blanket zero-width rule.
`bench/grapheme-skin-baseline/` preserves all replies and payload writes.

The candidate uses the local Unicode data file whose header explicitly identifies
Emoji 17.0 (the package version 1.19 is not the Unicode version). Its exact copy is
`data/emoji-data-17.0.0.txt`, SHA-256
`2cb2bb9455cda83e8481541ecf5b6dfda66a3bb89efa3fa7c5297eccf607b72b`.
The generated modifier-base table contains 134 code points in 50 ranges and is
checked by Nix against the versioned source. Eligible base+optional VS16+tone joins
one wide cell; lone/invalid/repeated modifiers retain explicit scalar behavior.
SGR/same-cursor adjacency remains allowed, while a cursor inside an old wide pair
does not qualify. Streaming placement reuses the existing margin/insert/history
promotion. Complete inline sequences keep the parallel styled path; split or
unsupported contexts fall back before styled commit. Search prompt layout uses
the same complete-sequence width. Cell capacity and scalar width tables are unchanged.
This is not a ZWJ, shaping or arbitrary-length grapheme implementation.

Review corrected draft omissions in cursor adjacency, narrow-base paint/prompt
promotion and one-column styled fallback before the build; the draft is archived.
`nix build . --no-link --print-out-paths` exited zero for
`/nix/store/s6gdmyl8239gbsz0valryii5jvhlg5vl-cudaterm-0.1.0`.
V1 CUDA Unicode validation subsequently exited zero. New tests cover byte splits, margins, insertion,
bottom scrolling, reflow, exact search/copy, control adjacency and bulk-versus-byte
feeds at 1/8/20 columns. No test success is claimed until its Nix command exits zero.

Pre-change engine feed/reply cost collection exited zero: 24 measured samples per
ASCII/ANSI/Unicode/tone/styled-tone workload, medians 22.29–22.83 ms, with maximum
tracked allocation 18,206,422 bytes. `bench/skin-tone-cost-gates.json` freezes an
additional median/p90 ratio screen of at most 1.05 and no tracked allocation growth;
paired confirmation is required after an initial pass. These engine intervals are
not window or physical latency, and original competitive gates remain unchanged.
The full goal remains incomplete, including the 78 MB PSS target and ZWJ/shaping.

Next storage investigation is recorded in
`bench/grapheme-next-audit-20260906-082928.md`. Current family pictographs remain
in separate cells; the three-mark limit constrains a proposed collapsed cluster,
not proof that the current family copy is truncated. Expanding every Cell from
32 to an illustrative 52 bytes would add 6.55 MB to an 80-column 4096-row ring
and 26.05 MB at 318 columns, before live grids. No such expansion is adopted.
Bounded pool or wide-tail storage requires ownership, overflow and consumer
validation before implementation; this note is design evidence only.

## German keypad separator: validated and retained

The previous recovery turn made progress: all 13 integration commands passed and
its keypad checkpoint was retained. A new layout fixture first exposed its own
configuration error: XKB environment variables did not change Weston's effective
US map. All six physical evdev-21 probes returned `y`, not German `z`. That Nix-zero
collection is preserved as US calibration in `bench/keypad-layout-de-baseline/`,
with `bench/keypad-layout-env-diagnosis.json`; it is not German-layout evidence.

The corrected helper writes a private Weston keyboard section with explicit
keymap rules/model/layout/variant/options. All six probes now return `z`. Repeated
17-key/2-mode/2-NumLock observations show German numeric Decimal is a comma in
Foot and Monstar but a period in Cudaterm. Forced application mode produces Foot's
SS3 `l` separator sequence, Monstar's comma, and Cudaterm's incorrect SS3 `n` decimal
sequence. Fourteen modifier phases confirm Alt-comma, Foot Ctrl keysym 65452 and
modified SS3 `l`, versus Cudaterm's hardcoded period/65454/SS3 `n`. Exact reports and
summaries are `bench/keypad-layout-de-configured*` and `bench/keypad-layout-de-modified*`.
The premature modifier-summary attempt exited one while collection was still
running; its log is preserved, and the completed collection and summary exited zero.

Frozen `bench/keypad-layout-gates.json` requires German separator bytes to match
Foot, all other keys to retain previous behavior, all existing US mode/modifier
bytes unchanged, and whole held-key repetitions followed by an intact ordinary
character. This changes no original performance targets.

The candidate defers only NumLock-on Decimal until GLFW's layout-resolved
character-with-modifiers callback, which precedes ordinary text delivery and also
runs for Alt/Ctrl and repeats in the pinned GLFW 3.4 source. Its encoder selects
comma/SS3 `l`/65452 for Separator and retains period/SS3 `n`/65454 for Decimal.
The next plain callback is consumed once; release/other keys/focus loss clear
pending state. Search and NumLock-off navigation retain their existing paths.
Other Unicode symbols on that physical key are forwarded as text; their extended
modifier/protocol semantics remain unverified. The deprecated GLFW callback is
available in the pinned 3.4 dependency; backend/IME coverage beyond the measured
Wayland layouts remains open. A plain-character-only fix was rejected because it
would leave the verified application and Alt/Ctrl errors in place.

The candidate Nix build (including input tests) exited zero:
`/nix/store/h1icfdpzis7gfgbcwaaw526ghicjmbip-cudaterm-0.1.0`.
All four private candidate fixtures and summaries exited zero through Nix.
`bench/keypad-layout-evaluation.json` passes 68 German basic and 476 German
modified cases, plus unchanged 408 US mode and 476 US modifier cases. Each
candidate fixture was repeated in fresh private compositors.

Both layout repeat fixtures and their evaluators exited zero: 144 total held-key
cases across Foot/Monstar/Cudaterm in both orders emit whole expected sequences
with at least two repetitions and exactly one following ordinary key. Observed
counts were six to seven (US) and seven (German), not a repeat-timing acceptance
claim. Exact raw observations and evaluations are `bench/keypad-repeat-{us,de}-*`.
All eight final integration commands exited zero: private sync/window search,
38 graphics cases, private headless Ekko, Nix flake check/build and Finix preview
build/evaluation. `bench/keypad-layout-integration-20260906-073835/manifest.json`
records exact commands and exits; `bench/keypad-layout-checkpoint.json` joins
source/binary identity, frozen gates, raw evidence and verified archive hashes.
The final binary SHA-256 is
`75913e60359daa8241a882a1c1f9da69af982682ec3a1b88d61edc187fa22e2d`, identical to
the candidate used for passing byte/repeat fixtures. Engine source is unchanged
from the prior keypad checkpoint.

Fresh private 318×89 Ekko PSS is 80.70–80.76 MB with listed compute allocation
331,350,016 bytes (316 MiB). The 78 MB target remains unmet. These short idle
samples establish neither zero wakeups nor zero GPU activity. No desktop access,
deployment, activation or result-link change occurred. Next revalidate current
grapheme behavior against the pinned references: the older cursor-gap report
predates the retained VS16 work and cannot alone identify current failures.
The full objective remains active and incomplete.

## Recovery: keypad increment validated and retained

Nix daemon access, an owned Unix-socket round trip and NVIDIA discovery passed
again after permissions were restored (`bench/access-keypad-recovery-20260906T070917.json`).
Old process handles were not reused. The original goal, frozen performance gates,
private-headless-only window testing and deployment restrictions remain in force.

The keypad increment adds GPU application-keypad state (ESC = / ESC > and private
mode 66), NumLock override mode 1035, reset behavior and host key encoding.
NumLock-off digit/decimal keys now navigate; NumLock-on keys emit numeric text.
Like both measured references, override defaults on, so applications must clear
1035 to receive application-keypad sequences. Navigation retains application-cursor
mode behavior. The host suppresses the duplicate GLFW text callback after handling
a keypad press. State stays in CUDA; no idle polling or GPU architecture change
was introduced. A small enum/table encoder reuses the existing navigation encoder;
merely mapping keypad Enter would leave the measured navigation/application gaps.

The current source hashes match `bench/keypad-validation.json`. Its Nix build
(including native input tests), VT test and two fresh private runs of each keyboard
fixture exited zero. Baseline reports preserve 9,384 key observations across both
terminal orders, default and disabled Foot font bindings. Candidate fixtures add
816 mode and 952 modifier observations. Every key has exact raw bytes and a unique
F12 sentinel; repeats agree. Initial geometry is 40×24; reference font shortcuts
can change geometry during modified-key runs, so it is not claimed fixed throughout.

`nix develop --command python3 bench/keypad_evaluate.py --output bench/keypad-evaluation.json`
exited zero. Frozen raw-report hashes agree. All 408 unmodified cases match both
Foot 1.27.0 and Monstar 1.1.0. All 299 required modified cases with nonempty
references match at least one reference. Two application Ctrl+Alt-minus cases
produce no reference bytes and remain unknown/local interception. Of 175 separately
reported numeric-text/Equal cases, 68 differ from at least one reference and six
match neither (numeric Ctrl+Alt plus/minus/multiply with NumLock off/on). The
encoder's unsupported numeric Ctrl fallback follows the measured Foot legacy
keysym form; this does not establish full modifier, keyboard-layout or keyboard
protocol parity. No input/display latency claim follows from these byte checks.

Raw reports, exact helper versions, pre-edit source archives, candidate patch,
frozen gates and evaluator output are under `bench/keypad-*`. All 13 sequential
integration commands exited zero: reference, Unicode, selection, reflow, search,
private sync/window search, 38 graphics cases, private headless Ekko, flake check,
standard build, Finix preview build and evaluation. Exact commands, exits and
source hashes are in `bench/keypad-recovery-integration-20260906-070947/manifest.json`;
`bench/keypad-checkpoint.json` joins the evidence. The retained package is
`/nix/store/nwnqnd0l1v0hgp5ppc2bdlybaasw1yqh-cudaterm-0.1.0`, binary SHA-256
`ca92a54878004d94f959eb2c03008568039865cb98fdb380b713d78d99bd04c8`.
Fresh private 318×89 Ekko samples report PSS 80.68–80.99 MB and listed compute
allocation 331,350,016 bytes (316 MiB). Three one-second parent samples contain no
CPU ticks; they do not establish zero wakeups or GPU activity. No performance target
has been relaxed; PSS remains above 78 MB, and the full objective remains incomplete.
Next input work is a bounded repeat/character-callback and non-US-layout fixture
before expanding protocol support; numerical performance gates remain open.

## Recovery: retained-history selection increment

Restored access was rechecked: Nix daemon information, an owned Unix-socket
round trip and NVIDIA RTX 4090 discovery all succeeded
(`bench/access-offviewport-recovery.json`). Previous background jobs were not
reused. All terminal windows remain on private headless Weston; desktop access,
GPU performance settings and deployment/result links are unchanged.

A new 40×24 comparator fixture places the beginning of a 1,200-letter ASCII word
above the viewport. Twelve pre-fix cases in both terminal orders show Foot and
Monstar copying all 1,200 letters on double-click, versus Cudaterm's 846-letter
visible suffix. Triple-click differs: Foot copies the visible suffix plus newline
(853 bytes), Monstar the full logical line (1,212 bytes), and Cudaterm the visible
suffix without newline (852 bytes). Raw screenshots, clipboard bytes, commands,
helper/binary hashes and repeated observations remain in
`bench/selection-comparators-history/` and its summary.

Word/Line endpoint expansion now follows retained soft-wrap metadata above and
below the viewport, stopping at retained-history bounds and hard breaks. Alternate
screen bounds prevent access to primary history. Copy extraction processes at
most one viewport per batch, preserving global newline/wide-padding decisions.
The smaller alternative—only widening endpoint bounds—would grow retained GPU
scratch with history length. The batched implementation avoids that allocation.
Review caught and corrected a draft's unsafe one-row allocation before any build;
that draft remains archived and was never run.

`nix build . --no-link` and `nix run .#selection-test` exited zero. New cases
exercise both viewport directions, exact Unicode bytes across short wide wraps,
hard breaks between batches, alternate isolation, cursor/view preservation,
ring eviction and all 4,096 retained rows. At 128×24, first-copy tracked device
allocation is bounded by 49,177 bytes; repeat copy adds none. The first fixture
incorrectly assumed alternate entry homes the cursor; its preserved failure and
diagnostic identify empty output versus expected ALT. Explicit CUP corrected the
test, consistent with existing VT coverage, without changing terminal behavior.

Eight private candidate clipboard cases pass through Nix: history word/line
outputs are exactly 1,200 / 1,212 bytes, matching Monstar for this fixture;
visible outputs remain 80 / 92 bytes. Exact expected bytes are asserted in
`bench/offviewport-clipboard-acceptance.json`. Reflow, search and independent
reference tests also exited zero (`bench/offviewport-final-validation.json`).

The old sync fixture failed its final blue capture on candidate and retained
binary: child write readiness plus 50 ms did not establish draw completion.
The retained binary's saved capture contains the complete previous green image
(32,768 pixels), with zero blue, in
`bench/offviewport-sync-baseline-capture/` and `offviewport-sync-baseline-colors.json`.
The initial candidate failure log is preserved; its temporary screenshot was
removed by the original fixture and is unavailable. The corrected fixture saves
every capture. Red/green retention assertions remain single-shot; final blue may
wait up to five seconds while only the complete previous green image is allowed.
Blank or partially blue frames still fail. This is functional frame completion,
not a physical display-latency measurement or a change to frozen performance gates.
Strict candidate and retained-baseline sync runs exited zero, as did window
search, all 38 graphics cases, private headless Ekko, flake check, standard build,
Finix preview build and evaluation. `bench/offviewport-integration-validation.json`
records commands, exits and source hashes; `bench/offviewport-checkpoint.json`
joins unit, clipboard, failure and integration evidence. Two candidate correctness
runs accidentally overlapped; their captures/logs remain, and no timing/resource
inference is drawn from them. The reliable pipefail rerun first captured complete
green, then complete blue. Subsequent GPU checks ran sequentially.

The final package is
`/nix/store/40cgcx894yfx355bcb6z6wd51wh3nq21-cudaterm-0.1.0`, application SHA-256
`e68bdf0dcc4181d5da00a8949ae27c63ec48e4fbeedee93fbce5d91a6dad1ad7`, identical
to the binary used for the passing unit and clipboard checks. Final private
318×89 Ekko idle samples report PSS 80.66–81.00 MB and listed compute allocation
316 MiB; PSS remains above 78 MB. No parent CPU ticks were observed in these
three one-second samples; this does not establish zero wakeups or GPU activity.

Full-goal targets remain unmet. This increment does not establish Unicode word
segmentation, full graphemes/shaping, drag/autoscroll or desktop clipboard parity.
The measured large-window PSS remains above the fixed 78 MB target; this
selection change has not been claimed to improve whole-window memory or throughput.
Earlier sections below describe their respective validated checkpoints.

## Logical-line triple-click copying validated from comparator evidence

The previous turn was progress: it measured feed-size tradeoffs and restored a
rejected bitmap candidate. This increment addresses a verified daily-use gap.
The settled private Wayland comparison runs both terminal orders and captures
exact clipboard bytes after double/triple clicks on a fully visible wrapped
ASCII line. All 12 cases pass readiness/geometry, marker calibration, clipboard
replacement, empty child input and clean terminal exit checks through Nix.
`bench/selection-comparators-summary.json` records that all three copy the whole
80-character word on double-click; Foot and Monstar copy the entire logical line
on triple-click, but Cudaterm 27k8 copies only its physical 40-character row.
Foot additionally appends a newline; Monstar does not. Screenshots/raw clipboard
files, commands and exact helper/binary hashes are retained. The first fixture
failed calibration during Weston's startup fade, preserved its failures, then
was corrected to wait for exact marker color with bounded retries.

`select_kernel` now expands Line-mode endpoints over existing visible soft-wrap
joins, stopping at hard breaks and viewport bounds. The change adds two bounded
walks and preserves Cudaterm's existing no-forced-final-newline policy. No parser,
CUDA raster architecture, feed limit or allocation policy changed. Meaningful
CUDA cases cover clicks from either wrapped row, reversed ranges, hard breaks,
wide-wrap padding, an actual history viewport, resize reflow and a full row with
no committed wrap. A new window-sync mode7 triple-clicks a wrapped continuation
and checks exact full-line clipboard bytes plus bracketed-paste framing.

`nix run .#selection-test` passes. Four candidate private comparison cases also
pass and now match Monstar's full logical-line bytes; double-click output is
unchanged (`selection-comparators-logical-line-summary.json`). Reflow, search
and independent reference test commands exited zero. Sync (including new mode7),
38 CUDA graphics cases and private headless Ekko presentation passed. Flake
check, final package build, Finix preview build and evaluation also exited zero.
No deployment or result-link changes occurred. The final package is
`/nix/store/y5wj6w516qli7r1n1dm5i8dwhhb67221-cudaterm-0.1.0`, application SHA-256
`5bd8ac3fd6ab7678347954c090e8cad4626e8fc825f706ea1231613457928d17`.
Final status/hashes are in `bench/logical-line-validation.json`.

The original window-search fixture failed on both candidate and restored 27k8:
it captured immediately after injecting Escape, before observing the redraw.
Failure logs/screenshots/traces remain in `logical-line-window-search-failure`
and `logical-line-window-search-baseline-failure`. The fixture now waits up to
five seconds for a newer `gl_texture_swap`, retaining its exact marker-coordinate
oracle and saving screenshots before assertions. It passes on both executables.
This orders the functional check; it is not a display-latency or transient-frame
quality measurement. The test-only repair leaves application bytes unchanged.

This is a visible-line copying increment, not full selection parity. Off-viewport
logical-line expansion, Unicode segmentation and further gesture/backend cases
remain open. Performance/resource targets remain unmet and unchanged. The full
objective remains active.

## Feed-size tradeoff measured; bitmap candidate rejected after fresh pairing

The previous goal turn was progress: host/event profiles narrowed raw graphics
cost to parser dispatch. This turn sends identical 2,802,391-byte raw RGBA wire
payloads through six fresh hosts at 4 KiB, 64 KiB, 1 MiB, then reversed sizes.
Each host has one warmup and four measured uploads; all 30 upload/delete checks
and six exits pass through Nix. `bench/image-feed-size-profile.json` retains raw
per-request timing and allocations; `image-feed-size-summary.json` validates
exact coverage and retains eight timing samples per size. Median upload times
are 4220.93, 1189.95 and 1114.05 ms respectively. The 1 MiB feed retains
61,585,102 device bytes versus 20,758,222 at 64 KiB; 4 KiB retains 18,206,414.
No feed limit changed. The modest larger-feed gain does not justify its workspace
increase against the outstanding memory target.

A separate candidate compacted graphics parameter presence flags from 128 bytes
to four words, cleared only flags at APC start, and checked continuation membership
with word masks. Values remained GPU-owned and guarded by presence flags. It
saved only 224 tracked bytes. Before edits, `bench/graphics-flags-gates.json`
froze a 10% raw median improvement and no worse p90/compressed timing against
existing measured gates, with no retained allocation regression. Full targets
and prior memory targets were neither changed nor declared met.

Candidate Nix build, flake check and all 38 CUDA graphics cases passed. Both
targeted protocol oracle runs exited zero: 17 cases matched restored replies,
terminal state and graphics allocations, including malformed continuations and
quiet-error ordering (`graphics-flags-oracle-comparison.json`). The initial
128-sample timing collection passed every frozen gate
(`graphics-flags-evaluation.json`). However, later hosts were substantially
faster than the first; that collection did not uniquely attribute the difference
to this implementation.

Before a fresh retained/candidate/candidate/retained raw RGBA collection, an
additional qualification froze the same 10% median improvement and no worse p90
against its paired retained samples (`graphics-flags-paired-gates.json`). All
36 upload/delete cycles and four exits passed, with 16 measured samples per
executable preserved. Candidate median was only 2.7% lower (ratio 0.972810), and
p90 was essentially unchanged (0.997895). Thus this qualification failed;
the original passing run and every paired sample remain on disk. Shared GPU
conditions were uncontrolled, so this is not proof of an exact causal gain.

The candidate is rejected. Both headers are restored byte-for-byte from
`bench/graphics{,_types}.before-flags.cuh`. Rejected source, patch, oracle,
raw timing and paired results remain under `bench/graphics-flags-*` and
`graphics{,_types}.flags-rejected.cuh`. Restoration build/flake status and hashes
are in `graphics-flags-validation.json`. Earlier work and result links remain
preserved. This measurement does not support implementing the bitmap solely for
the claimed speed target. Next quantify parser phase costs before more graphics
micro-optimizations, or proceed with the still-open comparator pixel/Foot Sixel
workflow and prioritized daily-use gaps. Full goal requirements remain unmet.

## Raw image transport profiled before another optimization

The previous goal turn was progress: fixed gates rejected the opaque reservation
candidate and exact source restoration passed. This increment changes no
production engine/flake bytes. `bench/image_chunk_profile.py` uses the existing
Kitty encoder and two fresh engine hosts, four RGB/RGBA raw/zlib variants, one
warmup plus four measured uploads per variant per host. Every 64 KiB F request
has raw offset/length/monotonic start/end timing. All 40 upload acknowledgments,
quiet deletions, zero post-delete image/transfer allocations and host exits pass.
`bench/image-chunk-profile.json` stores raw data, exact wire/helper/host/dependency
hashes; its summary retains per-image timing distributions.

Eight measured raw RGB uploads have median summed request time 897.80 ms across
33 requests; raw RGBA 1169.15 ms across 43. Median interior-request totals are
755.38/993.17 ms, so the cost is distributed through transport. Each compressed
upload fits one request (209.77/273.11 ms medians). These are harness request
intervals including IPC, not kernel or display timings.

A separate derived diagnostic engine (`bench/image-profile-engine.cu`) adds host
wall timers around existing preparation, history reservation, dispatch plus
request copy, and graphics service; it adds no CUDA synchronization. Repeating
the same sample plan gives median raw RGB/RGBA dispatch totals 740.33/996.58 ms
and service totals 134.89/153.93 ms. Each raw upload makes 11 service calls,
not one per continuation APC: the source already performs capacity-sufficient
continuation decoding inline, and output allocation occurs only at final
completion. Compressed uploads instead spend 197.84/254.08 ms in service.
`image-chunk-instrumented.json`, its stderr trace, and
`image-profile-host-summary.json` preserve all 820 matched feed/delete records.

A second derived engine (`image-profile-events-engine.cu`) adds CUDA events
around dispatch, read after the existing request-copy wait. Across 496 measured
full 64 KiB feeds with one dispatch and zero graphics-service calls, median host
dispatch time is 21.30 ms and CUDA event interval 16.25 ms. Median summed raw
RGB/RGBA event intervals are 617.49/788.66 ms. Events can include GPU scheduling
and host submission gaps; they are not exclusive SM instruction time or physical
display latency. Instrumentation perturbs timing and is not an acceptance run.
See `image-chunk-events.json`, its stderr trace and
`image-profile-events-summary.json`. Shared GPU scheduling was uncontrolled;
inherited `CUDA_DISABLE_PERF_BOOST=1` was preserved, not changed.

All three collections, both diagnostic compilations and summary evaluations ran
through Nix and exited zero. No window/EGL/raster workload was launched. Sources,
hashes and command status are in `bench/image-profile-{source,validation}.json`.
The new evidence prioritizes the GPU parser/dispatch path over repeated output
allocation or history shrinking. Next isolate fixed per-dispatch cost from
byte-dependent parsing using the identical wire stream at different feed sizes,
and profile parser phases before changing production code. Existing acceptance
and better-comparator targets remain unchanged and unmet.

## Access restored; opaque graphics reservation candidate rejected

Nix daemon access, a fresh AF_UNIX roundtrip, and NVIDIA access passed after
permission restoration. `nix run .#headless-test -- --ekko
/run/current-system/sw/bin/ekko --output-dir bench/recovery-transport-ekko`
exited zero on restored package 27k8 in private Weston; no desktop was used.
See `bench/recovery-transport-access.json` and the associated headless log.

The candidate kept graphics classification on the GPU and stopped opaque
transport before ordinary text, including text between continuation packets.
It moved speculative history reservation after classification, retaining normal
reservation for text and decoded-height reservation for scrolling placement.
Candidate Nix builds passed. `nix run .#graphics-test` passed 38 real CUDA
parser/decode/raster cases; the Nix-integrated transport test passed split
prefixes, cancellations, interleaved wrapped Unicode text, image allocation,
live cells/copying and pending UTF-8/partial-ESC boundaries. Flake check passed.
The first standalone test attempt loaded a CUDA stub; the Nix package used the
normal driver rpath successfully. This was not a restored-access blocker.

All 128 measured and 32 warmup upload/delete allocations in the separate
acceptance collection met the frozen 128-row/10,600,142-byte limits, with zero
image/transfer bytes after deletion. However, four of eight timing groups failed
`bench/image-reclaim-gates.json`: raw RGB/RGBA with and without the diagnostic H
callback. Median ratios versus the fixed gates were 1.083/1.158 without H and
1.061/1.114 with H; p90 ratios were 1.002/0.975 and 1.105/1.165 respectively.
All four compressed-image groups passed. No limits changed or samples were
removed. Shared GPU conditions remain uncontrolled, so this is acceptance-test
failure, not a unique causal attribution to the new guard.

`bench/opaque-guard-acceptance-cost.json` retains the separate collection, which
started after all agent-owned GPU correctness workers finished; collection and
Nix evaluation exited zero. `bench/opaque-guard-evaluation.json` records the
failed acceptance decision. The earlier `opaque-guard-cost.json` remains a
separate diagnostic because parent overlapped it with graphics correctness
work (`opaque-guard-cost-context.json`). The window-memory gate was not run
after the timing rejection.

The candidate is rejected. Exact pre-edit engine/flake bytes are restored;
`bench/opaque-guard-candidate.patch`, `engine.opaque-guard-rejected.cu`,
`flake.opaque-guard-rejected.nix` and `opaque-guard-rejected-test.cu` preserve
reviewable work. The transport test also remains untracked in tests, as it was
at recovery, and is not wired into the restored package. Earlier local work,
result links and Finix deployment were preserved. Final restored checks are
recorded in `bench/opaque-guard-validation.json`.

Next: profile raw graphics transport before another implementation attempt;
current evidence does not justify retrying either post-commit reclaim or this
per-dispatch guard unchanged. Pixel-observed comparator image workflows, Foot
Sixel, remaining lifecycle coverage and daily-driver gaps remain open. Full
performance targets are unmet and the goal is not complete.

## Image-history reclaim experiment rejected on timing gates

The previous increment attributed 10,158,080 unused history bytes after images.
This experiment froze `bench/image-reclaim-gates.json` before production edits:
post-delete engine bytes ≤10,600,142, empty history capacity ≤128, window listed
compute ≤246 MiB, and no worse pooled engine image-operation median/p90 in each
of eight mode/format groups. Full historical/better-comparator targets were not
changed. A fresh retained baseline contains 128 measured intervals plus 32
warmups across four hosts, with the diagnostic decode callback on/off in paired
order. The same sample plan was run on the candidate, with raw samples retained.

The candidate added `request.committed` to the existing post-request history
shrink condition, after GPU servicing and history-count refresh. Nix built
`/nix/store/qi0njjcck8rappcyf5q3wd4l221mqxfd-cudaterm-0.1.0` and the new
`nix run .#graphics-history-test` passed: wrapped Unicode history, nonzero view
position, live cells, viewport copy, search after reflow, empty-history capacity,
7-byte/large chunks and cursor-advancing image scrolling were preserved.

All candidate measured post-delete allocations met 10,600,142 bytes and 128-row
capacity. However, seven of eight timing groups failed their frozen median/p90
guards. The default-callback zlib RGBA median worsened by about 14.2% and p90 by
12.9%; other groups varied. `bench/image-reclaim-evaluation.json` records every
result. Shared GPU conditions were not controlled, so the comparison does not
uniquely attribute timing differences to allocator churn. It does fail the
predeclared acceptance test; samples were not discarded or thresholds relaxed.
The window-memory gate was not run after this earlier rejection.

The experiment is rejected and the prior engine/flake bytes are restored exactly.
The candidate patch, source, regression test and raw timing samples remain under
`bench/image-reclaim-*` plus `bench/engine.image-reclaim-rejected.cu` and
`bench/flake.image-reclaim-rejected.nix`. The experimental test is archived as
`bench/image-reclaim-rejected-test.cu`; it is not wired into the restored package
because its new memory requirement intentionally fails the original behavior.
Only this experiment's paths were restored; all earlier local work is preserved.

Restored `nix build . --no-link --print-out-paths` and `nix flake check` exited
zero. The package is again 27k8, with application SHA-256
`64937ea240ddc79b141a92eba017087130d6921ba7d877f7fd9048d73f043d56`.
Commands/hashes are in `bench/image-reclaim-validation.json`. Existing targets
remain unmet. The next memory approach should avoid reserving thousands of
history rows for GPU-identified opaque image transport, rather than repeatedly
allocating and freeing them after completion. This requires preserving genuine
scrolling and invalid/split parser behavior without introducing a CPU parser.
Image transfer profiling, pixels, Foot Sixel and combined multiwindow workflows
remain separate outstanding work.

## Image retention attributed to unused history capacity

The previous turn measured 14 MiB of retained window compute allocation after
image deletion. Four engine-host runs now repeat the same 1024×512 image variants
and exact wire hashes, fed in 64 KiB chunks, without EGL, rasterization or windows.
Two runs enable the existing diagnostic H decode callback, paired between two
default runs. All 32 upload/delete cycles pass and all four hosts exit zero.
Image and transfer allocations return to zero after every deletion in every mode.

Default and diagnostic decode paths give identical allocation totals: engine
bytes rise from 7,875,535 initially to 20,758,222 after deletion; NVIDIA compute
allocation rises from 230 to 242 MiB. History capacity rises from 128 to 4096.
Thus the separate interactive decode callback is not supported as the explanation
for this retained allocation. Its H callback differs from GLFW and includes
snapshot/mouse polling, so this is a controlled host-path comparison, not a
complete attribution of every window resource.

A separate exact-state/RIS probe proves history occupancy is zero before and
after image upload/delete. Reset reduces history capacity back to 128 and tracked
allocation to 10,600,142 bytes, releasing exactly 10,158,080 bytes:
(4096−128) × 80 columns × 32-byte Cell. NVIDIA's rounded listing falls from
242 to 232 MiB. Input/scan workspace remains above initial allocation, separately
from this unused history reservation. Source `Engine::enqueue_feed` calls
`reserve_history(n-offset)` before dispatch, and the reservation conservatively
budgets two potential rows per byte, including opaque graphics transport.

`bench/image-engine-memory.json`, `bench/image-engine-memory-summary.json` and
`bench/image-history-attribution.json` retain actual allocation/state counts,
image/wire hashes, process observations and callback reports. Collection,
summary validation and state attribution all ran through Nix and exited zero;
`nix flake check` also passed (`bench/image-engine-attribution-validation.json`).
Luna prepared the host probe; parent integration corrected wire packet size,
constructor arguments, missing initial/exit/provenance records and added paired
H-mode coverage. No production code changed.

This identifies a concrete optimization candidate: reclaim speculative history
capacity after a completed graphics request, using freshly returned history
occupancy and preserving every occupied row. Source review identifies allocation
churn and preservation of wrap metadata/nonzero viewport offsets as material
risks. Before editing production code, freeze retention gates from these samples
and capture repeated image-operation timing; then exercise real history and
selection/search across growth/shrink. Existing full performance targets remain
unmet and must not be relaxed. Window-specific residual memory, pixel validation,
Foot graphics, multiwindow combined workflows and daily-driver gaps remain open.

## Acknowledged image upload/delete window lifecycles

The previous turn qualified Kitty query replies from the actual Monstar and
Cudaterm builds. `bench/image_lifecycle_probe.py` now runs eight upload/delete
cycles in each of four fresh private Weston processes, in reversed orders.
Each sequence covers raw RGB, raw RGBA, zlib RGB and zlib RGBA twice, using
1024×512 solid images (1,572,864 or 2,097,152 decoded bytes). Payload generation
and retained wire buffers live in the separate child, outside parent accounting.
The images exceed the small viewport and may clip; no pixel verification is
claimed. Foot remains outside this Kitty workload pending a Sixel path.

All 32 uploads return the exact image/placement success reply. The same explicit
placement command succeeds before deletion and fails afterward: Monstar reports
`ENOENT: image not found`, while Cudaterm returns its generic `EINVAL` graphics
error. This verifies loss of a usable placement under that command, not exact
GPU allocation release. All 32 deletion checks, 80×24 geometries and four
parent/child cleanup checks pass. Raw/encoded image SHA-256 and byte counts
match the independent existing encoder in `tests/test_graphics.py`.

Cudaterm starts at 242 MiB NVIDIA compute allocation and retains 256 MiB after
every deletion in both orders: a 14 MiB process-level increase despite successful
protocol deletion. Final parent PSS is 82.302–82.314 MB, above the fixed 78 MB
gate. Monstar final PSS is 10.973–10.976 MB; some earlier delete samples are
about 13.995 MB. Its GPU memory remains unknown. These eight-cycle settled
samples do not establish peaks, long-term stability, allocation ownership, full
protocol compatibility or presentation. CUDA image/transfer accounting and
context/driver retention need separation using the same larger payloads.

Luna implemented the child protocol; parent integration corrected cursor-reply
coordinates versus ioctl geometry, ready-field names and delete indices, added
pre/post-delete placement checks, and verified wire bytes against the existing
encoder. The production application was unchanged. Collection and summary:
`nix develop --command python3 bench/image_lifecycle_probe.py` and
`nix develop --command python3 bench/image_lifecycle_summary.py` exited zero,
as did `nix flake check`. Raw results, summaries and command/hash records are
`bench/image-lifecycle-current/report.json`, `bench/image-lifecycle-summary.json`
and `bench/image-lifecycle-validation.json`.

Next attribute the 14 MiB residual with the same raw/compressed image sizes in
the engine host, add actual private-compositor image observation, and integrate
image/history/resize workloads with multiple windows. Foot's graphics protocol,
long soaks, daily-driver feature gaps and fixed performance targets remain open.

## Runtime graphics protocol qualification

The previous turn completed combined history/resize/reset evidence. Before
adding an image lifecycle comparator, `bench/image_protocol_probe.py` now runs
a one-pixel RGB Kitty query (`a=q,t=d,f=24,s=1,v=1,i=123`) followed by CSI 6 n
in six fresh private Weston terminal processes, using two reversed orders.
The reader accepts APC and CSI independently and waits up to three seconds;
no cursor reply alone is counted as image support. All six processes and their
children exit cleanly at the verified 80×24 grid.

Both Cudaterm and Monstar reply exactly `ESC_Gi=123;OK ESC\` (without the
explanatory space before ESC) followed by the cursor reply in both orders.
Foot replies to CSI 6 n but sends no Kitty reply during the bounded interval.
That absence is unknown Kitty support, not proof of unsupported protocol or
successful image handling. Foot's installed documentation identifies Sixel;
its image workload must therefore be qualified separately. Local source review
informed the query, while these replies establish behavior of the actual pinned
executables. No displayed pixel or retained-image assertion follows from a query.

`bench/image-protocol-current/report.json` preserves exact request/response hex,
commands, executable/dependency hashes, geometry, bounded observation duration
and cleanup. `bench/image-protocol-summary.json` validates both orders, exact
positive APC replies and the independent CSI barrier. The collection and summary
ran through `nix develop --command python3` and exited zero; `nix flake check`
also exited zero (`bench/image-protocol-validation.json`). Production code and
all existing targets remain unchanged.

Next run acknowledged raw/compressed RGB/RGBA uploads and image deletion in
Cudaterm/Monstar, measuring per-cycle retention and observing pixels separately.
Use meaningful image sizes within both implementations' limits, retain transfer
and image hashes, and do not treat parser completion as display or exact device
allocation release. Foot needs its own Sixel image path. Multiwindow combined
lifecycles, long soaks, remaining feature gaps and unmet targets remain active.

## Combined history, matched resize and reset lifecycles

The previous turn completed matched resize-only evidence. The same private
Weston helper now fills 10,000 Unicode/SGR lines (370,000 bytes) before each
40×32 → 318×89 → 80×24 resize cycle, then sends ED3/RIS and waits for CSI 6 n.
Six processes in reversed terminal orders each complete three combined cycles:
54 verified resize transitions, 36 history/reset acknowledgments, and six clean
parent/child exits. Large writes loop until the full payload is sent. No desktop
connection or production-code change was made.

`bench/resize-history/report.json` and `bench/resize-history-summary.json`
retain commands/provenance, geometry, byte counts, settled parent/child/compositor
resources and parent-only NVIDIA compute readings. CUDA baseline is 242 MiB;
each history fill is 256 MiB, each large resize 344 MiB, each return to 80×24
before reset 254 MiB, and each reset 245 MiB in both orders. The first/small
resize samples are 251, 249 and 251 MiB across cycles, also repeated in both
orders. The 3 MiB post-reset excess therefore differs from the prior resize-only
return to 242 MiB. Engine input/scan high-water storage was previously identified,
but these process totals cannot uniquely attribute the residual allocation.

After the third reset, parent PSS is 46.367–46.429 MB Foot, about 20.287 MB
Monstar and 81.363–81.436 MB cudaterm. These are decimal MB and are post-command
retention samples, not an assertion of equal reset/history semantics or a leak.
Cudaterm remains above the fixed 78 MB PSS gate. GPU memory for the comparators
is unknown; absence from NVIDIA's compute-process list is not zero.

The helper's exact pre-history source is preserved as
`bench/resize_geometry_probe_matched_baseline.py`, hash
`a617e35e435a6febd2cd75e51452203abec974d385864baad86a87005f9637f3`.
An extra trailing newline in the initial archive was removed only after verifying
that this restores the raw report's recorded hash; original results were unchanged.
Luna implemented child protocol support and parent integration completed the
control loop and summary checks after patch-context failures.

`nix develop --command python3 bench/resize_geometry_probe.py --matched-grids --history --output bench/resize-history/report.json`,
`nix develop --command python3 bench/resize_geometry_summary.py bench/resize-history`,
prior matched-run revalidation with its archived helper, and `nix flake check`
all exited zero (`bench/resize-history-validation.json`). This verifies bounded
short-run processing, geometry and cleanup; it does not verify reflow pixels,
equal history content, peaks, long-running stability or physical display latency.

Next integrate the verified resize/history path with multiple retained windows
and image upload/delete. Use explicit protocol handling and preserve unsupported
cases as unknown. Existing performance gates and remaining daily-driver gaps
are unchanged; the full goal is not complete.

## Matched-grid private resize lifecycle samples

The previous turn made progress by calibrating per-terminal resize geometry.
The helper now optionally requests terminal-specific pixel sizes and requires
exact shared PTY grids: 40×32 → 318×89 → 80×24, repeated three times in each
of six fresh processes across reversed Foot/Monstar/cudaterm orders. All 54
transitions and six parent/child clean exits pass. No user desktop was used.

The calibrated request formulas were verified by the runtime assertions: Foot
uses 9×cols by 16×rows+28; Monstar 10×cols by 15×rows; cudaterm 8×cols+8 by
16×rows+28. These formulas apply to this pinned compositor/font/terminal setup.
Matching cells does not make font pixels, decoration, rendering or history policy
identical. This workload contains geometry queries and resizing, not text/history
reflow assertions or image uploads. It supplies settled resource samples, not
latency, peaks or display evidence.

After the third return to 80×24, parent PSS across the two orders is 6.797–6.839
MB Foot, 19.667–19.668 MB Monstar and 79.074–79.123 MB cudaterm (decimal MB).
Cudaterm remains above the fixed 78 MB PSS target and the better comparator.
Its reported NVIDIA compute allocation repeats 241/302/242 MiB for the three
sizes in every cycle/order, returning to its 242 MiB starting value. Comparator
GPU values remain unknown. Traces repeat the mapped-buffer growth/shrink pattern;
these short observations do not prove long-term boundedness or full GPU ownership.

Luna prepared the matched mode and parent integration corrected tuple/list
comparison, per-case size validation and acknowledgment timestamp placement.
The original calibration helper is archived byte-for-byte as
`bench/resize_geometry_probe_calibration.py`, SHA-256
`509f3ff932e96378ba8cc42f50c1e5a8c159cd832ec2a6ef847721238f52abee`.
The initial archive had one extra trailing newline; restoring exactly the
recorded bytes allowed the original raw evidence to revalidate. Raw results
were not edited. New `ack_end_ns` samples receipt before settling, but still
include deliberate convergence polling and cannot measure display latency.

`nix develop --command python3 bench/resize_geometry_probe.py --matched-grids --output bench/resize-matched/report.json`,
`nix develop --command python3 bench/resize_geometry_summary.py bench/resize-matched`,
old-calibration revalidation with the archived helper, and `nix flake check`
all exited zero. See `bench/resize-matched-validation.json` for commands/hashes
and `bench/resize-matched-summary.json` for per-cycle samples.

Production code and acceptance targets remain unchanged. Next reuse these
verified dimension requests in combined history/resize and multiwindow lifecycles,
and add image upload/delete with protocol-specific handling; Foot documents Sixel,
while the current cudaterm/Monstar graphics path uses Kitty graphics. Unsupported
protocols must not silently count as successful image workloads. Full objective
requirements, including daily-driver gaps and unexplained timing regressions,
remain active.

## Private resize calibration and short lifecycle validation

The previous increment completed recovered redraw evidence. This increment adds
`bench/resize_geometry_probe.py`, using the verified functional seat and fresh
private Weston for each Foot/Monstar/cudaterm launch in two reversed orders.
All six parents/children exit cleanly after three small–large–small cycles each:
54 successful geometry transitions in total. No desktop connection was used.

The first prototype timed out because the parent omitted its child control
request. That result did not establish a comparator or compositor limitation.
Luna implemented the prototype; parent review/integration corrected the handshake,
repeated same-process cycles, geometry convergence and cleanup/provenance before
the successful run. `bench/resize-geometry-calibration/report.json` preserves
raw settled samples; `bench/resize-geometry-summary.json` validates them.

Requested dimensions 328×540, 2552×1452 and 648×412 produce, respectively:

| Terminal | First size | Large size | Final size |
| --- | --- | --- | --- |
| Foot | 36×32 | 283×89 | 72×24 |
| Monstar | 32×36 | 255×96 | 64×27 |
| Cudaterm | 40×32 | 318×89 | 80×24 |

All geometries repeat exactly across all cycles and both orders. This is
calibration and short lifecycle evidence, not a matched-grid resource gate.
Different cell/decorations prevent treating identical requested pixels as
identical terminal workloads. Content/reflow pixels are not verified here.

For cudaterm, baseline NVIDIA compute allocation is 242 MiB; each cycle samples
241 MiB at 40×32, 302 MiB at 318×89 and 242 MiB after returning to 80×24.
Both runs repeat those totals across all three cycles. Lifetime mapped-PBO
traces show 983,040 → 14,490,624 → 983,040 bytes for each large/small pair.
The first intermediate size retains 983,040 bytes because it is above the
half-capacity shrink threshold. GPU driver/backing ownership remains unknown.
Compositor descriptors are 50 after every close; this probe includes a control
FIFO and has no empty-before snapshot, so it does not prove a return to the
original descriptor baseline. All measured child processes are absent after exit.

`nix develop --command python3 bench/resize_geometry_probe.py` and
`nix develop --command python3 bench/resize_geometry_summary.py` exited zero.
`nix flake check` also exited zero; commands and hashes are recorded in
`bench/resize-geometry-validation.json`. Luna independently reviewed the final
report and repeated geometry/cleanup evidence.
The field `ack_end_ns` was recorded after settling; it is excluded from latency
claims. These snapshots are not peaks, presentation evidence, long-soak stability
or multiwindow resize routing. Production code remains unchanged; targets remain
unmet. Next use calibrated per-terminal dimensions to assert shared effective
grids, then integrate the validated resize path with multiwindow/history/images.

## Restored access and completed redraw-only validation

Recovery rechecked the Nix daemon, an owned Unix socket round trip and NVIDIA
access successfully (`bench/access-redraw-recovery.json`). The saved redraw run
was already collected; no old PID or background job was reused. New local work
and package links were preserved. A fresh Luna worker reviewed and corrected
parent-only GPU summation and complete trace/acknowledgment validation.

`bench/multiwindow-redraw/report.json` contains 12 private Weston groups, both
grids and reversed Foot/Monstar/cudaterm orders, with 36 clean parent/child exits.
Each window executes three cycles of 60 small background redraw updates followed
by reset. All 216 operation acknowledgments pass; compositor descriptors return
to 48 in every group after five seconds. This validates parser/geometry replies
and cleanup, not each update's visible pixels or identical reset semantics.

Three cudaterm parents have the same within-run NVIDIA compute allocation in
both orders: 726 → 729 MiB at 80×24 and 900 → 948 MiB at 318×89, comparing the
last idle sample with the first redraw before any reset. The first and third
reset retain those redraw totals. History fill is therefore not required for
part of the window-level increase. These figures do not identify its allocator,
backbuffer owner, or complete graphics VRAM. Prior history/reset totals of
738/1002 MiB remain higher, under a different workload/schedule.

The 12 cudaterm traces each record 184 lifetime `gl_texture_swap` events.
Command interval timestamps are absent, so these cannot establish per-update
presentation or physical display latency. Three-parent PSS rises by 3,182,592
bytes after the first redraw and another 1,216,512 bytes by the third reset in
all four cudaterm groups; a three-cycle observation does not prove a leak or
long-term boundedness. Raw evidence and limitations are retained in
`bench/multiwindow-redraw-summary.json` and
`bench/multiwindow-redraw/validation-restored.json`.

`nix develop --command python3 bench/multiwindow_summary.py bench/multiwindow-redraw`,
`nix develop --command python3 bench/validate_redraw.py`,
`nix run .#headless-test -- --ekko /run/current-system/sw/bin/ekko --output-dir bench/recovery-redraw-ekko`,
and `nix flake check` each exited zero. Fresh Ekko presentation passed entirely
inside private headless Weston, using the current 27k8 package. Logs/hashes are
listed in `bench/recovery-redraw-validation.json`. Production code was unchanged.

Targets remain unchanged and unmet. Next extend private window lifecycle evidence
to resizing with explicit geometry acknowledgments and safe surface targeting,
then image upload/delete. Exact window GPU allocation ownership, peaks, long
soaks and the outstanding daily-driver requirements remain open.

Resize preparation: the smallest approach is to resize each newly launched
private window before launching the next, then restore its starting geometry.
Opcode 770 affects keyboard focus only; do not assume focus or configure
completion from launch alone. Require bounded child geometry convergence and
verify earlier children's geometries remain unchanged. Reuse the verified
functional seat build with opcode 770 rather than assuming the older benchmark
seat implements it. Cudaterm's existing 328×540 outer-size fixture expects
40×32 cells; Foot/Monstar decoration/cell offsets still need direct calibration.
This is a prepared next step, not completed resize evidence.

## History memory attribution separates workspace from window costs

The previous turn was progress: the mapped-font experiment failed its gate and
was safely restored. This increment changes only `tests/memory_probe.cu` to
report engine-accounted device bytes, separately tracked raster-buffer bytes,
and samples after EGL interop release, history reset and raster release. Its
optional `--history` workload asserts that capacity reaches 4096 rows and
returns to 128, with zero image/transfer bytes. Those assertions concern the
named resources, not all engine workspace. Original probe source is preserved
in `bench/memory_probe.before-history.cu`.

Four Nix-run probes alternate no-EGL/EGL/EGL/no-EGL with the 128-byte stack limit
and three history/reset cycles. EGL is explicitly surfaceless on the NVIDIA
device; DISPLAY/WAYLAND_DISPLAY are removed, and no window/desktop is used.
A 370,000-byte single feed leaves 32,315,982 engine-accounted bytes after each
reset versus 10,538,831 initially. History capacity is restored, but input/scan
workspace remains sized for the largest feed. Source inspection of
`enqueue_feed`, `reserve_scan` and `memory_usage` identifies that high-water
policy; it is bounded by the existing 1 MiB input ceiling, not freed by RIS.

A separate four-host comparison uses the retained 055j2 engine-host with the
same payload, alternating whole-payload and 65,536-byte chunks. With terminal-
sized chunks, post-reset engine-accounted bytes are 13,263,438 and NVIDIA
compute allocation is 234 MiB, versus 32,315,982 and 252 MiB for whole feeds.
Both repeat identically across all three cycles/orders. This 19,052,544-byte
accounted difference shows why the large single-feed probe cannot directly
represent terminal memory retention. `bench/history-chunk-memory.json` retains
all stages; its host payload is outside the measured engine process.

In the direct probe, raster allocation adds 14 MiB to NVIDIA's rounded listing
and returns on release; destroying the engine lowers it to 220 MiB without
EGL or 226 MiB with EGL, about 2 MiB above the preceding context-only levels.
Surfaceless EGL does not reproduce the window swapchain. The earlier large-grid
windows increase about 34 MiB per parent after history/reset, whereas the
terminal-sized engine-only workload increases about 2 MiB. That difference
supports investigating window/GL allocation separately, but different rendering
and feed schedules prevent attributing it to a specific buffer/cache yet.

Exact commands, exits and raw hashes are in `bench/history-memory-probe-runs.json`;
`bench/history-memory-attribution.json` combines the validated stages and limits.
All four probe processes and four engine hosts exit zero. Unavailable NVIDIA
readings remain -1/null, never zero. These are synchronous stage measurements,
not peaks, process-owner attribution of aggregate load, or long leak tests.

The diagnostic package is `/nix/store/27k8jdw5qq57mikziji0n4qjrhhg04zc-cudaterm-0.1.0`. Its application bytes
are identical to provisional 055j2 (SHA256 `64937ea240ddc79b141a92eba017087130d6921ba7d877f7fd9048d73f043d56`).
Nix build and final flake check pass; package identity changed only because the
probe changed. Fixed targets remain unchanged and unmet.

Next compare private-window GPU allocation after repeated redraws without
history against the history workload, then extend resize/image lifecycle
coverage. Do not label all post-RIS retention a leak or change scan workspace
policy without measuring its repeated-workload cost.

## Font staging mapping experiment rejected

The previous turn was progress: it measured history/reset retention but did not
attribute the retained bytes. This increment tested one bounded host allocation
hypothesis from the earlier constructor-phase evidence. Before editing,
`bench/font-map-gates.json` required at least 1 MiB paired PSS and private-memory
reduction, while preserving the fixed 78 MB PSS target and other existing
performance/correctness requirements.

The experiment replaced temporary font-file vectors with read-only private
file mappings, released after the CUDA copies. Existing atlas/content validation
remained in the constructor. A new Nix-run loader test covered data preservation,
invalid/missing/empty/oversized files, descriptor cleanup after rejection, and
unmapping at destruction. The first build omitted the untracked header from
Nix's Git source; after including the new files, the candidate built and its
check phase passed (`bench/font-map-build-validated.log`/`.stderr`). Font assets
were assumed immutable during their short mapped lifetime, as in the Nix store.

The private idle mapping run used before/candidate/candidate/before ordering.
PSS reductions were only 224,256 and 258,048 bytes, and private reductions were
221,184 bytes in both pairs (216 KiB). Before PSS was 80,760,832/80,803,840 bytes;
candidate PSS was 80,536,576/80,545,792. Both reduction gates fail, and all four
samples remain above 78 MB. These are settled snapshots, not peaks or proof
that all constructor allocations explain retention. Full candidate Unicode,
Ekko and performance acceptance was not pursued after this failed memory gate.

The experiment was rejected, including its extra loader/test code. The complete
patch is retained in `bench/font-map-rejected.patch`, along with raw smaps,
commands and evaluation (`bench/font-map-idle-checks.json`,
`bench/font-map-evaluation.json`). Restoration verified that engine/flake edits
were limited to this experiment before restoring their backups. The original
vector loader and provisional coalescing checkpoint 055j2 are restored. Fresh
Nix build and flake check pass and resolve to 055j2
(`bench/font-map-restored.json`). Existing unrelated work is preserved.

The smaller retained implementation is justified by the measured sub-gate
benefit; mapped staging did not deliver the hypothesized material reduction.
Next separate engine-accounted allocations from CUDA/GL context/backbuffer
retention during the existing fill/reset workload, and continue the missing
resize/image multiwindow lifecycle stages. Fixed targets and the broader
daily-driver/Unicode requirements remain open; this rejection is progress,
not a completed-goal or global-blocker claim.

## Multiwindow history/reset retention

The previous turn was progress: it established one/three-window idle costs and
process cleanup. The same private runner now supports explicit history cycles
and post-close settling. The original idle helper bytes are preserved in
`bench/multiwindow_resources_idle_baseline.py`; pass that path as the summary
helper's second argument when validating the original baseline. Current runs
use explicit `--output`, `--history-cycles` and `--post-close-seconds` options.

The new run covers both grids and all three terminals in reversed orders,
36 parents/children total. Each of the three concurrent windows completes three
cycles of 10,000 short Unicode/SGR lines followed by ED3 and RIS, acknowledging
each operation with CSI6n. That is 108 history/reset cycles and 216 operation
acknowledgments. All geometry checks and exits pass. These acknowledgments
establish parser progress, not identical history-clearing policies or visual
correctness. There is still no resize or image-upload/delete workload here.

Three-parent PSS after the last reset is approximately 38.8 MB Foot, 21.8 MB
Monstar and 225.6 MB cudaterm at 80×24; at 318×89 it is 132.7 MB Foot, 81.6 MB
Monstar and 225.6–225.8 MB cudaterm. Cudaterm grows about 1.6 MB across the
three resets, mostly by the second/third cycle. Three cycles are insufficient
to prove a leak or indefinite stability. Raw per-process/child/compositor
stages remain available, rather than only these aggregate values.

NVIDIA compute allocation for the three cudaterm parents is 768 MiB after the
first small-grid fill and 738 MiB after reset; at the large grid it is
1122 MiB after fill and 1002 MiB after reset. Both rounds reproduce those
values. The earlier idle three-parent baseline was 726/900 MiB; reset does not
return the NVIDIA total to that idle level. The listing does not distinguish
engine allocations from CUDA/GL context, backbuffer or driver caches, so no
ownership/leak conclusion is established. Comparator graphics-device memory
remains unknown rather than zero.

After all windows close and a five-second settle, compositor descriptor counts
again return to 48. Compositor PSS still varies above its empty baseline,
including about 46–50 MB in large-grid Monstar groups, 26–39 MB for Foot and
0.18–4.38 MB for cudaterm. A longer settle alone therefore does not eliminate
all observed retention; reset semantics, renderer caches and allocator state
need separate attribution. Do not subtract these costs silently or label them
leaks from short snapshots.

Raw data is `bench/multiwindow-history/report.json`; validated distributions
and lifecycle/workload stages are in `bench/multiwindow-history-summary.json`.
Both old/new summary checks pass through Nix (`bench/multiwindow-history-checks.json`),
as do final build and flake check (`bench/multiwindow-history-validation.json`).
The application remains provisional 055j2, with unchanged fixed targets.

Next profile the concrete retained CUDA/GL and host allocations across fill and
reset, and extend the window workload to resize and image upload/delete. The
existing font constructor also still allocates transient atlas/width/offset
vectors; prior allocator-phase evidence identifies their lifetime, so a mapped
staging experiment is a bounded host-memory candidate once its before/after
gates are frozen. Preserve all font-data validation and CUDA architecture.

## One/three-window resource and cleanup baseline

The previous turn was progress: GPU telemetry located slow tabs timing in feed
spans without proving a candidate-specific cause. This increment fills an
independent resource evidence gap. `bench/multiwindow_resources.py` now records
one then three simultaneous same-terminal processes at both grids in two
reversed terminal orders, with fresh private Weston per group. All 36 terminal
parents exit zero and all known children are absent after reaping. Each of the
12 compositor groups returns to its original 48 descriptors after closing the
windows. No application source or acceptance limits changed.

At 318×89, aggregate three-parent PSS medians are 38.12 MB Foot, 78.58 MB Monstar
and 224.07 MB cudaterm. NVIDIA compute allocation for the three cudaterm parents
is 900 MiB; comparator GPU allocation is unknown, not zero. This exposes a
material multi-process cost rather than a parity claim. Parents, children and
compositor samples remain separate. Short post-close compositor memory differs:
large-grid Monstar groups are 55–64 MB above their empty baseline, while
cudaterm is near 0.1 MB. No leak/ownership conclusion follows from that snapshot.

`docs/multiwindow-evidence.md` contains the table and scope limits. Raw stages,
commands, geometry, GPU readings and cleanup checks are in
`bench/multiwindow-current/report.json`; validated statistics/provenance are in
`bench/multiwindow-current-summary.json`. Nix execution, summary, final build
and flake-check evidence is in `bench/multiwindow-invocation.json` and
`bench/multiwindow-validation.json`. The current app remains provisional 055j2.

Next extend these windows through history fill, resizing, graphics upload/delete
and repeated reopen/close stages, including a longer post-close compositor
settle to distinguish transient retention. Then profile attributable retained
allocations before changing resource policy. The 128-byte CUDA stack limit is
already present in Engine construction, so proposing that existing optimization
again would not advance the goal. Physical latency, full Unicode/grapheme and
remaining performance/daily-driver requirements remain open.

## Tabs diagnostic: slow feed spans correlate with aggregate GPU state

The previous turn was progress: it retained all variable tabs samples and
measured idle thread/memory behavior. This diagnostic adds six alternating
before/candidate rounds with exactly one traced launch and 200 barriers per
variant/round (2,400 samples). One launch per trace avoids overwriting earlier
launch traces. `bench/coalesce-tabs-trace/` retains raw PTY and phase files;
`bench/coalesce-tabs-telemetry.jsonl` records concurrent aggregate NVIDIA
telemetry with receipt monotonic/realtime timestamps. Only the owned telemetry
process was stopped. No user-desktop windows or processes were manipulated.

The large slowdown reproduces for both executables. Later before/candidate
median barriers are 19.170/20.388 ms, followed by candidate/before
20.696/31.247 ms. Corresponding median feed-phase overlaps are
13.114/14.068/14.445/22.835 ms. Faster rounds have approximately
0.375–0.521 ms barriers and 0.266–0.384 ms feed overlaps. High-latency rounds
coincide with 100% aggregate GPU utilization and reported SM clocks falling
through roughly 855–540 MHz; most faster readings are 1–10% utilization at
about 2520–2580 MHz. Exact ranges and each sample's phase intersections are in
`bench/coalesce-tabs-telemetry-summary.json`.

This locates much of the variable cost in feed spans, which include host/device
transfers, synchronization and terminal processing. It does not identify the
GPU workload owner, prove a throttling cause, or separate kernel execution from
waiting. Device utilization uses coarse internal averaging; receipt timestamps
are approximate. One fast launch has no in-interval telemetry sample, recorded
as null. Synchronous tracing and telemetry can perturb timing. These results
are diagnostic, not new acceptance limits or filtered replacement benchmarks.

All 12 diagnostic launches exit zero, phase arithmetic and source hashes
validate through Nix, and final build/flake check pass
(`bench/coalesce-telemetry-validation.json`). Main application source remains
055j2, still a provisional coalescing experiment. Current evidence does not
isolate a consistent tabs regression attributable to it, but also does not
prove regression-free acceptance or meet the fixed performance targets.

Next fill the independent one/three-window resource and lifecycle gap on
private Weston, recording per-process and compositor memory, descriptors,
owned-child exit and aggregate GPU context alongside telemetry. Keep parser,
submission, compositor observation and physical latency scopes separate.
Further timing acceptance needs comparable GPU conditions or controlled
concurrent-load experiments; do not change system GPU clocks, disturb other
workloads, discard slow samples, or treat this as a global goal blocker.

## Coalescing follow-up: tabs variability and idle evidence

The prior turn made progress by implementing and validating a provisional
coalescing candidate. This follow-up preserves that candidate at 055j2 while
checking unresolved effects. No application source changed in this increment.

`bench/coalesce-tabs-paired/` adds 720 uninstrumented tabs barriers: six
alternating before/candidate rounds, each with one warmup and three measured
launches of 20 intervals. All samples remain in the report. The first-round
before/candidate medians are 14.959/21.324 ms; later rounds span approximately
0.387–1.591 ms. The direction changes across rounds. Neither a stable gain nor
regression is established, and there was no concurrent GPU-load/clock record
to attribute these outliers. `bench/coalesce-tabs-paired-summary.json` preserves
the pairs without filtering or post-hoc target changes. Next collect aggregate
GPU clock/load alongside paired feed/render traces rather than repeat the same
uninstrumented timing comparison or infer a cause from timing alone.

Four separate three-second instrumented idle intervals (before/candidate/
candidate/before) show zero main-thread context-switch and CPU-tick deltas and
no draws overlapping the interval. This is resolution-limited evidence, not
zero CPU usage or zero process wakeups. The cuda-EvtHandlr thread has 426–724
voluntary switches per interval, and another thread has 29–30. Thread names
alone do not establish exact allocation/driver cost ownership.
`bench/coalesce-idle-summary.json` retains every thread delta and raw hashes;
commands/exits are in `bench/coalesce-followup-checks.json`.

Four additional settled 80×24 process mapping samples show candidate PSS
82,184,192 bytes in both observations and private memory 71,544,832 bytes.
Before PSS is 82,194,432 then 81,527,808 bytes; private clean sharing changes
in the latter sample. RSS is 122,449,920 bytes in all four. These samples do
not establish a memory reduction; the fixed 78 MB PSS target remains missed.
Raw smaps/rollups and executable identity are preserved in
`bench/coalesce-idle-maps-*`; `bench/coalesce-idle-maps-checks.json` records the
Nix commands. GPU memory/utilization, peaks, long soaks and compositor/child
resource totals were not measured by this idle helper.

Nix summary validation, build and flake check pass
(`bench/coalesce-followup-validation.json`). Candidate acceptance remains open:
visible-marker delivery improves and functional checks pass, while fixed
performance targets, tabs attribution and the broader resource/daily-driver
requirements remain unresolved. Other evidence gaps may proceed independently
of this benchmark uncertainty; this is not a global blocker.

## Bounded input coalescing — provisional candidate 055j2

The previous trace turn was progress: it identified a render between partial
feeds followed by an approximately 8 ms deadline wait. `src/main.cu` now tests
whether more PTY input is immediately available before an eligible draw. It
continues feeding only within a one-millisecond coalescing budget, services
GLFW events between feeds, and bypasses coalescing for explicit synchronized
update boundaries. There is no added wait for input and no larger buffer.
The budget limits deferral decisions; it does not preempt a CUDA feed already
running or bound driver calls. CUDA parsing/state/rasterization are unchanged.

Before this edit, `bench/coalesce-gates.json` froze additional parser and
capture-completion median/p90 limits from the better comparator in the
uninstrumented persistent baseline. Existing historical, PTY and resource
limits remain unchanged. The prior main source is preserved in
`bench/main.before-coalesce.cu`, with the isolated edit in
`bench/coalesce-candidate.patch`. The candidate store is
`/nix/store/055j2d1lxshypp94yw0hiviwkjbr31bl-cudaterm-0.1.0`;
vjw4 remains the before checkpoint. This is a provisional worktree experiment,
not performance acceptance, a push or a Finix activation.

The 120-marker three-terminal run (`bench/paired-visible-coalesce/`) reduces
loaded cudaterm capture-completion medians from 27.844/27.820 ms to
11.492/11.313 ms at small/large grids. Parser medians fall from 1.381/1.340 ms
to 0.727/0.898 ms. The marker-only parser results and several fixed limits
still miss (`bench/coalesce-visible-evaluation.json`). The 1,723- and
1,725-line boundary-adjacent runs each capture all 120 measured markers;
all 20 loaded cudaterm samples in each run appear on the first capture.
These are capture-paced framebuffer observations, not physical display/input
latency. Exact commands and Nix exits are in `bench/coalesce-checks.json`.

A diagnostic 64 MiB continuous write in two reversed before/candidate orders
shows 27–29 submitted frames during 232–250 ms, with maximum gaps around
9.01–9.06 ms for both checkpoints (`bench/coalesce-sustained/report.json`).
This verifies bounded frame delivery for that short write, not a long soak,
physical presentation or full memory-lifecycle acceptance.

Both the candidate and a fresh retained checkpoint completed separate
900-barrier PTY matrices (`bench/coalesce-pty-summary.json` and
`bench/coalesce-retained-pty-summary.json`). Small-grid tails/tabs and fixed
historical targets remain unmet. The fresh retained large-grid ANSI median
is 0.480 ms versus candidate 0.498 ms, rather than the much older 0.336 ms;
sequential full matrices alone do not isolate small changes from drift.
A focused alternating comparison adds 720 samples (three workloads, both
orders, three measured launches with 20 barriers each). ANSI and DEC-graphics
candidate medians improve in both orders. Tabs medians are 0.507→0.503 ms in
one order but 0.407→0.496 ms in the other (`bench/coalesce-focused/report.json`).
That unresolved variation prevents a claim of regression-free acceptance.
Its 20-barrier distribution is separate from the five-barrier full matrix.

Synchronized graphics/clipboard/input/child-exit tests, headless history search,
explicit Ekko graphics and flake check pass on the candidate. Final build,
Finix checks and exact executable/source hashes are recorded in
`bench/coalesce-final-validation.json`; summary validation is in
`bench/coalesce-summary-checks.json`. Helper snapshots preserve prior raw
hashes: use `paired_visible_probe_coalesce_baseline.py` for the candidate's
original paired report and `paired_visible_probe_persistent_baseline.py` for
the persistent before report. Current helper accepts `--cudaterm` and
`--load-lines` for explicit candidate and boundary cases.

Next resolve tabs variability with paired feed/render attribution and evaluate
idle/wakeup resource effects before accepting or reverting this candidate.
The visible improvement supports continued investigation, but does not erase
fixed misses or prove the full daily-driver/Unicode/multiwindow requirements.

## Feed/render/capture correlation identifies early partial rendering

The previous observer increment was progress: its capture counts exposed a
repeatable visible-marker delay. The new `--trace` option records cudaterm's
existing synchronous phase trace per launch while preserving parser and
capture timestamps. `bench/paired-visible-trace/` contains a completed two-order,
two-grid three-terminal run. This instrumented run is diagnostic, not a new
performance acceptance baseline. The prior helper is preserved as
`bench/paired_visible_probe_persistent_baseline.py` for hash-matched reproduction.

`bench/paired_trace_summary.py` correlates all 20 loaded cudaterm samples.
Every one contains a texture/draw/swap between the first feed and the final
feed; every next post-reply swap starts 7.759–8.222 ms after the reply. In 18
samples the first feed fills the 65,536-byte buffer, leaving 10 or 11 trailing
bytes. Two others split earlier (9,728/55,819 and 56,832/8,715 bytes). The trailing
marker and CSI6n are therefore parsed after an already-submitted partial update.
The next update waits for the 8.333 ms deadline set after that swap. This
correlation explains a controllable contributor to the measured delay; it does
not attribute all compositor timing or establish physical display latency.
Raw selected events and source hashes are in
`bench/paired-visible-trace-analysis.json`.

Next implement a bounded input-coalescing experiment before rendering an
unfinished burst, with a time bound that still presents under sustained output
and preserves explicit synchronized-update boundaries. Merely enlarging the
64 KiB buffer would not cover the two earlier partial reads and would shift the
boundary for larger output. Freeze experimental comparison limits from the
uninstrumented persistent baseline before edits, while retaining all existing
PTY, resource and historical limits. Validate both parser barriers and observed
markers, boundary-adjacent payload sizes and sustained-output frame delivery;
reject a parser-only improvement that worsens visible output or fairness.

## Persistent private-compositor capture observer

The prior paired-marker turn was progress: it established visible marker
correctness but found that PNG screenshots were too slow to assess rendering.
The new test-only `bench/capture_observer.c` uses the pinned Weston 16 capture
protocol and a persistent SHM buffer. It records capture request, completion
callback and pixel-count completion separately. `nix/capture-observer.nix`
builds it through Nix from the pinned protocol XML. It requires the runner's
explicit private socket name; the runner supplies a fresh private runtime
directory and removes DISPLAY. The terminal application remains unchanged.

The persistent run repeats 12 launches and 120 measured markers plus 12 warmups
across both grids, both terminal orders and all three terminals. Every marker
was observed and every owned client exited zero. Exact commands, observer hash,
raw timestamps and color counts are in `bench/paired-visible-persistent/report.json`.
`bench/paired-visible-persistent-summary.json` validates executable identities,
geometry, counts and timing arithmetic. `bench/capture-observer-validation.json`
records Nix build, both old/new summary checks, flake check and the display-name
rejection check. Original screenshot helper bytes are archived in
`bench/paired_visible_probe_screenshot.py`; pass that path as the summary
helper's second argument when reproducing the old screenshot report.

Median capture-request-to-completion is 11.076 ms; full-output pixel counting
adds a separately measured median 4.540 ms. Unlike the PNG path, this exposes a
repeatable scheduling difference: 19 of 20 loaded cudaterm samples require two
captures to observe the new color, across both grids/orders. All 40 loaded
Foot/Monstar samples need only one. Counts/attempts are preserved in
`bench/paired-visible-persistent-attempts.json`. Loaded cudaterm write-to-capture
completion medians are 27.844/27.820 ms at small/large grids, versus Monstar
11.327/11.324 ms, despite cudaterm parser medians of 1.381/1.340 ms. In the
second large-grid Foot launch, even first-attempt captures take about 28 ms;
this variance must remain visible rather than being filtered away.

Capture requests follow parser replies and cause compositor work; callbacks
include scheduling and framebuffer transfer. The probe does not measure first
presentation, physical scanout or input latency. Pixel counting delays retries
and sample pacing, and a missed capture is not an exact display timestamp.
Nevertheless, the repeated missing-color first captures change the next
profiling action: trace cudaterm feed completion and texture/swap submission
against these capture timestamps, including the 8.333 ms frame deadline and
partial reads. Keep all better-comparator/historical limits unchanged and
measure both parser and visible-marker outcomes before retaining any scheduling
change. Full goal completion remains unproven.

## Paired parser and visible-marker probe

The previous turn made progress by restoring the rejected experiment and
validating the retained application. This increment adds
`bench/paired_visible_probe.py`: a private Weston-only runner for all three
pinned terminals, 80×24 and 318×89 grids, two reversed launch orders, and
zero-load/1,724-line ASCII cases. Each launch has one warmup marker and ten
measured markers. The child records a CSI6n reply timestamp, then keeps the
marker alive until the parent captures enough pixels of its distinct color.
Every marker alternates color, preventing reuse of the immediately prior frame.
All 12 launches exited zero; all 120 measured markers and 12 warmups were
captured. PNGs, exact commands, payload hashes, parser/capture timestamps and
capture attempts are retained in `bench/paired-visible-current/`.

`bench/paired_visible_summary.py` validates geometry, timestamp ordering,
payload-independent sample counts, executable-run records and every saved PNG
hash. It produces `bench/paired-visible-current-summary.json`; Nix invocation
results and environment provenance are in `bench/paired-visible-validation.json`.
The application is unchanged at vjw4. No performance targets were relaxed.

This observation path is too slow for render-scheduling acceptance: pooled
capture-completion medians are about 352–371 ms, including screenshot startup,
compositor scheduling, transfer and PNG decoding. Those stages were not timed
separately, so their individual costs are unknown. Parser medians are
0.054–2.746 ms. Marker-only cudaterm medians are 0.353/0.413 ms at the two grids,
versus Foot 0.054/0.069 ms. Loaded cudaterm medians are 1.559/1.616 ms versus
Foot 0.707/1.773 ms, with a 4.267 ms large-grid cudaterm p90. These small,
capture-paced samples include a full-screen color/erase marker and are not the
prior throughput workload or proof of display competitiveness.

The marker replaces the preceding load pixels. Capture starts after the reply,
so its completion is an upper bound, not first presentation or physical scanout.
This closes a narrow visible-final-output evidence gap and demonstrates that the
current screenshot observer cannot resolve the scheduling differences under
investigation. Next profile/separate observer stages and implement a persistent
private-compositor frame observer before another scheduling change. Keep the
same marker verification and report parser, submission, compositor observation
and physical display evidence separately. Full resource/multiwindow matrices,
remaining daily-driver gaps and fixed performance targets are still open.

## Query-redraw experiment rejected; restored checkpoint

A GPU-derived redraw hint was implemented and passed the CSI regression and
seven relevant CUDA suites through Nix (`bench/query-redraw-core.json` and
`bench/query-redraw-csi.log`). It conservatively retained redraw for selection
invalidation, mixed output and interrupted UTF-8. A separate private Weston
matrix collected 900 barriers with the same two grids, workloads and reversed
terminal orders (`bench/query-redraw-pty-matrix.json`).

The candidate did not meet the existing targets. Small-grid text, ANSI and
Unicode p90 and tabs median still miss the frozen contemporaneous limits;
large-grid Unicode median also exceeds the historical limit. Most pooled
medians increased. `bench/query-redraw-evaluation.json` records rejection.
`bench/query-redraw-gates.json` materializes limits from the already recorded
baseline; this file was made after implementation but before candidate runs,
and does not change those earlier limits. Historical small-grid figures remain
scope-mismatched references, not matched acceptance gates.

The first-interval median fell from 1.355 to 0.708 ms, but the second interval
now has a 0.956 ms median. A single instrumented burst confirms rendering can
move into the second pending reply: 0.521 ms overlaps texture upload/draw/swap.
This is diagnostic phase overlap, not isolated causal attribution or physical
display latency (`bench/query-redraw-burst-analysis.json`). The helper's five
parser barriers can finish before the next frame deadline. Further scheduling
experiments therefore need joint parser and frame-submission evidence and a
visible final marker, rather than acceptance from the first reply alone.

Recovery found that the earlier restoration failed on Nix's nested derivation
JSON format. The rejected five-file patch is now preserved in
`bench/query-redraw-rejected.patch`; only those files were restored from the
verified vjw4 Nix source. Pre-experiment source hashes are in
`bench/query-redraw-before.json`. Fresh daemon, Unix bind/listen and NVIDIA
checks succeeded (`bench/access-query-restoration.json`). Restored `nix build . --no-link --print-out-paths`, `nix flake check`,
`nix run .#sync-test`, `nix run .#window-search-test` and the private
`nix run .#headless-test` with explicit Ekko all exited zero. Exact commands and
log hashes are in `bench/query-redraw-restored.json`; binary/source identity is
in `bench/query-redraw-restored-identity.json`. These checks establish the
retained checkpoint, not completion of the outstanding performance targets.
No desktop benchmark, push or Finix activation was performed.

Benchmark CLI support is retained. The original matrix helper is archived as
`bench/current_pty_matrix_baseline.py`, matching the baseline's recorded hash.
To reproduce its summary, run `nix develop --command python3
bench/current_pty_summary.py --matrix bench/current-pty-matrix.json --helper
bench/current_pty_matrix_baseline.py --output <new-summary.json>`. Candidate
summaries instead use `--helper bench/current_pty_matrix.py`; new matrices accept
`--prefix <unique-prefix> --cudaterm <store-executable>`. Existing evidence is
preserved. Overall performance and daily-driver completion remain open.

## Current three-terminal PTY matrix and query redraw diagnostic

The current vjw4 executable completed the full five-workload, two-grid private
PTY matrix in both terminal orders: 900 measured barriers, 180 measured launches
and 60 warmup launches. `docs/current-pty-comparison.md` contains the table and
scope limits; `bench/current-pty-matrix.json` and `bench/current-pty-summary.json`
retain exact commands, hashes, geometry, raw samples, per-launch and per-round
statistics. All large-grid matched median/p90 checks pass in both orders, while
small-grid tails and tabs remain behind. Historical limits are unchanged and
remain unmet for four of five large-grid workloads. No parity is claimed.

A first-interval pattern changed the next profiling action: all 60 first cudaterm
intervals exceed 1 ms, versus four of 240 later intervals. An instrumented launch
shows 0.560 ms texture/draw/swap overlap in the first 1.131 ms barrier, immediately
after the helper's initialization cursor query. `bench/current-pty-burst-analysis.json`
records exact phase intersections and raw hashes. The query feed marks the app
dirty despite no ordinary cursor-query screen mutation; selection invalidation
and search generation side effects must also be examined before skipping redraw.
The CUDA-derived nonvisual-feed experiment below was subsequently rejected.
Next measure parser completion and frame submission together before changing
render scheduling; the evidence does not support an assumed one-millisecond timer.
Full memory, display latency, grapheme and lifecycle requirements remain open.

## VS16 lookup experiment and retained-engine lifecycle

A binary-search predicate was tested against both the retained linear vjw4
checkpoint and the pre-VS16 bhsg checkpoint. `bench/vs16-binary-cost-raw.json`
contains 96 engine-host launches in two reversed orders, with the same grids,
payloads, 20 warmups and 30 samples per launch. The raw file identifies all three
executables. Candidate Unicode tests passed through Nix. Several affected median
barriers improved roughly 3–7% versus the contemporaneous linear variant, but
other results were mixed and 23 of 32 checks still exceeded a frozen limit
(`bench/vs16-binary-evaluation.json`). The gate file SHA remains
`a025761d5ef4ed7cb09d1e513220775b86c591216d00f90f9da2a59a429391aa`.

The binary-search change was rejected and only that header edit was restored;
`bench/vs16-binary-rejected.patch` preserves it. Production retains vjw4 and its
correctness fixes, including styled inline VS16 support. Final restored build
and flake-check exits, source hashes and executable identity are in
`bench/vs16-lookup-restored.json`. Performance acceptance remains open.

The retained engine then passed `nix develop --command python3
tests/test_lifecycle.py --host <vjw4>/bin/cudaterm-engine-host --cycles 5
--processes 3 --output bench/vs16-retained-lifecycle.json`. The actual argv/store
is available in the saved invocation and the report's host field. Across 15
cycles and three fresh processes, each cycle writes 5,000 lines, confirms the
4,096-row history bound, resizes to 318×89 then 40×12, uploads RGB/RGBA graphics
(raw and compressed cases), verifies every 64×32 image pixel, deletes the image,
and resets/resizes to 80×24. All owned hosts exited.

After every cycle, engine-accounted device allocations returned to 10,600,142
bytes with history reservation 128 and zero image/transfer bytes. Post-cycle
PSS was 56,897 KiB and private host memory 52,868 KiB in all 15 observations.
Raw stage samples and summary hashes are in `bench/vs16-retained-lifecycle.json`
and `bench/vs16-retained-lifecycle-summary.json`. These are engine-host lifecycle
samples, not full terminal-window memory, total device/context memory or true
instantaneous peaks. The payload is the existing ASCII/history/graphics corpus;
this does not prove a long-running VS16 or full-grapheme soak.

Next update the current three-terminal PTY/resource comparison and profile the
remaining styled overhead, preserving the existing limits. Full window lifecycle,
physical display latency, grapheme/shaping support and several fixed performance
targets remain incomplete; none is promoted from this bounded engine evidence.

## VS16 styled-output cost — material regression found

The new `bench/vs16_cost_probe.py` uses the existing CUDA engine-host transport,
without a window or compositor. It measures wall time around a complete F
feed/reply operation, not a PTY, renderer or display event. Two reversed rounds
cover four workloads, two payload sizes and both grids, with 20 warmups and 30
raw samples per launch: 64 launches in `bench/vs16-cost-raw.json`.
`bench/vs16-cost-summary.json` records paired comparisons. The original helper
bytes are preserved as `bench/vs16_cost_probe_baseline.py`; its SHA matches the
raw record before CLI support was added for separate candidate/output paths.

The wcp2 candidate's all-VS16 styled fallback causes a clear regression: 64 KiB
VS16/SGR-VS16 median feed barriers are 237–320 times the prior bhsg checkpoint in
both run orders, roughly 47–60 ms rather than about 0.2 ms. This changes the next
action: correctness alone is insufficient to retain that fallback as finished
work. These engines share the desktop GPU but create no desktop windows.
Before/after allocation and proc-memory snapshots are diagnostic stages, not
instantaneous peaks or full terminal resource acceptance.

Before editing the styled implementation, `bench/vs16-styled-gates.json` froze
median/p90 ceilings per grid, size and workload from the larger corresponding
bhsg observation across the two rounds. The full better-Foot/Monstar targets
remain separate and unchanged. No ceiling comes from the slower candidate.

The revised candidate recognizes a complete inline sanctioned base+FE0F sequence
in layout and painting. Suffixes requiring prior-feed state still reject the
styled line before commit. The scalar parser remains CUDA-based and keeps eager
promotion. Existing whole-versus-byte tests cover inline sequences; a new
large suffix-start/history search regression checks the prior-feed case. The
revised candidate uses package vjw4; its new paired run is
`bench/vs16-styled-cost-raw.json`, with per-launch medians in
`bench/vs16-styled-paired-summary.json`. The 64 KiB affected workloads now take
139.7–232.0 microseconds across both grids and rounds, rather than the former
47–60 milliseconds. Against the contemporaneous bhsg control, affected medians
are still about 2–10% higher; smaller workloads also retain overhead.

`bench/vs16-styled-evaluation.json` reports 25 of 32 candidate checks exceeding
at least one frozen median/p90 ceiling, including some control-workload tails.
The exact limits are unchanged. This removes the catastrophic fallback cost but
does not pass performance acceptance. The experimental implementation remains
in the worktree for further measurement and correction, with no push or activation.
Next profile the remaining inline predicate/layout overhead and resolve control
tail variability, then repeat the same frozen evaluation. Full terminal memory,
PTY/compositor/display comparison and broad lifecycle requirements remain open.

Final Nix/integration commands and current source hashes are recorded in
`bench/vs16-styled-checks.json`; complete validation requires every listed command
to exit zero. All 13 commands exited zero, current source/binary hashes match,
and Finix's nested desktop assertion list is empty with integration guards intact.
These checks do not substitute for the failed performance gates.

## VS16 presentation candidate — implementation and validation

The review candidate promotes an already emitted, eligible scalar when its
immediate FE0F suffix arrives. It preserves base and suffix UTF-8 in the existing
Cell representation, creates a valid wide pair, relocates a final-column base
with soft-wrap metadata, and queues padding edits before bottom-scroll history
copies. Insert mode shifts the additional cell and preserves a populated next
row on wrap. There is no delayed-output buffer or Cell-size increase.

The qualifying predicate is generated from the exact Unicode 17 variation
sequence data in `data/emoji-variation-sequences-17.0.0.txt`, with Unicode's
license retained beside it. `bench/vs16-data-provenance.json` records independently
verified download hashes; Nix checks that the header ranges match the data.
Styled lines containing FE0F fall back to the CUDA streaming path before commit.
Search-prompt layout uses the same predicate before truncation. The affected
styled-path performance cost is unmeasured and must pass the unchanged gates
before performance acceptance.

New CUDA regressions cover immediate base output, all byte splits, narrow and
last-column wrapping, exact UTF-8 copy/search, reflow, bottom scrolling, insert
mode, repeated selectors, unsupported bases and styled-versus-scalar feeds.
Prompt pixels verify placement of a following ASCII character. The first
candidate i2bj passed these initial suites, private sync/Ekko, Finix evaluation
and flake check; final review added a wrapped-insert fix and its regression.
`bench/vs16-checkpoint.json` tracks the final checkpoint's actual commands,
exits and source hashes; earlier logs are not substituted for that checkpoint.

The first candidate's private-compositor probes matched Foot and Monstar for
heart/keycap width and all tested margin conditions; raw paths and hashes are
in `bench/vs16-comparator-summary.json`. Its three launch width run remains a
functional sample, not a performance distribution or visual-shaping proof.
The final wcp2 checkpoint passed all 13 recorded commands: build, seven CUDA
suites, private sync/Ekko, Finix build/evaluation and flake check. Source hashes
still match the checked files; executable hashes are in
`bench/vs16-checkpoint-binaries.json`. Final comparator results follow in the
companion `bench/vs16-final-comparator-summary.json`.

Limitations remain explicit: right-edge cursor clipping with autowrap disabled
requires better preceding-cell tracking, so this case retains existing scalar
behavior. One-column presentation remains scalar. Full ZWJ/skin-tone clustering,
long cluster storage, shaping, styled-path cost, broader lifecycle stability and
fixed resource targets remain open. This candidate is neither full Unicode
parity nor performance acceptance; existing result links and system activation
are untouched. Next work must close those behavior gaps and measure the affected
path, rather than declare success from the heart/keycap improvement.

## Unicode margin comparison — 2026-09-06

`nix develop --command python3 bench/grapheme_margin_probe.py` exited zero.
The authoritative final run is `bench/grapheme-margin-20260906-015856-24592.json`;
`bench/grapheme-margin-summary.json` records its hash and the independently
verified 84 exact CPR replies across three launches at stable 80×24 geometry.
Earlier margin runs predate final helper corrections; use the named final run
for reproducibility. No application source changed.
Final `nix build . --no-link --print-out-paths` and `nix flake check`
exited zero; raw logs are indexed in `bench/unicode-margin-final-validation.json`.

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

## Recovery recheck and constructor allocation diagnostic — 2026-09-06

Fresh recovery checks again passed Nix daemon access, private Unix socket
bind/connect/send/receive, and NVIDIA enumeration (RTX 4090, driver 595.91.07).
Raw results are in `bench/access-recovery-recheck.json`. No desktop windows,
system activation, push, or reset was performed; newer local work is preserved.

The saved V3 diagnostic build completed successfully before recovery. Production
engine/main hashes match the retained checkpoint. A new private Weston run of
`/nix/store/ac3rxpmnyv4a002p4kgpirczj2f590k4-cudaterm-0.1.0` exited zero at
80×24 and captured all six allocator phases in one process. Raw stdout, stderr
and smaps are under `bench/heap-phases-v3-runtime*`; the exact diagnostic-only
patch is `bench/heap-phases-diagnostic-v3.patch`. The first recovery launch used
an absent Weston store path and was retried with the pinned existing compositor.
That failure was an invocation error, not a restored-access failure.

Across the three font-buffer reads, mallinfo2 allocated arena bytes increased
2,228,496 and mmap-backed allocator bytes increased 4,632,576. Immediately across
successful constructor-scope exit, allocated arena bytes decreased 2,228,256,
free arena bytes increased by the same amount, and mmap-backed allocator bytes
decreased 4,632,576; total arena size stayed at 14,934,016 bytes. These counters
bracket temporary-buffer cleanup in the same process. They are not RSS/PSS,
allocation stack ownership, a peak measurement, or evidence that all free arena
pages can be returned. Heaptrack preload/injection attempts failed before a first
frame with a CUDA runtime/driver error; a settled allocation-stack profile remains
unknown. The normal private run succeeds, so those failures do not establish a
host-driver blocker. No allocator optimization is retained from this diagnostic.

The independently reviewed `bench/grapheme-summary.json` contains 99 valid cursor
replies from nine launches of the pinned three terminals. Cudaterm differs from
both comparators for heart VS16, emoji skin tone, two ZWJ sequences and keycap;
`docs/feature-evidence.md` records exact widths. This proves layout differences,
not visual shaping or copy fidelity. The full remaining requirement/evidence
matrix is `docs/remaining-evidence.md`. A fix must preserve complete UTF-8 through
copy, feed splits, margins and reflow rather than merely correcting the cursor.

On restored production source, `nix build . --no-link --print-out-paths` and
`nix flake check` both exited zero, recorded with raw logs and hashes in
`bench/recovery-final-validation.json`. The output remains the retained bhsg
word-selection package. Fixed performance targets, complete grapheme behavior,
matched display/latency evidence and broad current-checkpoint lifecycle work
remain unmet; the goal stays active. Next bounded optimization work should test
font staging only under frozen resource and workload gates, or address a measured
Unicode failure with exact copy/reflow regression coverage.

## Current goal status — access restored, validation resumed

The newly restored unrestricted turn on September 6 successfully queried the
RTX 4090/595.91.07 driver, bound a private Unix socket, and built the current
source through Nix. `nix flake check` also succeeds. Earlier environment
failures were real observations of the restricted workers, not evidence that
the host driver or Nix service had failed. `bench/access-restored.json` records
the fresh successful checks. New Luna workers perform the pending validation.

The parent-pushed snapshot is `af470c1`; local work is preserved and no system
activation or desktop benchmark is performed here. Private headless functional
checks and final Nix/Finix validation now pass, including explicit Ekko
presentation. The candidate fails the fixed PSS gates on both grids and is
not accepted; the full goal remains incomplete. Existing result and result-finix
links are preserved; review links select the freshly tested checkpoint.

Restored headless testing exposed two fixture assumptions. Private Weston's
Alt-F4 delivery did not close the idle window; a private-seat opcode now sends
the desktop-surface close request directly and that close test passes. The
new wake test queried `CSI 5 n`, while the frozen idle-checkpoint engine implemented only
`CSI 6 n` in its DSR handler. The fixture now uses an explicit cursor position
and the implemented query to isolate transport wakeups. Missing `CSI 5 n`
status replies were a confirmed source-level VT gap, addressed by the separate increment below;
no full VT compatibility is claimed. Failed logs are preserved under
`bench/idle-restored-functional-sync*.log`; complete sync and search reruns
passed through Nix. Exact checkpoint commands, source hashes and Ekko evidence
are recorded in `bench/idle-restored-functional.json`.

## Restored idle checkpoint — fixed performance limits unmet

The controlled run in `bench/idle-event-controlled.json` completed all 18
launches, with three samples per terminal per grid. Cudaterm voluntary context
switch medians are 338 (80×24) and 339 (318×89) per three-second interval;
linear p90 values are 338.8 and 341.4. These improve on the fixed historical
361/401 medians but remain above the better comparator target of zero.
CPU, RSS, private host memory and measured GPU memory (242/300 MiB) satisfy
this increment's fixed ceilings. Maximum PSS is 80,644,096/80,652,288 bytes,
exceeding the unchanged 78,086,144/78,073,856-byte ceilings. Collection success
is not acceptance success.

The contemporaneous reference run uses executable SHA256
`370893e3516a6397e9955919b26960b777a281f1e5a6e7c6c79b57acf6c47b00`,
identical to the old accepted v513 executable despite a different store path.
It also exceeds the historical PSS ceilings. This supports an environmental
contribution but does not isolate its cause, replace the baseline or waive
limits. Raw evidence is `bench/idle-event-reference-current.json`.

The settled trace shows the main event loop and PTY worker blocked in
indefinite waits across the measured interval. An initial worker attribution
for another thread's 100 ms polls was unsupported by thread name alone;
a separate same-executable stack run resolves the matching eventfd/pipe wait
inside libcuda (`bench/idle-event-settled-stacks-analysis.json`). No recurring
100 ms timeouts occur in either own loop during the measured interval. This
passes the own-polling gate, while PSS still fails overall acceptance. Do not describe all process
wakeups as application polling or all driver-associated costs as irreducible.
The instrumented trace is diagnostic, not a resource acceptance run.

## VT increment — normal device-status reply

Normal CSI 5n now returns exactly ESC[0n. The new branch excludes private
requests; existing CSI 6n handling is unchanged. CUDA regression coverage checks
normal status bytes, every feed split, private/malformed silence, parameter
overflow beginning with 5, and an explicit cursor-position response. Review
corrected a test's cursor-column expectation before the final passing run.
`nix run .#csi-test`, `nix run .#test`, `nix run .#vt-test`,
`nix run .#reference-test`, `nix build --out-link result-vt-status-review`,
and `nix flake check` all exit zero. `bench/vt-status-validation.json` records
source and executable hashes; its companion log is a manually assembled
command/result summary, not captured test stdout.

The private-window delayed-output fixture now requests both CSI 5n and CSI 6n
and requires their exact concatenated 10-byte response after waking from idle.
The full sync suite passes, as does explicit Ekko presentation on private
Weston. Finix preview build and evaluation pass with no failed assertions.
Raw output is in `bench/vt-status-sync.log`, `bench/vt-status-ekko.log`, and
`bench/vt-status-finix-*.log`. No desktop benchmark or system activation was
performed. Existing result/result-finix links remain unchanged.

The VT increment is separate from the frozen idle resource measurements; those
numbers do not measure this new executable. Broader memory, workload, Unicode
and feature targets remain incomplete. Next prioritize attribution of the PSS
change and the existing feature-comparison gaps without relaxing fixed limits.

## Word selection across soft wraps

Word-mode selection now follows existing positive wrap lengths across visible
rows, checking the neighboring character class before crossing each boundary.
This fixes double-click copying of a word split across rows. It stops at hard
breaks, separators and viewport edges, and skips synthetic padding before a
wrapped wide glyph. Line-mode selection remains physical-row based. No new
allocation, cell representation or CPU terminal-state path was introduced.
This is still the existing simple character-class policy, not Unicode word
segmentation or full grapheme support; off-viewport expansion is not provided.

Literal-byte CUDA regressions cover both click directions, multiple wraps,
separator boundaries, history rows, wide/combining text and resize reflow.
Parent review corrected boundary-class checks and malformed test literals
before the final passing build. Selection, reflow, CSI and reference tests,
Nix build and flake check pass (`bench/word-wrap-validation.json`). A new
private-window mode double-clicks the continuation of 96 W characters followed
by a space and END; clipboard roundtrip must contain precisely the 96-character
word. The full sync suite including this mode passes through Nix.
History-search interaction, explicit Ekko presentation, engine tests and Finix
preview/evaluation also pass on the same final executable; commands, logs and
hashes are in `bench/word-wrap-functional.json`. Existing accepted result links
remain unchanged. The full performance and feature goal remains incomplete.

## Mapping-level memory investigation — allocator experiment only

Nine private-headless 80×24 launches captured raw smaps and smaps_rollup:
three old accepted executables, three frozen VT-status executables, and three
VT-status executables with MALLOC_TRIM_THRESHOLD_=0 applied to the terminal
process environment. Weston did not inherit the experimental setting.
`bench/pss-maps-summary.json` links raw captures, read bounds, byte counts,
identities and reviewed hashes. This diagnostic uses a 960×640 compositor and
is not a replacement for the controlled two-grid resource baseline.

Old/current private memory was 69,758,976/69,914,624 bytes. Heap residency
was identical at 16,580,608 bytes, as were NVIDIA/DRI mapping totals at
24,813,568 private bytes. The difference was mainly executable-backed private
pages plus one anonymous page. Mapping names identify backing objects, not
which allocator or application component owns their contents. Historical
captures lack mapping detail, so this cannot explain the original PSS drift.

The temporary allocator setting reduced total private memory by 2,932,736
bytes in all three runs: heap private decreased 5,718,016 bytes while unnamed
anonymous private increased 2,785,280 bytes. PSS was 76,435,456–76,441,600
bytes. This is a reproducible diagnostic effect, not accepted optimization or
proof that all freed startup buffers caused the saving. Explicit trim
configuration disables dynamic threshold adjustment, as described in the
[glibc allocator manual](https://sourceware.org/glibc/manual/latest/html_node/Memory-Allocation-Tunables.html).
No allocator setting was added to the application or Finix defaults. A future
isolated experiment should compare scoped reclamation against fixed resource,
startup/throughput and lifecycle limits before adopting any change.

## Scoped heap-reclamation experiment — rejected and restored

A new frozen word-selection baseline measured all three terminals at 80×24 and
318×89, plus matched 80×24 plain/ANSI/Unicode PTY workloads and three startup
profiles. `bench/reclaim-baseline.json` contains the controlled 18-launch raw
resource matrix; `bench/reclaim-pty-{text,ansi,unicode}.json` and corresponding
Foot/Monstar files contain three measured launches, one warmup and three
intervals per launch. The older startup attempts lack a launch timestamp and
are diagnostic only. Valid profiles record process-launch monotonic time and
the first GL texture-swap return; this is not physical presentation latency.

Before editing main, `bench/reclaim-experiment-gates.json` froze the minimum
1 MiB private-memory reduction, existing PSS/GPU ceilings, CPU limits and
baseline dispersion envelopes for context switches, PTY barriers, whole-process
launches and first-swap startup. Full-goal comparator and historical targets
remain separate and unchanged. The baseline already exceeded fixed idle
context-switch targets: medians 1354/831 per three seconds, compared with
338/339 in the previous checkpoint. That variation is not attributed to a
source change or an irreducible driver cost.

The candidate added only malloc.h and one malloc_trim(0) call after engine and
optional face setup. Its engine-host executable was byte-identical to the
baseline. In the acceptance matrix, private memory was 71,618,560/71,626,752
bytes, above the baseline by 1,634,304 bytes; PSS also exceeded the fixed limits.
The small-grid CPU gate and text/ANSI whole-process launch envelopes failed.
First-swap startup passed its envelope (median 83.328 ms, linear p90 90.943 ms),
and the measured PTY barriers improved, but these do not waive other failures.
`bench/reclaim-evaluation.json` records all gate calculations and raw hashes.

A later paired smaps capture of both frozen executables finds only 69,632 bytes
less heap/RSS/PSS in the candidate, with identical file/library and device
private accounting. The baseline itself now has 71,688,192 private bytes,
so the earlier measured 1.63 MB increase is not established as patch-caused.
The earlier controlled runs lack mapping data sufficient to isolate that
accounting change. Even the paired saving is far below the predeclared minimum;
this diagnostic does not replace the original baseline or gate decision.

The two experimental main additions were removed, preserving the word-selection
and CSI fixes. `bench/reclaim-rejected.patch` keeps the rejected change.
The retained Nix build again resolves to the word-selection package bhsg with
app SHA256 fcd4d7551dab8736dd513820d21dfd1b1406f29dc2765ca430031234dc2a1cba;
Nix build and flake check both exit zero (`bench/reclaim-retained.json`). No
allocator default, Finix activation or desktop benchmark was introduced.

Next investigate which medium-lived host allocations change placement under
the allocator environment experiment. File-backed startup font data versus
heap staging is a hypothesis to profile before another implementation; the
scoped trim result does not establish that constructor buffers are the cause.
Broader memory retention, workload and daily-driver requirements remain open.

## Historical restricted recovery — superseded by restored validation

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
