# Finix desktop replacement — 2026-09-05

The NVIDIA desktop candidate is built as `result-finix/bin/cudaterm-finix`.
The tested workflows are shell/Neovim, the local Ekko v2 shell/browser workspace,
Wayland clipboard, application mouse input, synchronized graphics presentation,
and terminal/launcher routing in Finix. This is a desktop replacement candidate,
not full Foot/Monstar or Kitty protocol parity. No running system was activated
and no host default was changed.

## Run and integrate

From this checkout:

```sh
nix build --impure --file nix/finix-preview.nix --out-link result-finix
./result-finix/bin/cudaterm-finix
./result-finix/bin/cudaterm-finix -e nix run path:$HOME/dev/maintaining/ekko_v2#workspace -- \
  --current-terminal --session cuda-workspace
```

The preview reads the actual desktop font package, point size and pixel line
height from `~/finix`. It currently produces 10×24 logical cells: Departure Mono
Ultra Condensed at 16 pt, rasterized at 21 pixels, with Nerd Font symbols.
The 5.35 MiB alpha atlas is built by Nix and uploaded once to VRAM. Python,
Pillow and fonttools do not run in the terminal process. Unifont supplies missing
glyphs and combining marks. The configured background opacity is 0.82; explicit
cell backgrounds remain opaque. Existing Wallust `colors_monstar` files are read
at startup. Theme changes take effect in newly opened windows; live Wallust
file watching is not implemented.

The reusable integration is maintained in this repository:

- `flake.nix` exports `lib.mkFinixPackage` and `finixModules.default`.
- `nix/finix-package.nix` builds the face, wrapper and desktop entry.
- `nix/finix-module.nix` selects `cudaterm-finix` for `TERMINAL` and the launcher,
  installs the package, and rejects enablement without the NVIDIA driver.
- `nix/finix-evaluate.nix` checks the full desktop configuration, launcher,
  environment, explicit terminal overrides, and the unchanged AMD laptop.

For a persistent Finix configuration, add a flake input:

```nix
inputs.cudaterm.url = "path:/home/y0usaf/dev/developing/cudaterm";
```

Then include this module on the NVIDIA desktop only:

```nix
{ config, flakeInputs, ... }: {
  imports = [ flakeInputs.cudaterm.finixModules.default ];
  user.ui.cudaterm = {
    enable = true;
    package = flakeInputs.cudaterm.lib.mkFinixPackage {
      fontFile = "${config.user.ui.fonts.mainFont}/share/fonts/truetype/DepartureMonoUltraCondensed-Regular.ttf";
      fontSize = config.user.appearance.termFontSize;
      lineHeight = 24;
    };
  };
}
```

Keep Monstar enabled as a fallback. Disabling `user.ui.cudaterm.enable` restores
Finix's existing Monstar terminal and launcher defaults. Explicit terminal
choices override the cudaterm default. Do not enable it on the AMD Framework;
the current binary targets NVIDIA Ada (`sm_89`).

The local preview/evaluation does not require these edits or a system rebuild:

```sh
nix eval --impure --json --file nix/finix-evaluate.nix
```

The previous untracked preview under `~/finix/packages` disappeared during the
session; the integration files now live alongside cudaterm instead. The only remaining Finix edit from this work excludes the existing
Vercel package/test helpers from automatic module discovery. The unrelated
Vercel changes were preserved.

## Reliability and responsiveness

The GPU now handles OSC palette/default-color updates and queries, resets and
window titles. Indexed colors remain symbolic, so changing a palette recolors
existing cells and history without changing explicit RGB colors. Custom cell
sizes flow through rendering, graphics placement, pixel mouse reports and CSI
cell-size queries. Window identity and working directory support the Finix
launcher and terminal commands.

Long image decoding runs on a nonblocking CUDA stream while the window handles
keyboard/mouse events and writes PTY input. The parser and image commit wait for
decoding, keeping partial images off screen. Resize is deferred until the decode
finishes. Preloading only input kernels avoids first-use lazy-loading stalls;
CUDA parsing, base64, zlib and rasterization remain on the GPU. No additional
framebuffer, persistent image staging copy, or global eager-loading setting was
introduced. See NVIDIA's [lazy-loading discussion](https://docs.nvidia.com/cuda/cuda-programming-guide/04-special-topics/lazy-loading.html)
for why loading a kernel can synchronize concurrent work.

The final headless decode probe recorded 104 input callbacks during a 218.4 ms
upload; the slowest callback took 1.75 ms. A separate real Wayland Ctrl-Space event
reached the PTY during a longer decode in 0.1 ms. These are input-delivery and
callback measurements, not physical display latency or sustained browser FPS.

