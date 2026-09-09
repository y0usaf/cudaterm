# Cudaterm / Monstar parity audit

This is a source audit of the current checkouts as of 2026-09-09. Existing
project notes were used only as pointers; the matrix below is based on the
implementation in `src/`, `flake.nix`, and `build.zig`. Cudaterm references
include the current working tree. Acceptance evidence is recorded below;
source coverage alone does not establish full compatibility.

`Implemented` means Cudaterm has the named behavior. `Partial` means that a
bounded subset exists or that an important integration path is still missing.
`Missing` means there is no corresponding implementation in the current
source. The status is parity status, so an implementation can be useful while
remaining `Partial` against Monstar.

| Area | Monstar current source | Cudaterm current source | Status | Gap and acceptance target |
| --- | --- | --- | --- | --- |
| Font discovery and rasterization | `src/Font.zig:1-9,748-851,1025-1334` loads FreeType faces, fontconfig candidates, embedded symbols, and lazy fallback faces. | `src/font.hpp` resolves at most the configured family plus one fallback and rasterizes FreeType gray/mono bitmaps. | Partial | Add cluster-aware fallback and the face/style/color policy described below; test primary, bold/italic, CJK, symbol, and emoji fallback. |
| HarfBuzz shaping and ligatures | `src/TextShaper.zig:1-31,128-243` and `src/Renderer.zig:1175-1715` shape runs, cache output, repair `.notdef` clusters, and snap clusters to cells. | No HarfBuzz dependency in `flake.nix`; `src/font.hpp` accepts only gray/mono raster output. | Missing | Shape Latin ligatures, Arabic joining, Indic clusters, and fallback runs while preserving cell selection/search anchors. |
| Grapheme clusters and emoji presentation | Ghostty VT is constructed with terminal state in `src/App.zig:470-488`; `src/Font.zig:1038-1282` resolves complete clusters and emoji/color preference. | `src/grapheme_properties.cuh`, `src/styled.cuh`, and `src/engine.cu` implement GPU combining/VS16/modifier/ZWJ boundary logic, with three inline marks plus a suffix pool. | Partial | The cluster state is useful for width and copy, but there is no shaped emoji or color-font path. Test ZWJ sequences split across feeds, modifiers, variation selectors, and long mark chains. |
| VT parser and terminal modes | `src/App.zig:470-488,820-918` delegates terminal parsing/effects to Ghostty VT and handles clipboard, DND, title, device, and progress effects. | `src/engine.cu` is a custom GPU parser; public feed/reply/resize/mode APIs are in `src/engine.cuh`. | Partial | Build a VT conformance fixture covering CSI/OSC/DCS, alternate screens, reports, synchronized output, and malformed input; close the unsupported mode gaps before claiming parity. |
| Keyboard layouts, compose, and functional keys | `src/Keyboard.zig:1-257,343-430` owns XKB state, modifier sides, compose, layouts, and functional-key remapping. | `src/main.cu` uses GLFW callbacks and `src/input.hpp` has a fixed legacy key/keypad table; no XKB/compose state is owned by Cudaterm. | Partial | Keep GLFW for event delivery but add layout/compose-aware translation and test US, Dvorak, dead keys, media keys, and modifier sides. |
| Kitty keyboard protocol | Ghostty input encoding is exercised in `src/Keyboard.zig:814-865,1020-1075` and App forwards translated events. | `src/keyboard_protocol.cuh`, `src/keyboard_protocol.hpp`, and `src/main.cu` negotiate and encode disambiguation flag 1 with independent screen stacks. | Partial | Child enables Kitty keyboard flags, presses representative keys, and captures exact CSI-u/disambiguate/modifyOtherKeys bytes through the PTY. |
| Mouse reporting and terminal selection | `src/App.zig:2777-3450` handles pointer reports, links, word/line/rectangle gestures, autoscroll, and scrollbar interaction. | `src/main.cu` and `src/engine.cuh` cover cell/word/line/rectangle/link selection, legacy/SGR reports, and local wheel behavior. | Partial | Match selection gesture details, pixel coordinates, smooth/inertial scroll, and scrollbar behavior; test mouse modes with Shift override and wide/combining cells. |
| Basic Kitty graphics | `src/App.zig:457-488,771-800` enables VT image decoding and image limits; `src/kitty_graphics.zig:53-146` collects placements. | `src/graphics.cuh` parses streaming APC, raw RGB/RGBA, zlib, crop/placement/delete/query; limits are in `src/graphics_types.cuh`. | Partial | Test raw RGB/RGBA and zlib uploads, deletion, crop, scroll/reflow anchors, and synchronized output under bounded dimensions. |
| Kitty graphics transports and rendering | Ghostty-backed Kitty image state plus `src/kitty_graphics.zig:330-400` handles PNG/gray/RGBA formats, scaling, crops, z layers, virtual placeholders, and multiple placements; `src/App.zig:771-800` decodes PNG. | `src/graphics.cuh` and `src/graphics_types.cuh` support cell-based scaling and 256 independent placements sharing decoded image storage. PNG, file/shared-memory transport, animation, Unicode placeholders and z ordering remain absent. | Partial | Add one transport/format at a time with capability tests for `t=d`, PNG, `t=s`, scaling, animation, Unicode placeholders, and multiple z-ordered placements. |
| Standard clipboard copy/paste | `src/Clipboard.zig:241-521` claims and requests Wayland clipboard data asynchronously with MIME selection and bounded transfers. | `src/main.cu` uses synchronous GLFW clipboard strings and bracketed paste. | Partial | Preserve current copy flash and bracketed paste while adding MIME-aware asynchronous reads and a transfer cap without blocking the event loop. |
| Native primary selection | `src/Clipboard.zig:20,71-80,316-345,496-521` and `src/App.zig:728-760,3450-3770` support Wayland primary offers/sources and middle-button paste. | `src/primary_selection.hpp` bridges existing X11 APIs and the extension in `nix/glfw-primary-selection.patch`; `src/main.cu` claims on copy and pastes on middle click. | Partial | Positive Sway/wlroots copy/paste and negative Weston/no-global copy passed; asynchronous transfers remain a gap. The patched GLFW API must return capability, silently no-op on unsupported compositors, bound reads to 64 MiB, and time out a broken offer in 5 s. |
| OSC 52 and Kitty clipboard | Monstar routes OSC 52 and Kitty clipboard reads/writes through `src/App.zig:898-918,2353-2455` and `src/Clipboard.zig:323-399`. | `src/clipboard.hpp` decodes only outgoing OSC 52 writes, validates UTF-8, and caps payloads at 1 MiB; README documents reads unsupported (`README.md`). | Partial | Test OSC 52 clipboard and primary writes, query/read responses, invalid UTF-8, oversized input, and Kitty clipboard MIME/status handling. |
| Drag and drop | `src/Clipboard.zig:581-748` tracks MIME offers, motion/leave, source actions, copy/move negotiation, and transfer data; App sends Kitty DND events (`src/App.zig:898-918`). | `src/main.cu` accepts GLFW file paths and `src/input.hpp` shell-quotes them before paste. | Partial | Add Wayland MIME/action negotiation and Kitty DND protocol effects; test text, URI-list, multiple files, cancellation, and copy/move acceptance. |
| Wayland protocol integration | `src/Window.zig:1-80,205-245,930-1120` binds primary selection, text-input-v3, fractional scale, activation, decorations, cursor shape, and background effect globals. | Cudaterm relies on GLFW in `src/main.cu`; Nix carries pointer, primary-selection, and text-input-v3 GLFW patches (`flake.nix`) and links Wayland/X11 (`flake.nix`). | Partial | Keep the small GLFW extensions, then cover fractional scaling, activation, decoration, cursor shape, and background effect behavior or explicitly scope them out. |
| Wayland text-input-v3 / IME | `src/Window.zig:322-339,385-390,655-687,1207-1220` owns the object, focus, enable/disable, cursor rectangle, and event forwarding; `src/App.zig:4299-4372` applies preedit/commit state at done. | `nix/glfw-ime.patch` adds the generated v3 object/listeners and native API; `src/ime.hpp` wraps it; `src/main.cu` preserves normal GLFW xkb input and applies commit/preedit state; `tests/wayland_ime.c` provides a private wlroots v2 input-method fixture. | Partial | The bridge and transient preedit overlay are implemented. Run the private Sway fixture for enter/leave, UTF-8 byte-offset preedit, one commit at done, cursor rectangle updates, keyboard-grab consumption, and ordinary typing after IME exit. |
| Linux desktop integration | `src/App.zig:955-1160,1292-1360` uses D-Bus for portal appearance, URI/file opening, notifications, progress, and activation; `src/cgroup.zig` provides systemd scope support. | `src/main.cu` has detached launcher/new-window handling and sets `TERM=xterm-256color`/`COLORTERM=truecolor`; no D-Bus/portal/cgroup implementation is present. | Partial | Test URI/file opening, notifications, activation, system theme changes, and optional cgroup isolation; retain a working no-D-Bus build. |
| Configuration, themes, and reload | `src/Config.zig:1-969` supports broad config/theme/font/window/scrollback/image settings; `src/App.zig:1683-1712,2047-2082` reloads and reapplies them live. | `src/config.hpp` has a small strict settings/theme parser; `src/main.cu` handles Ctrl-Shift-Comma and SIGUSR1 reload. | Partial | Add live/system theme and per-setting coverage, then verify invalid config diagnostics, relative theme paths, font reload, and no state loss on SIGUSR1. |
| Search | `src/ScrollbackSearch.zig:1-102` and `src/App.zig:1437-1630` drive bounded nonblocking search work and restore the prior viewport. | `src/main.cu` owns the prompt and controls; `src/engine.cu` scans GPU cells synchronously, with a 512-codepoint query cap. | Partial | Make long searches incremental/nonblocking and test output invalidation, direction, alternate screen, Unicode, soft wraps, and selection/copy of matches. |
| Scrollback and scrolling | Configured byte-limited Ghostty pages plus `src/ScrollDetector.zig:1-168` provide smooth/inertial scrolling and idle compression. | `src/engine.cu` caps history at 4096 rows and `src/main.cu` handles wheel/page scrolling; no inertial detector or compression exists. | Partial | Replace the fixed row cap with a bounded byte policy, add smooth/inertial scroll and scrollbar state, and test resize/reflow, alternate screen, selection, and memory eviction. |
| PTY, child lifecycle, hold, and cleanup | `src/Pty.zig:1-204` owns spawn, winsize, wait, close, and process cleanup; `src/App.zig:497-561,1436-1660` adds signalfd, hold mode, and cgroup setup. | `src/main.cu` owns forkpty, pidfd-backed PTY waiter, SIGCHLD/SIGUSR1 wakeups, and cleanup; no hold mode or cgroup scope. | Partial | Test child exit versus PTY EOF, SIGHUP escalation, hold behavior, resize races, reload during output, and child cleanup after window close. |
| Packaging and terminal identity | `build.zig:121-188` installs the binary, desktop entry, icon, man pages, themes, and generated terminfo; `build.zig:20-53` generates protocol bindings. | `flake.nix` installs Cudaterm and many tests, but no desktop entry, icon, man page, or terminfo is installed. | Partial | Add desktop/terminfo/man artifacts and verify an installed package launches with a discoverable terminal entry and all declared protocols. |

