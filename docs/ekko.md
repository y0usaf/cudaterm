# Ekko compatibility and memory — 2026-09-05

## Follow-up decoder experiments

The next hillclimb retained the proven `zvsnvj0...` build. An eight-byte coarse
output-to-token index appeared faster in separate runs, but alternating old/new
samples showed no overall noisy-image gain and a solid-image regression
(130 to 152 ms). A smaller single-token shortcut was also flat: 146 ms for
solid images and roughly 891–895 ms for noisy images. Both were reverted.
These timings share an active desktop GPU and should not be compared directly
with earlier, less busy measurements below.

`bench/graphics_pair_bench.py` now alternates two headless hosts in reversed
order on successive samples, checks rendered pixels, and reports allocations.
Run through `nix develop . --command python3 bench/graphics_pair_bench.py
--reference /path/to/baseline/bin/cudaterm-engine-host
--host ./result/bin/cudaterm-engine-host --output bench/comparison.json`.
It collects twelve samples per host/case and excludes the first two from
medians. This reduces time drift; it does not remove desktop contention.
Results and validation scope are in `bench/hillclimb-decode-review.json`.
All candidates passed `nix build .` and `nix run .#graphics-test` (36 cases).
Production source and the running user window remain on the proven decoder,
with no additional retained memory.

## CUDA graphics performance update

The upload path now copies opaque APC payloads cooperatively and decodes base64
in parallel. Continuation chunks remain on the device while reserved staging
has capacity; the host is involved for growth, final commit, and cleanup. Active
image uploads also bypass the text-classification kernels. CPU code still
transports bytes and manages allocations; it does not parse/decode images.

The bounded CUDA inflater uses 128 threads, parallel Huffman token speculation,
and a 32 KiB shared sliding window. Only the actual token chain is committed;
selected tokens validate bitstream bounds, distances and output limits. Threads
resolve LZ references against immutable history, then update that history.
Highly compressed streams use direct token decoding with parallel copying to
avoid expensive speculative work. Stored blocks, cross-block history, final
sizes and Adler checksums are still checked.

The reproducible benchmark is `bench/graphics_bench.py`: a 1274×1368 RGBA image,
both solid color and deterministic grayscale noise. The latter is 6.65 MiB
decoded / 2.50 MiB compressed. Its cost includes Python transport overhead and
shares the desktop GPU; these are synthetic image timings, not application FPS.
Use `nix develop . --command python3 bench/graphics_bench.py --host
./result/bin/cudaterm-engine-host --output bench/graphics-current.json`.
Each sample also checks rendered pixels and reports retained device allocations.

All temporary compressed storage is still freed after transfer. Shared decoder
workspace exists only during its kernel; the new streaming pointer/capacity
metadata adds 16 bytes to persistent device state. There is no retained CPU
image copy or additional framebuffer.

Two serial rounds with reversed before/after order are recorded in
`bench/graphics-final-comparison.json` and its four referenced raw files.
Warm medians for the difficult image were 983–1024 ms for upload processing and
942–982 ms for decode/commit before, versus 55–62 ms and 265–283 ms after:
about 6× faster overall. These matched results supersede the earlier unpaired
live-GPU estimate. Dense streams retain a direct-token path with parallel copying. GPU decompression is
still substantially slower than CPU zlib on this difficult single stream;
these changes do not establish terminal/browser performance parity.

The final build is `/nix/store/zvsnvj0fqij9rvwx009p446xvbg2zqzp-cudaterm-0.1.0`
(`hxvcwhmssgk82khscibgnl725bbbll65-cudaterm-0.1.0.drv`). Nix build/flake
checks, 36 graphics cases, synchronized presentation, and the engine/VT/CSI/
plain/styled/reference/Unicode/mouse/scrollback/charset/selection/workspace
suites exited zero. Real Ekko and browser pixel/input integration also passed;
see `bench/graphics-fast-integration.log`, `bench/graphics-fast-browser.json`
and `bench/graphics-fast-sync.log`. The expanded cases cover window wrap,
stored/Huffman block transitions and different feed boundaries.

Compute Sanitizer memcheck on all 36 cases exited zero with zero errors for
the decoder variant using 32 threads on dense streams and 128 otherwise.
Focused racecheck also exited zero with zero hazards/warnings, covering dense
and noisy uploads, continuation storage growth, parallel payload/decode paths,
synchronized commits, rasterization, and reset cleanup. Both used
`--error-exitcode 99`, without kernel exclusions. Logs are
`bench/graphics-fast-memcheck.log` and
`bench/graphics-fast-racecheck-focused.log`. An earlier unfiltered full-suite
racecheck was stopped during the slow split-feed sweeps; it is not counted as
a completed check.

