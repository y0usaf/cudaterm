# Daily-use target — historical September 5 checkpoint

The retained layout increment preserves German keypad comma and uses Foot's
measured application Separator/Alt/Ctrl forms. US mappings remain unchanged.

The keypad increment adds NumLock navigation, application-keypad sequences
and reset/private-mode handling. Numeric Ctrl modifier policy, non-US layouts
and full keyboard protocols remain partial. Application-keypad mode is masked
by default NumLock override mode 1035, matching the measured references; an
application can clear it with CSI ? 1035 l.

The selection increment extends word and logical-line copying through retained
history above or below the viewport, with alternate-screen isolation and
bounded GPU copy scratch.

The immediate target is the local Ekko shell/browser workspace: dependable
input, complete frames, bounded retained memory, usable history and selection,
and clean exit/reattach. Full Foot/Monstar feature parity is a separate target.

Use `nix run . -- -e /home/y0usaf/dev/maintaining/ekko_v2/result/bin/ekko
attach cuda-workspace` to attach the existing session with the current build.
See [Ekko compatibility](ekko.md) for the measured memory baseline.

## Hardening build

- Partial PTY writes advance an offset rather than moving the entire remaining
  paste. The queue releases its allocation after delivery.
- When a child stops reading input, the event loop waits for PTY writability
  or window events rather than polling continuously just because input is queued.
- Ctrl-Space sends NUL, like Ctrl-@.
- After the direct child exits, the window drains queued output and closes even
  if a background process inherited the slave PTY. It does not terminate
  independent Ekko daemons.

Terminal parsing, graphics decoding and rendering remain in CUDA. No CPU image
copy or persistent graphics allocation was added.