## Prioritized acceptance tests

These tests turn the matrix into reviewable gates. They are ordered by user
impact and by dependency depth; shaping and keyboard work should land before
claiming rendered/input parity, while the clipboard patch can be accepted
independently.

| Priority | Acceptance test | Pass condition |
| --- | --- | --- |
| P0 | Nix host build/check plus patched GLFW compile | The repository's Nix build/check target exits zero; the patched GLFW Wayland sources dry-run cleanly and compile with `gcc -std=c99 -fsyntax-only` for `wl_init.c` and `wl_window.c`. GPU and visible-desktop runs are separate gates. |
| P0 | Native primary positive path | Under headless Sway/wlroots, copy a selection in Cudaterm, read it with a primary-selection client, then set an external primary owner and middle-click paste it. Both UTF-8 and `text/plain` offers work. |
| P0 | Native primary negative and bounds | Under a compositor without `zwp_primary_selection_device_manager_v1`, `glfwWaylandPrimarySelectionSupported()` is false, ordinary clipboard copy emits no GLFW error, set/get bridge calls are no-ops, and a stalled or over-64 MiB offer returns within the documented bound. |
| P0 | Kitty keyboard probe | A PTY child negotiates Kitty keyboard flags and captures exact bytes for arrows, function/media keys, Ctrl/Shift text, keypad, release/repeat, and modifier sides. Legacy mode remains unchanged when Kitty is disabled. |
| P0 | Shaping/cluster fixture | Render and copy Latin ligatures, Arabic/Indic clusters, combining marks, emoji ZWJ/modifier/VS16 sequences, missing-glyph fallback, and color glyphs. Cell hit testing and copied UTF-8 retain cluster boundaries. |
| P0 | Clipboard protocol matrix | Exercise standard clipboard, primary, OSC 52 set/read/query, Kitty clipboard MIME/status, invalid UTF-8, cancellation, and oversized transfers while the PTY remains responsive. |
| P1 | Graphics capability matrix | Exercise raw RGB/RGBA, zlib, PNG, file/shared-memory input, crop, scaling, animation, Unicode placeholders, multiple placements, z ordering, deletion, and scroll/reflow anchors against bounded dimensions. |
| P0 | Wayland IME bridge | With the private v2 helper, wait for `active`, grab the keyboard, verify a grabbed key produces no PTY byte, render `p UTF-8` only as transient preedit, then `c UTF-8` commits exactly once and clears the overlay; after helper exit the same key is ordinary typing. |
| P1 | Wayland desktop behavior | Verify fractional scale, cursor shape, activation, decorations, background effect, portal appearance, URI/file opening, notifications, and optional D-Bus-disabled startup. |
| P1 | Config/reload | Change font, theme, opacity, padding, scrollback, image limit, and key overrides; SIGUSR1 and the shortcut apply the same validated result without losing PTY, selection, or search state. |
| P1 | Search/history/scroll | Search long primary and alternate histories incrementally, invalidate on output, copy a match, preserve soft-wrap semantics, reflow after resize, evict by byte budget, and verify smooth/inertial scrolling. |
| P1 | Lifecycle | Verify child exit is distinguished from PTY EOF, output is drained, SIGHUP/KILL cleanup is bounded, hold mode (once added) keeps the window alive, and closing a window leaves no worker, fd, or child. |
| P2 | Package identity | Installed artifacts include desktop metadata, icon, man pages, themes, and terminfo; a remote shell recognizes the terminfo entry or the documented fallback is explicit. |