Focused memcheck and racecheck were also rerun against the final 128-thread
build; both exited zero with zero errors/hazards
(`bench/graphics-final-{memcheck,racecheck}.log`). The private-compositor memory
comparison in `bench/graphics-fast-window/headless-window.json` measured
115.2 MiB idle RSS and 316 MiB NVIDIA process GPU memory for both the previous
build and the optimized decoder variant. Final stage timings and allocation
counts are in `bench/graphics-final-current.json`.

## Browser flicker correction

The initial desktop run exposed a presentation bug missed by the static pixel
tests below. Ekko deletes and replaces browser images inside mode 2026. The
window's 150 ms absolute deadline expired during active uploads and displayed
the temporarily empty image area. Reading only the final mode bit also lost
boundaries when one PTY read contained an update end followed by another start.

The GPU now yields at synchronized-update completion; the window presents that
completed state before consuming the next frame's bytes. Pending PTY bytes stay
in the existing bounded transport buffer. An abandoned update expires after
one second without incoming progress. There is no extra framebuffer or retained
image copy. Presentation boundaries clear stale allocation-request metadata so
they cannot replay a previous upload's commit/free operation.

`nix run .#sync-test` checks actual private-compositor pixels during slow updates
and a coalesced end/start/delete. `bench/sync-before.log` records the old binary
showing zero red pixels where the last complete red image should remain.
The graphics suite also exercises repeated synchronized uploads and verifies
that presentation barriers preserve image allocation ownership.

The corrected build is
`/nix/store/ph69lq4s66awap1an7wkbpp40fpkkc5x-cudaterm-0.1.0`
(`2m668rk9xcnc10wwdz3klvi64wv9aid7-cudaterm-0.1.0.drv`). Nix build, flake
checks, sync presentation, 30 graphics cases, mouse/frame-boundary tests, and
engine/VT/CSI/plain/styled/reference suites passed. Real Ekko and browser tests
also passed; see `bench/sync-after.log`, `bench/sync-integration.log` and
`bench/sync-browser.json`. The original desktop session was reattached to this
build with its shell and browser processes preserved.
Compute Sanitizer memcheck on the complete 30-case CUDA graphics suite, without
a kernel filter and with `--error-exitcode 99`, also exited zero with zero errors
(`bench/sync-memcheck.log`).

The local Ekko v2 daemon/client and pinned terminal-browser work with the CUDA
engine. `bench/ekko-browser.png` shows the real browser beside a shell after a
GPU-encoded mouse event clicked a DOM button. `bench/ekko-browser.json` records
the exact binaries, 20 uploads, six pixel checks, and zero Ekko graphics errors.
The broader PTY integration also checks pane clipping, keyboard routing, paste,
scoped deletion, reconnect, zoom/swap, placement reuse and shutdown.

`bench/headless-window.png` separately verifies actual CUDA → OpenGL → Wayland
presentation of two Ekko image panes in private Weston. Neither test touches the
user's desktop. Browser raster correctness and compositor presentation are
separate checks; interactive desktop use and full feature parity are not claimed.

## Memory

Three fresh idle windows per binary in the same private Weston compositor,
318×89 cells, RTX 4090. Medians, MiB; raw samples and resolved binaries are in
`bench/headless-window.json`:

| Terminal parent | Previous | Current |
|---|---:|---:|
| RSS | 232.6 | 115.0 |
| PSS | 156.3 | 79.6 |
| Private RAM | 135.3 | 71.5 |
| NVIDIA process GPU memory | 484 | 316 |

The scope excludes compositor, Ekko, shell and browser memory. RSS includes
shared mappings; NVIDIA's compute-process figure is not the allocator's exact
live-byte count. Loaded applications and accumulated history can increase use.

CUDA uses one default stream, so runtime defaults request one connection and
quarter-size launch queues. NVIDIA-only EGL discovery on NixOS avoids loading
Mesa/LLVM alongside NVIDIA. Disabling GLFW libdecor avoids loading GTK; GLFW's
fallback decorations remain available. Explicit CUDA/EGL environment settings
are honored, and configuration occurs after forking the child.

