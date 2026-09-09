# cudaterm

A Linux terminal with CUDA VT parsing, GPU screen state, and CUDA
pixel rasterization. The CPU transports PTY bytes and input events, manages the
child process, and presents CUDA output through an OpenGL buffer shared with
GLFW. OpenGL presents pixels; it does not draw glyphs.

The default window uses an installed monospace font with native-size grayscale
coverage, dark or light themes, padding, styled text and an animated cursor.
Fonts, colors and interaction settings reload without restarting the shell.
See [configuration and shortcuts](docs/configuration.md).

```sh
nix build .
nix run . -- -e bash
nix run .#test
nix run .#plain-test
nix run .#vt-test
nix run .#csi-test
nix run .#styled-test
nix run .#unicode-test
nix run .#workspace-test
nix run .#selection-test
nix run .#scrollback-test
nix run .#charset-test
nix run .#mouse-test
nix run .#graphics-test
nix run .#sync-test
nix run .#appearance-test
nix run .#bench -- --bytes 65536
nix flake check
```

A configured Finix desktop package is available:

```sh
nix build --impure --file nix/finix-preview.nix --out-link result-finix
./result-finix/bin/cudaterm-finix
```

It uses the desktop font, line height and Wallust colors. See
[Finix replacement checks and integration](docs/finix-replacement.md) for the
validated workflows, memory measurements, enablement and remaining differences.

Ekko v2's shell/browser workspace is supported. From this checkout:

```sh
nix run . -- -e nix run path:$HOME/dev/maintaining/ekko_v2#workspace -- \
  --current-terminal --session cuda-workspace
```

The Kitty graphics subset used by Ekko runs entirely in CUDA: streaming APC and
base64 parsing, RGB/RGBA uploads, zlib decompression, native-size placements,
cropping, alpha blending, queries, and image deletion. Decoded images stay in
VRAM; transient upload storage is freed after each completed transfer. Limits
are 128 images, 32 MiB per image and 64 MiB retained image data. PNG, file/shared
memory transport, animation, scaling, Unicode placeholders and multiple
placements per image are not implemented. This is Ekko compatibility, not full
Kitty/Foot/Monstar feature parity.

At 318×89 cells on the development RTX 4090, a private headless Weston comparison
measured idle RAM falling from 232 to 115 MiB RSS (71 MiB private), and NVIDIA
process GPU memory from 484 to 316 MiB. CUDA driver/GL resources still require
host RAM; these totals exclude Ekko and browser processes. Queue sizing, EGL
vendor selection and avoiding libdecor's GTK dependency cut RAM; a smaller CUDA
stack and lazy buffers cut VRAM. Alternate-screen redraws do not grow main
scrollback. See [measurements and integration evidence](docs/ekko.md).

The current build targets NVIDIA Ada (`sm_89`) and is being developed on an RTX
4090. A working NVIDIA driver and graphical session are needed for the app;
the engine tests need the GPU but no display. Nix build checks exercise the PTY
benchmark protocol without GPU access; `nix run .#test` runs actual CUDA tests. The build also checks special-key
encoding, including Shift/Alt/Ctrl navigation and function keys.

The GPU validates plain-text prefixes and uses parallel prefix scans to compute
line layout and scrolling. A cooperative warp interprets controls and UTF-8,
with parser state in shared memory and parallel cell writes. A third path parses
bounded UTF-8/SGR/tab lines in parallel and scans their color and layout effects.
The GPU finishes bounded fragments at feed boundaries before retrying parallel
processing. The CPU reads classifier results and consumed counts to select launches.
Screen parsing and terminal state stay on the GPU; a host observer handles OSC 52
desktop clipboard writes.

**Overall performance parity is not established**. The latest matched-grid
comparison trails Foot on text, ANSI and graphics, and beats Monstar on
all five measured PTY workloads. Compositor-capture latency has been measured,
but physical display latency remains unverified. See the
[latest measurements](docs/progress.md) for raw samples and limits.

The built-in fallback uses GNU Unifont 17.0.05, converted to a static atlas during
the Nix build and rasterized in CUDA. The explicit `bitmap` font uses 8×16 cells;
the default installed font uses runtime FreeType coverage. A build-time
custom font atlas and configurable/scaled cell dimensions are also supported. The engine supports BMP glyphs and 59,295 supplementary glyph records from
Unifont, wide cell pairs, and variable-length combining marks. Three marks stay
inline in each 32-byte cell; further marks share a GPU suffix arena capped at
8 MiB. Exhaustion with no reclaimable nodes raises an explicit error. Width data uses
Unicode 16.0.0 plus Unifont combining overrides. Missing glyphs use a replacement glyph. Supplementary symbols render as
monochrome bitmaps; shaping and emoji sequences remain unfinished.
Font copyright and license files are installed in `result/share/cudaterm`.

