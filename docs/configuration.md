# Appearance and interaction

Cudaterm reads `$XDG_CONFIG_HOME/cudaterm/config`, falling back to
`~/.config/cudaterm/config`. Create the file to customize the defaults:

```ini
font-family = monospace
font-size = 14
line-height = 1.3
theme = midnight
padding-x = 12
padding-y = 10
background-opacity = 1
cursor-style = block
cursor-blink = false
cursor-animation = 0.08
scroll-multiplier = 3
```

`font-size` is in logical pixels; monitor scaling and zoom are applied before
rasterization. Fontconfig resolves the installed family and its regular, bold,
italic and bold-italic faces. FreeType prepares grayscale glyph coverage at the
requested size. CUDA renders the terminal, including glyph composition, styles,
selection, graphics and the cursor. Missing glyphs use the existing Unifont
fallback. This is scalar font rendering: ligature shaping, full grapheme shaping,
and color emoji are not implemented.

`line-height` is a multiplier from 0.5 to 3. Padding is in logical pixels.
`background-opacity` changes the default background; explicit cell backgrounds
stay opaque. `theme` accepts `midnight`, `light`, `classic`, or a Wallust/Monstar
color-file path. File paths in the config resolve relative to its directory.

Use `cursor-style = block`, `underline`, or `bar`. Applications can override it
with DECSCUSR. `cursor-blink` controls the default; blinking stops when the cursor
is hidden or the window is unfocused. An unfocused cursor is an outline.
`cursor-animation` is the time in seconds the cursor takes to settle after a
move (0–0.5); set it to `0` for no motion. Motion stops scheduling frames as
soon as the cursor settles. Moves within a quarter second of your last
keystroke or pointer event animate; positions an application picks on its own
— output, repaints — and single jumps longer than eight cells land immediately,
so the block tracks the text instead of drifting over it.

Each setting also accepts a CLI flag, for example:

```sh
cudaterm --font-family 'DejaVu Sans Mono' --font-size 16 --theme light
cudaterm --config ./terminal.conf
cudaterm --no-config --font-family bitmap --theme classic --padding-x 0 --padding-y 0
```

`--font-file /path/to/font.ttf` loads a standalone font at runtime, with synthesized
bold/italic coverage when separate style files are unavailable. `font-fallback`
accepts a second installed family or `file:/path/to/symbols.ttf`; its missing
characters are fitted to the primary terminal cell width. The Finix launcher uses
the configured font file and Nerd Font symbols through this runtime path.

Rendered fonts are cached in `$XDG_CACHE_HOME/cudaterm/fonts` (default
`~/.cache/cudaterm/fonts`), including all four styles and fallback symbols.
Repeated launches reuse these atlases. Font file changes, resolved style changes,
font size, line height, width data, and FreeType properties invalidate the cache.
Nix fingerprints the font renderer and its dependencies so unrelated terminal
rebuilds can reuse the cache; native builds conservatively use executable identity.
Missing, corrupt, or unwritable caches fall back to rendering; deleting the
cache directory is safe. Cold generation prepares the four styles concurrently,
with separate FreeType libraries and a serial fallback when threads are unavailable.

The Finix package prepares its configured primary font and symbols during the
Nix build. Its launcher sets `CUDATERM_PREPARED_FONTS` to those validated atlases,
so the first launch also avoids rasterization. Other sizes, font overrides, and
zoom levels use the normal runtime cache. Nix store font identities are portable
across machines; mutable font files retain timestamp and inode checks.
Runtime-only font path strings without Nix dependency context use the runtime
cache instead of requiring the file inside the build sandbox.

`--font-face` still loads a prepared CTFACE01 atlas. Prepared atlases and the
`bitmap` family use scaled coverage; runtime font families rerasterize on zoom
and display-scale changes. Runtime glyph coverage is bounded to 16 MiB per style.

Ctrl-Shift-Comma or `SIGUSR1` reloads settings without restarting the shell, even
when the window is idle. Command-line
settings keep precedence after reload. Invalid values report the file and line;
a failed config/font preparation leaves the running presentation intact. Theme
reload also resets application palette changes to the configured colors.

| Shortcut | Action |
| --- | --- |
| Ctrl-Plus / Ctrl-Equal / Ctrl-Minus | Zoom (also accepts Shift) |
| Ctrl-0 | Reset zoom (also accepts Shift) |
| Ctrl-Shift-Comma | Reload config |
| Ctrl-Shift-N | Open a shell window in the foreground process's directory |
| Ctrl-Shift-C / Ctrl-Shift-V | Copy / paste clipboard |
| Middle-click | Paste primary selection (Shift overrides application mouse capture) |
| Shift-Insert | Paste clipboard, including into search |
| Ctrl-Shift-F | Open history search |
| Enter / Shift-Enter, Ctrl-N / Ctrl-P | Next / previous search match |
| Ctrl-U / Ctrl-W | Clear query / remove last query word |
| Escape | Close search and restore the viewport |
| Shift-PageUp / Shift-PageDown | Browse history by page |
| Shift-Home / Shift-End | Oldest retained history / live output |
| Ctrl-drag | Rectangular selection |
| Ctrl-click / Ctrl-right-click | Open / copy a detected URI |

History shortcuts pass through to applications on the alternate screen.
Hold Shift to select when an application captures the mouse; Ctrl-Shift-drag
selects a rectangle in that case. Drag near the upper or lower text edge to
extend a selection through history. Selection anchors follow history while the
viewport moves. Rectangles copy one physical row per line and include complete
wide characters and their combining marks.

URI gestures recognize explicit `https://`, `http://`, `file://`, and `mailto:`
text, including across soft wraps. Enclosing punctuation is trimmed; the URI is
passed directly to `xdg-open` as an argument. There is no shell interpolation.
OSC 8 hidden hyperlink targets use the same gestures, preserving the exact URI
instead of trimming punctuation from it. Link metadata follows cells through
scrollback and resize. The GPU allocates a 512-entry target table on first use;
older entries can be evicted without redirecting their text to a newer target.
OSC strings are limited to 511 bytes including the command and parameters.
Targets use the same supported URI schemes as detected links.

Copied selections also become the native primary selection on X11 and on
Wayland compositors supporting `primary-selection-unstable-v1`. Middle-click
pastes primary selection; regular clipboard paste remains independent. File
drops insert single-quoted shell paths through the paste path, including
bracketed-paste delimiters when enabled. Drops containing control characters
are rejected before inserting any paths.

Native Wayland text-input-v3 supports IME preedit, committed text, and local
search composition when the compositor and input method provide the protocol.
Preedit uses the existing cell renderer, clips at the right edge, and does not
render a separate composition caret or selection. Inertial touchpad scrolling
remains a gap relative to Monstar. Cudaterm also has no tabs or splits. Cursor easing does not establish
Neovide's smooth scrolling or shaped-text rendering.

Applications can negotiate Kitty keyboard disambiguation (flag 1), including
independent primary/alternate mode stacks and CSI-u modified keys. Unmodified
Enter, Tab, and Backspace retain their normal bytes. The remaining Kitty
keyboard flags are masked until their callback behavior is implemented.
