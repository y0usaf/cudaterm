# Unicode layout increment: measured requirements and implementation constraints

The retained bhsg executable fails the heart+VS16 and keycap cursor-width
comparisons in `bench/grapheme-summary.json`. This increment must address those
real sequences while retaining the larger grapheme goal; it does not complete
skin-tone, ZWJ, shaping, fallback or Unicode word segmentation support.

Unicode 17 [UTS #51](https://www.unicode.org/reports/tr51/tr51-29.html#def_emoji_presentation_sequence)
restricts valid emoji presentation sequences to the versioned
[emoji variation sequence data](https://www.unicode.org/Public/17.0.0/ucd/emoji/emoji-variation-sequences.txt).
Use that data to qualify VS16 bases. A hand-picked heart table or unconditional
widening after FE0F would encode the test rather than the supported semantics.
These Unicode sequence definitions do not prescribe terminal cursor coordinates;
the actual Foot/Monstar runs supply the terminal comparison.

## Required behavior

- Base characters display immediately, even if the application never sends
  another byte. Their presentation can change when a valid suffix arrives.
- Preserve exact UTF-8 bytes in the cell representation, selection/copy and
  search. The current three combining slots can hold these short sequences;
  they cannot hold every full ZWJ cluster.
- Whole feeds, every UTF-8 byte split, and long styled lines must agree.
- Width promotion at the last column must preserve the base, suffix and soft
  wrap metadata. Check pending-wrap behavior by printing a following ASCII
  character, since a clipped column reply alone can hide it.
- Preserve pair integrity during overwrite, erase, insertion and reflow.
  Test both margins, bottom-row scrolling, autowrap disabled, one-column windows,
  resize narrower/wider, saved cursor, and alternate-screen behavior.
- Invalid sequences such as A+FE0F must not acquire emoji width. Controls and
  intervening text require explicit tests; a cursor query between base and
  selector is a distinct input condition from a transport-only feed split.

## Source paths and rejected shortcuts

`src/engine.cu::put` commits each scalar immediately and appends width-zero
scalars to the prior cell. A supported eager promotion must repair or relocate
the entire cell and wide tail, not just increment `s.col`. Preserve queued
history copies when promotion wraps at the bottom margin.

`src/styled.cuh::styled_lines` and `styled_paint` independently implement layout
and mark attachment. They must agree with the interpreter. Initially rejecting
an affected styled line before any commit can preserve correctness, but needs
performance validation under frozen gates. A suffix beginning a new feed can
follow an ASCII digit emitted by the plain fast path; that boundary cannot be
ignored just because the full sequence contains non-ASCII bytes.

An agent proposed holding an uncommitted candidate base until the next scalar.
Parent review rejected that design: a final digit or heart would remain invisible
indefinitely, while flushing at the end of a feed would break split equivalence.
The required direction is immediate emission followed by supported promotion,
or another design that demonstrates both immediate output and split equivalence.
The current review candidate now uses eager emission and later promotion.
Autowrap-disabled right-edge tracking and one-column promotion remain incomplete.

`src/search_kernels.cuh` walks base-plus-marks for matching but separately lays
out prompt cells. Validate both matched text and prompt geometry. Selection emits
base-plus-marks; reflow copies whole cells and uses WIDE/TAIL. Those existing
mechanisms are useful, not proof that promotion integrates correctly.

Before retaining a change, run CUDA Unicode/selection/search/reflow/reference
regressions, styled-versus-streaming comparisons, private-compositor probe and
copy checks, followed by Nix build and flake check. Preserve the fixed resource
and throughput gates; report any affected-path slowdown rather than waiving it.