One independent task completed alongside this audit is
the native primary-selection path: `nix/glfw-primary-selection.patch` adds the
generated `primary-selection-unstable-v1` protocol to GLFW 3.4 and exposes
`glfwWaylandPrimarySelectionSupported`, `glfwSetWaylandPrimarySelectionString`,
and `glfwGetWaylandPrimarySelectionString`; `src/primary_selection.hpp` keeps
the Cudaterm call site backend-neutral. No callback is needed in Cudaterm:
GLFW's internal Wayland listeners receive offer/send events. A valid recent
Wayland seat serial is required when setting the selection, which GLFW tracks
from keyboard/pointer events.

## Verified implementation checkpoint

The 2026-09-09 implementation pass added GPU OSC 8 link metadata and exact
link actions, SIGUSR1 reload, quoted file drops, native primary selection,
Kitty cell scaling and independent placements, and Unicode cluster fixes.
A transient CUDA preedit overlay and native Wayland text-input-v3 bridge are
implemented; the private Sway IME acceptance gate is separate.

- `nix build . --no-link` and `nix flake check` succeeded. Package checks
  include input/configuration helpers and Unicode generator validation.
- `nix run .#graphics-test` passed 47 CUDA cases, including shared image
  storage, selective placement deletion, scroll/reflow, and screen switching.
