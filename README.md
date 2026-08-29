# cudaterm

Terminal emulator whose render pipeline runs on the GPU. PTY output is parsed
into a cell grid on the CPU (processes are OS objects, so the parser is CPU by
definition). Everything downstream is CUDA: one kernel rasterizes every pixel
of the frame — glyphs from a device-side atlas, box drawing and block/shade
characters procedurally, bold double-strike, underline, inverse, block cursor
— and writes through CUDA-GL interop into the window texture.

Reference implementation: `ref/foot` (suckless Wayland terminal). The box
drawing and wide-char approach mirror foot's; foot draws with pixman on CPU,
here the same geometry lives in the CUDA kernel.

## Run

    nix run .            # opens a window running $SHELL
    nix run . -- --test  # headless: renders a canned frame, prints ASCII
    CUDATERM_PROBE=1 nix run .   # exits after 30 frames, dumps the parsed grid

## What works

- VT102 core: CUP/cuu/cud/cuf/cub, ED/EL/ECH/ICH/DCH/IL/DL, SU/SD,
  DECSTBM scroll regions, RI/IND/NEL, DECSC/DECRC, SGR (bold, underline,
  inverse, 16/256-color, truecolor), OSC title skipping.
- 1000-line scrollback ring on the CPU grid; kernel renders through it by
  offset, so scrolling needs no data movement.
- Wide chars (wcwidth) with paired cells; combining chars skipped.
- Glyphs: FreeType + Unifont (PCF) rasterized on demand into a 16384-slot
  GPU atlas; full BMP coverage including CJK.
- Box drawing U+2500-0x257F (light/heavy arms), blocks/shades/quadrants
  U+2580-0x259F drawn procedurally in-kernel, always pixel-crisp.
- Dirty-row grid upload; atlas slots uploaded once at raster time.

## Limits (v2)

- Fixed 120x40 grid, 960x640 window; no resize or reflow.
- 1-bit glyphs: no antialiasing or subpixel positioning.
- No mouse, selection, clipboard, scrollback viewing, or alt screen.
- Atlas eviction is wrap-around, not LRU.
- Double-line box drawing (U+2550-256C) falls back to adjacent singles.
