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
color emoji and IME composition are not implemented.

`line-height` is a multiplier from 0.5 to 3. Padding is in logical pixels.
`background-opacity` changes the default background; explicit cell backgrounds
stay opaque. `theme` accepts `midnight`, `light`, `classic`, or a Wallust/Monstar
color-file path. File paths in the config resolve relative to its directory.

Use `cursor-style = block`, `underline`, or `bar`. Applications can override it
with DECSCUSR. `cursor-blink` controls the default; blinking stops when the cursor
is hidden or the window is unfocused. An unfocused cursor is an outline.
`cursor-animation` is the easing duration in seconds (0–0.5); set it to `0` for
no motion. Motion stops scheduling frames as soon as the cursor settles.

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

`--font-face` still loads a prepared CTFACE01 atlas. Prepared atlases and the
`bitmap` family use scaled coverage; runtime font families rerasterize on zoom
and display-scale changes. Runtime glyph coverage is bounded to 16 MiB per style.

Ctrl-Shift-Comma reloads settings without restarting the shell. Command-line
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
OSC 8 hidden hyperlink targets are not yet supported. Middle-click primary
selection, native Wayland IME and inertial touchpad scrolling remain gaps
relative to Monstar. Cudaterm also has no tabs or splits. Cursor easing does not establish
Neovide's smooth scrolling or shaped-text rendering.
