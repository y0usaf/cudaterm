# Completion requirements

The active objective is the full baseline, optimization and daily-driver
comparison in the supplied task. Earlier Ekko/Finix milestones are supporting
evidence, not a narrowing of completion. See [Ekko evidence](ekko.md).
The broader Foot/Monstar criteria below remain unfulfilled unless separately
measured; Ekko compatibility alone does not establish parity.

The objective is a terminal emulator with CUDA parsing, terminal state updates,
and rasterization, with measured performance competitive with Foot and Monstar.
The CPU must perform Linux process/PTY I/O and window-system calls: CUDA kernels
cannot directly replace these OS interfaces. Host I/O is transport, not a CPU
terminal-parser fallback.

Completion requires evidence for all of the following, not just a successful build:

- A reproducible Nix build and Nix correctness checks.
- Interactive shell and command execution; correct PTY resize and child cleanup.
- CUDA-resident streaming VT parsing and screen state; chunk boundaries must not
  change results. Cursor movement, erasure, scrolling regions, delayed wrap,
  SGR, alternate screen, terminal queries, and UTF-8 require regression coverage.
- CUDA rasterization and a displayed window, with verified glyphs, colors, cursor,
  resize, Unicode widths, and scrollback. Font quality and coverage must be stated.
- Usable keyboard input, paste, selection, clipboard, and scrollback navigation.
- Reproducible same-machine comparisons against Foot and Monstar for plain text,
  ANSI-heavy output, Unicode, scrolling, latency under load, and idle resource use.
  Keep raw samples, commands, versions, geometry, font, GPU and display details.
- Performance comparisons must separate parser/PTY completion from actual display
  presentation. A cursor reply is a parsing barrier, not proof a frame was shown.
- Report remaining feature and performance gaps honestly; no parity claim from
  one throughput microbenchmark or from a CUDA-only kernel timing.

## Scope of local design rules

There is no extension interface or plugin lifecycle at present; adding one would
introduce more API than functionality. Revisit the extension rules when a plugin
surface is introduced. One window owns the terminal session; persistence across
viewer restarts is not currently requested. OS resources must still be cleaned up.

Recovering useful existing code is preferable to rewriting it, provided its data
path can satisfy the CUDA requirement. A CPU-parser-only terminal is not a final
substitute even if its renderer is fast.

## Numerical baseline gates

[Baseline audit](baseline-audit.md) records adopted historical-reference PTY
median/p90 and RSS gates, raw extraction, and the missing measurement matrix.
The better comparator is chosen per applicable metric; no tolerance is added
to make the current build pass. A new environment requires matched comparator
data as well as disclosure against the fixed historical references. Unknown
metrics cannot count as passing, and parser barriers cannot satisfy display
latency requirements.
