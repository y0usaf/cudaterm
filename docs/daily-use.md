# Daily-use target — historical September 5 checkpoint

The retained layout increment preserves German keypad comma and uses Foot's
measured application Separator/Alt/Ctrl forms. US mappings remain unchanged;
US/German held-key and subsequent text delivery checks pass, as do all eight
final integration commands including private Ekko and Nix/Finix. Integration status
and exact limitations are in [progress](progress.md). IME, other layouts and
extended keyboard protocols are not established by these fixtures.

The latest retained keypad increment adds NumLock navigation, application-keypad sequences
and reset/private-mode handling. Exact private keyboard fixtures pass their frozen
mode/navigation gates; all 13 recovery integration commands passed, including
private Ekko and Finix preview/evaluation. Numeric Ctrl modifier policy,
non-US layouts and full keyboard protocols remain partial. Application-keypad mode
is masked by default NumLock override mode 1035, matching the measured references;
an application can clear it with CSI ? 1035 l. See [current progress](progress.md)
and `bench/keypad-evaluation.json` for the exact tested scope.

The build and results below describe the September 5 checkpoint.
[Current progress](progress.md) records subsequent GPU history reflow, wrapped
copying, history search, event-driven idle waits, CSI status replies and the
latest private-headless Ekko/Finix validation. The historical remaining-work
list below is not a current feature inventory.

The current selection increment extends word and logical-line copying through
retained history above or below the viewport. Private ASCII clipboard fixtures
and CUDA tests cover exact copying, alternate-screen isolation and bounded GPU
copy scratch; Unicode segmentation, drag/autoscroll and desktop clipboard
coverage remain open. See `bench/offviewport-final-validation.json` for unit and
clipboard checks, and current integration status in [progress](progress.md).

The immediate target is the local Ekko shell/browser workspace: dependable
input, complete frames, bounded retained memory, usable history and selection,
and clean exit/reattach. Full Foot/Monstar feature parity is a separate target.

## Current hardening build

`/nix/store/dv3icgbzyqjrlc6bi1bwsfyd178iw6hg-cudaterm-0.1.0`

- Partial PTY writes advance an offset rather than moving the entire remaining
  paste. The queue releases its allocation after delivery. A nonblocking-pipe
  regression checks a 1 MiB binary payload with further input appended during
  backpressure, exact byte ordering, and allocation cleanup.
- When a child stops reading input, the event loop waits for PTY writability
  or window events rather than polling continuously just because input is queued.
- Ctrl-Space sends NUL, like Ctrl-@.
- After the direct child exits, the window drains queued output and closes even
  if a background process inherited the slave PTY. A private Weston test checks
  256 KiB of final output, its final marker, and exit status 23. The previous
  build times out on this test; the new build passes. It does not terminate
  independent Ekko daemons.

Terminal parsing, graphics decoding and rendering remain in CUDA. No CPU image
copy or persistent graphics allocation was added. This pass does not claim a
new measured RSS reduction or browser FPS improvement.

## Verification

These commands exited zero for this build:

- `nix build .` (includes CPU input/backpressure checks).
- `nix flake check`.
- `nix run .#sync-test` (private-compositor complete-frame and child-exit tests).
- `nix run .#graphics-test` (36 actual CUDA cases).
- Engine, VT, CSI, plain/styled, reference, Unicode, mouse, scrollback, charset,
  selection and workspace test executables through `nix develop . --command`.
- Real Ekko integration and real browser integration through `nix develop`:
  pixel checks, keyboard/paste routing, GPU mouse to DOM, clipping, deletion,
  client death/reattach, zoom/swap, placement reuse and shutdown.

Logs: `bench/daily-{sync,graphics,integration,flake-check}.log`,
`bench/daily-browser.json`, and `bench/daily-lifecycle-before.log`.
The browser integration is headless; it does not exercise desktop clipboard
delivery or a full working day. The input queue test covers transport under
backpressure, not measured window input latency under a long CUDA decode.

## Remaining work at that historical checkpoint

- Extended use of the actual workspace without hangs, lost input, image leaks,
  flickering or required restarts. Automated regressions cannot establish this
  subjective daily-use threshold on their own.
- Input latency during large compressed browser frames: decoding still blocks
  the window thread. This remains a priority beyond the blocked-write fix.
- Desktop copy/paste, selection and keyboard-layout coverage. Wrapped-line copy
  still preserves physical row breaks; resize does not reflow history.
- Font sizing/HiDPI usability, grapheme/emoji shaping, and whichever additional
  editors, remote shells or multiplexers are required for the user's workflow.

Use `nix run . -- -e /home/y0usaf/dev/maintaining/ekko_v2/result/bin/ekko
attach cuda-workspace` to attach the existing session with the current build.
See [Ekko compatibility](ekko.md) for the supported graphics subset and measured
memory baseline.
