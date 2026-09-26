# Ekko compatibility and memory — 2026-09-05

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

For a 1274×1368 RGBA image of deterministic grayscale noise (6.65 MiB decoded /
2.50 MiB compressed), warm medians were 983–1024 ms for upload processing and
942–982 ms for decode/commit before, versus 55–62 ms and 265–283 ms after:
about 6× faster overall. These synthetic timings include Python harness transport overhead and
share the desktop GPU; they are not application FPS. GPU decompression is still
substantially slower than CPU zlib on this difficult single stream; these
changes do not establish terminal/browser performance parity.

All temporary compressed storage is still freed after transfer. Shared decoder
workspace exists only during its kernel; the new streaming pointer/capacity
metadata adds 16 bytes to persistent device state. There is no retained CPU
image copy or additional framebuffer. Idle RSS (115.2 MiB) and NVIDIA process
GPU memory (316 MiB) were unchanged by the optimized decoder.

## Browser flicker correction

The initial desktop run exposed a presentation bug. Ekko deletes and replaces
browser images inside mode 2026. The window's 150 ms absolute deadline expired
during active uploads and displayed the temporarily empty image area. Reading
only the final mode bit also lost boundaries when one PTY read contained an
update end followed by another start.

The GPU now yields at synchronized-update completion; the window presents that
completed state before consuming the next frame's bytes. Pending PTY bytes stay
in the existing bounded transport buffer. An abandoned update expires after
one second without incoming progress. There is no extra framebuffer or retained
image copy. Presentation boundaries clear stale allocation-request metadata so
they cannot replay a previous upload's commit/free operation.

The local Ekko v2 daemon/client and pinned terminal-browser work with the CUDA
engine, including GPU-encoded mouse clicks, pane clipping, keyboard routing,
paste, scoped deletion, reconnect, zoom/swap, placement reuse and shutdown.
Ekko image panes present through CUDA → OpenGL → Wayland. This implements
Ekko's direct-transfer graphics requirements, not the full Kitty protocol;
unsupported features return a protocol error when replies are requested. Full
feature parity is not claimed.

## Memory

Three fresh idle windows per binary in the same private Weston compositor,
318×89 cells, RTX 4090. Medians, MiB:

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

The CUDA stack limit is 32 bytes for the current sm_89 build (maximum compiled
frame 24 bytes); the driver can grow it when required. This saved 184 MiB of
VRAM compared with the 1024-byte default.
Input and scan buffers grow on demand. History allocation tracks actual retained
rows and shrinks on reset/alternate-screen transitions without dropping retained
primary history. Images are decoded and retained in device allocations; upload
staging and replaced/deleted images are freed. GPU-requested image dimensions
also reserve history for cursor-moving placements before execution.

Host RAM cannot all move to VRAM: PTY/window APIs and NVIDIA/GL userspace driver
state execute on the CPU. The remaining footprint is measured, not asserted to
be a theoretical minimum.

## Performance limits

Two reversed, serial rounds of the old and new engine benchmark at 318×89
(`nix run .#bench -- --replies --cols 318 --rows 89 --warmup 2000 --repeats 30`)
show 64 KiB
feed/reply workloads about 2–6% slower by median: text 103→107 µs, ANSI
159→164 µs, Unicode 160→164 µs, DEC graphics 205→217 µs, and tabs
194–200→198–204 µs. Small-feed results are noisier; tabs cost about 11 µs more
and text regresses in both rounds. The graphics allocation handshake adds a
synchronous status read to feeds. This change does not establish a throughput
improvement or overall Foot/Monstar parity. The benchmark's “graphics” workload
is DEC text borders, not Kitty bitmap upload performance.
