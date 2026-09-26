# Startup optimization — 2026-09-09

The configured Finix launcher now prepares all four font styles during its Nix
build and loads them on the first launch. Runtime font changes retain the disk
cache and concurrent generation path.

The paired run used the same 80×24 configuration, Departure Mono at 21 px,
Nerd Font fallback, and a private Weston compositor with its startup fade disabled.
Each variant had five launches with an empty user font cache and fifteen warm
launches. Cache directories existed for every variant. The measurement is process
launch to the first completed GL texture swap, with a fixed child command.

| Build | Empty user font cache | Warm font cache | Warm process CPU | Settled PSS |
|---|---:|---:|---:|---:|
| Previous cached implementation | 649.6 ms | 138.3 ms | 145.9 ms | 79.9 MiB |
| Optimized runtime cache | 217.6 ms | 75.5 ms | 115.2 ms | 80.2 MiB |
| Configured launcher with prepared fonts | 68.3 ms | 63.7 ms | 113.4 ms | 80.2 MiB |

All values are medians. The configured launcher reduced the empty-user-cache
measurement by 89.5% and warm startup by 53.9%. Warm CPU use fell by 22.3%.
Overlapping initialization increased the sampled peak RSS from 129.2 to
140.3 MiB; settled PSS differed by 0.22 MiB in this run.

The desktop Wayland smoke runs completed their first swaps in 85.5, 68.2, and
66.7 ms. An X11 smoke run completed in 92.3 ms. These timings exclude physical
scanout and interactive-shell initialization. Empty user cache means the font
cache was removed; OS file caches and GPU state were retained. The prepared Nix
atlas remains available in this case. PSS depends on shared mappings and other
processes; peak RSS was sampled every 5 ms.

The retained changes are:

- XXH3 checksums and direct resolution of explicit font paths.
- Four independent FreeType style workers, with deferred execution available
  when thread creation is unavailable. Workers finish before the PTY fork.
- Direct uploads from each validated face into one GPU allocation, removing the
  extra host-side concatenation buffer.
- CUDA initialization on a joined worker while the main thread creates the GL
  window/context. Startup failures still reap the child and release resources.
- GL 2.1 entry points through libGL, removing the GLEW dependency and setup.
- Renderer/dependency fingerprints and immutable Nix store identities, allowing
  unrelated builds and substituted packages to reuse prepared fonts.
- A CPU-only Nix cache builder for the configured font, with runtime fallback
  for other sizes and font overrides.

All four prepared font atlases are byte-identical to the original serial
renderer, including bold, italic, bold italic, and fallback symbols. The cache handles
invalidation, truncated and corrupted entries, unwritable caches, prepared-cache
reuse and concurrent writers. A custom
20 px override generated its own cache and reused it on the next launch. LZ4
cache compression was rejected after its load/hash probe took 7.52 ms versus
3.81 ms for uncompressed data.

Most remaining startup time is in NVIDIA/GLFW context setup and CUDA/GL buffer
registration. The current implementation preserves the pre-fork font validation
and joins all initialization work before rendering. Larger architectural changes
to process or graphics-context lifetime were outside the retained optimizations.

Measure a launcher with the command below. `args.json` is a JSON array of
terminal options without a child command; repeat `--terminal label=path` to
compare builds.

```sh
nix build --impure --file nix/finix-preview.nix --out-link result-finix
nix run .#startup-benchmark -- \
  --terminal prepared=$PWD/result-finix/bin/cudaterm-finix \
  --args args.json \
  --samples 15 --cold-samples 5 --output /tmp/cudaterm-startup-recheck
```