The CUDA stack limit is 128 bytes for the current sm_89 build (maximum compiled
frame 96 bytes); the driver can grow it when required. A paired probe saved
168 MiB of VRAM compared with the 1024-byte default. See
`bench/memory-stack-{default,128}.jsonl` and `bench/graphics-resources.txt`.
Input and scan buffers grow on demand. History allocation tracks actual retained
rows and shrinks on reset/alternate-screen transitions without dropping retained
primary history. Images are decoded and retained in device allocations; upload
staging and replaced/deleted images are freed. GPU-requested image dimensions
also reserve history for cursor-moving placements before execution.

Host RAM cannot all move to VRAM: PTY/window APIs and NVIDIA/GL userspace driver
state execute on the CPU. The remaining footprint is measured, not asserted to
be a theoretical minimum.

## Reproduce

```sh
nix build .
nix flake check
nix run .#graphics-test
nix run .#mouse-test
nix develop . --command python3 tests/test_ekko.py \
  --host ./result/bin/cudaterm-engine-host \
  --ekko-source "$HOME/dev/maintaining/ekko_v2" \
  --ekko "$HOME/dev/maintaining/ekko_v2/result/bin/ekko"
nix develop . --command python3 tests/test_browser.py \
  --host ./result/bin/cudaterm-engine-host \
  --ekko "$HOME/dev/maintaining/ekko_v2/result/bin/ekko" \
  --browser "$HOME/.local/state/ekko-v2/benchmark/bin/terminal-browser" \
  --output bench/ekko-browser
nix run .#headless-test -- \
  --ekko "$HOME/dev/maintaining/ekko_v2/result/bin/ekko"
nix run .#memory-probe -- --egl
```

The browser wrapper is provisioned by Ekko's existing workspace launcher. The
browser test uses a local HTTP page and isolated profile; it needs that wrapper
and its already-built browser runtime. Headless tests need the NVIDIA GPU,
including EGL/GL interop for the compositor test. `--reference /path/to/cudaterm`
adds a previous binary to the window memory comparison.

Graphics coverage includes raw/stored/fixed/dynamic deflate streams, RGB/RGBA,
one-byte and split feeds, overlapping LZ copies, alpha, crop/offset placement,
corrupt input, bounded dimensions, reuse/deletion, alternate-screen cleanup,
and compressed tall images that scroll more rows than their input byte count.
Existing terminal regression suites remain applicable. This implements Ekko's
direct-transfer graphics requirements, not the full Kitty protocol; unsupported
features return a protocol error when replies are requested.

## Validation and performance limits

For `/nix/store/yjhrgsw1981fqqaf4afi972aaqfi9adi-cudaterm-0.1.0`
(derivation `srp17yr76l3ps0zxr7yqfgyhkhh1pmcg-cudaterm-0.1.0.drv`),
`nix build .`, `nix flake check`, `nix run .#graphics-test` (29 cases), and the
Nix-shell engine/plain/VT/CSI/styled/Unicode/workspace/selection/scrollback/
charset/mouse/reference binaries all exited zero. The same Nix-shell command
ran both real Ekko and browser tests; output is `bench/ekko-final-validation.log`.
Compute Sanitizer memcheck and racecheck on the Nix-built graphics harness,
filtered to `--kernel-name kns=graphics_ --error-exitcode 99`, exited zero with
zero errors/hazards; logs are `bench/graphics-{memcheck,racecheck}.log`.

The final flake excludes Python bytecode from its source fileset so running
local integration tests cannot silently change the build input. Its output is
`/nix/store/vawcwy3ik0by5aprbyw36cfjglaczsic-cudaterm-0.1.0` (derivation
`4pjnbwlx799dwnfhciwj689sac98p76f-cudaterm-0.1.0.drv`). The engine-host binary
is byte-for-byte identical to the sanitizer-tested output above (SHA256
`b8deff494c9941471f278358e1b850e6bcd13a308478707e452840f51f4e668c`).
All terminal suites, the 29-case graphics suite, Ekko/browser integration and
the private compositor comparison were rerun against this final output and
exited zero, as did `nix flake check`.

`bench/ekko-headless-throughput.json` has two reversed, serial rounds of the old
and new Nix-built engine benchmarks, 2000 warmups and 30 samples per case.
For 64 KiB feed/reply workloads, new median times are about 2–6% slower:
text 103→107 µs, ANSI 159→164 µs, Unicode 160→164 µs, DEC graphics 205→217 µs,
and tabs 194–200→198–204 µs. Small-feed results are noisier; tabs cost about
11 µs more and text regresses in both rounds. The graphics allocation handshake
adds a synchronous status read to feeds. Memory savings and Ekko support are
established; this change does not establish a throughput improvement or overall
Foot/Monstar parity. The benchmark's “graphics” workload is DEC text borders,
not Kitty bitmap upload performance.