The [Finix desktop candidate](docs/finix-replacement.md) adds configured fonts and
colors, responsive input during image decoding, Wayland clipboard verification,
and terminal/launcher integration. Broader VT compatibility, full grapheme
handling, and physical display-latency measurements remain open.

See [completion requirements](docs/acceptance.md) and the
[benchmark procedure](bench/README.md). The initial JSON files used different geometries. New `*-matched-*.json` runs
verify 318×89 cells, settle before timing, and reject geometry changes. Font
rendering still differs between implementations.

Drag with the left mouse button to select visible cells; release to copy automatically.
Ctrl-Shift-C copies again. Copied selections flash pale yellow for 200 ms, including
keyboard, search-result and link copies, then regain their original highlight.
Ctrl-Shift-V pastes. OSC 52 clipboard writes from applications such as Ekko are
supported for UTF-8 text up to 1 MiB; clipboard reads are unsupported. Ekko draws
its own selection flash when it owns the mouse. Selection includes complete wide glyphs and combining
marks. New terminal output or a resize clears the selection. Copies join true soft wraps, preserve spaces within joined lines, omit padding
inserted before wide glyphs, and keep explicit line breaks. Trailing spaces at
hard breaks or the end of a selection are trimmed. Double-click selects a word and
triple-click selects a physical row; dragging extends by words or rows. Word
selection groups letters, digits, underscore and non-ASCII glyphs, and groups
identical ASCII punctuation. It does not implement Unicode word segmentation.

Use the mouse wheel or Shift-PageUp/Shift-PageDown to browse up to 4096 retained
rows. Selection and copying also work in history. Typing or pasting returns to
live output. Full-screen primary output enters history; alternate-screen and
partial scrolling regions do not. Resizing reflows primary text and history to
the new width, preserving explicit line breaks and typed spaces. Narrowing can
evict older text when it exceeds the 4096-row history limit. Wide glyphs move as
pairs; at a one-column width they become replacement characters. Alternate-screen
content keeps its physical layout and is clipped or padded. Resize clears the
selection; image pixels remain allocated and their primary anchors follow reflow.

Ctrl-Shift-F opens incremental history search. Type or use Ctrl-Shift-V to edit
the query, Enter/Shift-Enter to find the next/previous match, Ctrl-Shift-C to
copy it, Ctrl-U to clear, and Escape to close and restore the prior viewport.
Search input stays local. Search covers primary history and live text, or only
the active alternate grid, joining soft wraps but stopping at hard breaks.
Queries match exact, case-sensitive Unicode codepoints (up to 512), without
normalization or regular expressions. Highlights and copies include complete
cells and their combining marks. A bottom-row prompt overlays the terminal;
long queries are clipped to its width. Output and resize restart the active
search against current text.

Copying counts exact UTF-8 bytes before allocating each viewport-sized batch.
A batch above 64 MiB raises an explicit error; copy buffers above 64 KiB are
released after use. Combining-mark storage preserves text but does not provide
ZWJ layout or shaped emoji rendering.

Alternate-screen modes 47, 1047, and 1049 are supported. Mode 47 retains the
alternate contents; 1047 clears them when leaving; 1049 saves/restores the main
cursor state and clears on entry.

DEC Special Graphics (G0/G1, SI/SO) is supported for legacy TUI borders, including
Unicode copying from those cells. Other national character sets and G2/G3
invocation are not implemented yet.

Applications can enable normal (1000), button-motion (1002), or all-motion
(1003) mouse tracking with legacy or SGR (1006) reports. Clicks, drags, and
vertical and horizontal wheel ticks are encoded on the GPU. Hold Shift to select text or browse
scrollback locally while tracking is enabled. Legacy coordinates are limited to
223; use SGR for larger grids. Pixel coordinates (1016), focus reports (1004),
cell-size queries (CSI 16 t), and synchronized updates (2026, with a timeout)
support Ekko and browser input. Without application mouse tracking, the wheel
sends arrow keys in the alternate screen and browses history in the main screen.

Window configuration accepts `--app-id`, `--title`, `--working-directory`,
`--theme` (Monstar/Wallust color file), `--font-face` (CTFACE01 atlas),
`--cell-width`, `--cell-height` and `--background-opacity`. OSC 0/2 updates titles;
OSC 4/10/11/12 updates/queries palette and default colors, with reset variants.
Theme files are read at startup. See `cudaterm --help` for invocation syntax.

Ctrl-Plus/Minus/0 zooms and resets; runtime font families are rerasterized at the
new size. Ctrl-Shift-Comma reloads configuration. Ctrl-drag makes a rectangular
selection; dragging at the text edge extends through history. Ctrl-click opens
a detected URI, and Ctrl-Shift-N opens a shell in the current directory. See the
[complete configuration and feature limits](docs/configuration.md).