- `nix run .#appearance-test` passed OSC 8 split feeds, exact targets,
  bounded eviction, history/reflow, and transient preedit pixel/cell checks.
- Unicode, styled, search, reflow, and selection CUDA suites passed after
  the grapheme changes. Engine, VT, plain, CSI, reference, mouse, charset,
  scrollback, and workspace suites passed on the integrated package through
  `nix shell`.
- The private Weston appearance fixture passed typography, reload/rejection,
  zoom, keyboard input, ordinary clipboard copy without the primary protocol,
  and copying a hidden OSC 8 target. Evidence:
  `bench/parity-final-window-20260909/`.
- The GLFW text-input-v3 patch and helper compile cleanly with Wayland CMake/C11
  checks; the live private Sway IME fixture remains the acceptance gate.
- The private Sway primary fixture passed ownership, a 278,528-byte UTF-8
  external paste, regular clipboard independence, application mouse capture,
  and Shift-middle-click override. A deliberately cancelled receiver initially
  killed Cudaterm with SIGPIPE; the same fixture passed after scoped signal
  handling was added. Evidence:
  `bench/parity-primary-cancellation-fixed-20260909/`.

All compositor tests used private headless instances. These checks establish
these named behaviors, not full Monstar parity. Full shaping/color-font
rendering, broader keyboard/graphics protocols, and desktop integration remain
separate gaps in the matrix.