The Wayland clipboard regression exposed GLFW 3.4 discarding the coordinates
from pointer-enter events. The packaged GLFW patch delivers that position before
the first click. Shift-selection now passes a real compositor clipboard
roundtrip with CJK and combining characters. A 393,216-byte external UTF-8 paste
also arrives exactly, with bracketed-paste delimiters, under PTY backpressure.
Horizontal wheel reports, alternate-screen wheel-to-arrow fallback and keypad
Enter are supported. Large rendering buffers shrink after substantial window
shrinks, and copy buffers are sized to the selected cells.

## Recorded checks

The following commands exited zero. GPU checks ran through Nix; desktop tests
used private headless Weston with a virtual seat, never the user's input devices.

```sh
nix build .
nix flake check
nix run .#sync-test
nix develop . --command bash -c 'set -e; for name in engine vt csi plain styled reference unicode mouse scrollback charset selection workspace appearance; do ./result/bin/cudaterm-${name}-test; done'
nix develop . --command python3 tests/test_metrics.py --host ./result/bin/cudaterm-engine-host
nix develop . --command python3 tests/test_nvim.py --host ./result/bin/cudaterm-engine-host --nvim /run/current-system/sw/bin/nvim --output bench/finix-nvim-final.json
nix develop . --command python3 tests/test_ekko.py --host ./result/bin/cudaterm-engine-host --ekko-source /home/y0usaf/dev/maintaining/ekko_v2 --ekko /home/y0usaf/dev/maintaining/ekko_v2/result/bin/ekko
nix develop . --command python3 tests/test_browser.py --host ./result/bin/cudaterm-engine-host --ekko /home/y0usaf/dev/maintaining/ekko_v2/result/bin/ekko --browser /home/y0usaf/.local/state/ekko-v2/benchmark/bin/terminal-browser --output bench/finix-browser
nix run .#headless-test -- --terminal ./result-finix/bin/cudaterm-finix --cols 254 --rows 58 --ekko /home/y0usaf/dev/maintaining/ekko_v2/result/bin/ekko --output-dir bench/finix-window-configured
nix eval --impure --json --file nix/finix-evaluate.nix
```

The 36-case graphics suite also passed under Compute Sanitizer memcheck. Focused
memcheck and racecheck of simultaneous decoder/input operations, plus appearance
memcheck, exited zero with no errors/hazards. Instrumented timings are excluded
from latency claims. The graphics suite's instrumented binary preceded the final
GLFW-only fix; the final concurrency and appearance checks use the final binary.

Evidence: `bench/finix-validation-final.log`, `finix-sync-clipboard.log`,
`finix-graphics-sanitized.log`, `finix-graphics-memcheck-4591.log`,
`finix-concurrent-{memcheck,racecheck}.log`, `finix-appearance-memcheck.log`,
`finix-module-final.json`, and `finix-window-configured/headless-window.json`.
Weston GL screenshooter captures are bottom-up, including compositor decorations.

Final terminal: `/nix/store/fv9gqwbv3sj4jb8kqphbxnjf0rz2c3px-cudaterm-0.1.0`.
Configured package: `/nix/store/hxq2lahxjkfc36qc4f1fkf0zbif612mp-cudaterm-finix`.
Tested Ekko: `/nix/store/akpgwa1vfjw989cyfipzc6arm9p2bbbw-ekko-0.1.0`.

## Memory and remaining differences

At 254×58 cells with the configured font/transparency, three one-second idle
samples reported 115.4–115.6 MiB RSS, 71.7–71.9 MiB private host memory and 312 MiB
NVIDIA process GPU memory. No CPU time was recorded in those samples. These
figures exclude Weston, Ekko and browser descendants. The matched default-font
318×89 comparison earlier in this pass stayed at 316 MiB GPU and approximately
115.5 MiB RSS. The configured and default-font measurements use different grids;
they are not a controlled before/after font-memory comparison.

GPU terminal buffers are a small part of total NVIDIA process memory. CUDA/GL
context and driver allocations still use both host RAM and VRAM; moving the
screen to VRAM cannot remove the host driver or Linux PTY/window machinery.
This is a substantial reduction from the initial build, but not Foot-level
memory use or a claim that further savings are impossible.

Known differences remain: no full grapheme shaping or color emoji sequences,
no history reflow/search or double-click word selection; local copying still
preserves physical row breaks on wrapped lines. Kitty support covers Ekko's
RGB/RGBA direct/zlib uploads, crop/place/delete operations, not PNG, shared-memory
transport, animation, scaling, placeholders or multiple placements per image.
Fractional scaling resamples the baked face instead of rerasterizing outlines.
Physical display latency and a long interactive daily-use soak remain unmeasured.