The subsequent keyboard/IME integration also passed the CUDA CSI suite and a
forced hyperlink-allocation failure test (`nix run .#hyperlink-oom-test`).
The latter intercepts only the hyperlink table allocation, without consuming
available GPU memory, and verifies continued terminal text plus bounded retry
behavior. Protocol behavior is based on the
[Kitty keyboard specification](https://sw.kovidgoyal.net/kitty/keyboard-protocol/).
Only flag 1 is exposed; formatter support alone does not establish acceptance
of release, repeat, alternate-key, or associated-text reporting.

The private Sway acceptance run additionally passed native IME keyboard grabs,
preedit rendering without PTY writes, UTF-8 commit exactly once, overlay
restoration, composition in local search, protocol focus leave/return, and
ordinary typing after input-method exit. It also passed the keyboard flag-1
PTY matrix and all primary-selection checks in the same run. Evidence:
`bench/parity-ime-complete-20260909/result.json` and its preedit screenshots.
The repeatable entry point is `nix run .#window-ime-test`. Focus leave uses a
second private view because Sway retains text-input focus on an empty workspace.

IME preedit remains a cell-based overlay at the reported cursor position;
it clips at the right edge and does not implement a distinct composition
caret/selection or shaped glyph runs. Those rendering limits remain explicit
instead of treating protocol integration as full text-rendering parity.

Final delivery verification (2026-09-09): `nix build .` and `nix flake check`
passed. The final package passed 16 CUDA suites (engine, VT, plain, CSI,
Unicode, styled, workspace, reflow, search, selection, scrollback, charset,
mouse, reference, appearance, and hyperlink OOM) plus all 47 graphics cases.
Both packaged integration entry points passed:

- `nix run .#window-ime-test -- --output bench/parity-delivery-ime-20260909`
- `nix run .#window-appearance-test -- --output bench/parity-delivery-appearance-20260909`

No private compositor, fixture terminal, or blur-window child remained after
those tests. Concurrent font-cache/startup work and pre-existing benchmark and
Finix notes were preserved; this report attributes only the parity changes.
