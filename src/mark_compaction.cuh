#pragma once

#include "mark_pool.cuh"
#include <stdexcept>
#include <cub/device/device_scan.cuh>

namespace mark_compaction_parallel {

inline void check(cudaError_t error) {
  if (error != cudaSuccess) throw std::runtime_error(cudaGetErrorString(error));
}

__host__ __device__ inline bool use_serial(uint32_t n, uint32_t root_count) {
  return n <= 512 && root_count <= 256;
}

// Prefix inputs are bounded nonnegative 0/1 counts (sum <= 1<<20), so reuse
// the engine's existing signed-int CUB scan storage and allocation.
static_assert(sizeof(int) == sizeof(uint32_t), "CUB scan type sizes differ");
inline cudaError_t scan_prefix(void *temporary, size_t &bytes,
                               uint32_t *map, uint32_t n) {
  return cub::DeviceScan::InclusiveSum(
      temporary, bytes, reinterpret_cast<int *>(map),
      reinterpret_cast<int *>(map), static_cast<int>(n));
}

__global__ void init_kernel(mark_pool::Arena a, uint32_t *map,
                            uint32_t *jump, uint32_t n) {
  uint32_t i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i >= n) return;
  map[i] = 0u;
  jump[i] = 0u;
  if (*a.status != mark_pool::OK) return;
  uint32_t parent = a.nodes[i].parent;
  bool valid = parent < i + 1;
  map[i] = valid ? 0u : 2u;
  jump[i] = valid ? parent : 0u;
}

__global__ void begin_kernel(mark_pool::Arena a, uint32_t n) {
  if (blockIdx.x || threadIdx.x) return;
  *a.status = (n <= a.capacity && a.used && *a.used == n)
                  ? mark_pool::OK : mark_pool::MALFORMED;
}

__global__ void seed_kernel(mark_pool::Arena a, mark_pool::RootSpan *spans,
                            uint32_t span_count, uint32_t root_count,
                            uint32_t n, uint32_t *map) {
  uint32_t index = blockIdx.x * blockDim.x + threadIdx.x;
  if (index >= root_count) return;
  if (n > a.capacity || !a.used || *a.used != n) return;
  uint32_t left = index;
  mark_pool::RootSpan span{};
  bool found = false;
  for (uint32_t i = 0; i < span_count; ++i) {
    if (left < spans[i].count) {
      span = spans[i]; found = true; break;
    }
    left -= spans[i].count;
  }
  if (!found) { atomicExch(a.status, mark_pool::MALFORMED); return; }
  uint32_t ref = mark_pool::head(span.cells[left]);
  if (!ref) return;
  if (ref > n || ref > a.capacity || !a.used || ref > *a.used) {
    atomicExch(a.status, mark_pool::MALFORMED); return;
  }
  atomicOr(map + ref - 1, 1u);
}

__global__ void jump_kernel(mark_pool::Arena a, uint32_t *map,
                            const uint32_t *jump, uint32_t *next, uint32_t n) {
  uint32_t i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i >= n) return;
  // A failed precondition or root validation leaves the disposable buffers
  // uninitialized; do not inspect them after status becomes malformed.
  // The status pointer is carried through the arena by the caller.
  if (*a.status != mark_pool::OK) return;
  uint32_t ref = jump[i];
  uint32_t flags = atomicOr(map + i, 0u);
  if ((flags & 1u) && ref)
    atomicOr(map + ref - 1, 1u);
  next[i] = ref ? jump[ref - 1] : 0u;
}

__global__ void validate_kernel(mark_pool::Arena a, uint32_t *map,
                                uint32_t n) {
  uint32_t i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i >= n) return;
  if ((map[i] & 3u) == 3u) atomicExch(a.status, mark_pool::MALFORMED);
  map[i] &= 1u;
}

__global__ void scatter_kernel(mark_pool::Arena a, uint32_t *map,
                               mark_pool::Node *scratch, uint32_t n) {
  uint32_t i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i >= n || *a.status != mark_pool::OK) return;
  uint32_t here = map[i], before = i ? map[i - 1] : 0;
  if (here == before) return;
  uint32_t old_parent = a.nodes[i].parent, parent = old_parent ? map[old_parent - 1] : 0;
  scratch[here - 1] = {a.nodes[i].cp, parent};
}

__global__ void copy_kernel(mark_pool::Arena a, const mark_pool::Node *scratch,
                            const uint32_t *map, uint32_t n) {
  uint32_t i = blockIdx.x * blockDim.x + threadIdx.x;
  uint32_t count = n ? map[n - 1] : 0;
  if (i < count && *a.status == mark_pool::OK) a.nodes[i] = scratch[i];
}

__global__ void rewrite_kernel(mark_pool::Arena a, mark_pool::RootSpan *spans,
                               uint32_t span_count, uint32_t root_count,
                               uint32_t *map, uint32_t n) {
  uint32_t index = blockIdx.x * blockDim.x + threadIdx.x;
  if (index >= root_count || *a.status != mark_pool::OK) return;
  uint32_t left = index; mark_pool::RootSpan span{}; bool found = false;
  for (uint32_t i = 0; i < span_count; ++i) {
    if (left < spans[i].count) { span = spans[i]; found = true; break; }
    left -= spans[i].count;
  }
  if (!found) return;
  uint32_t ref = mark_pool::head(span.cells[left]);
  if (!ref) return;
  mark_pool::set_head(span.cells[left], map[ref - 1]);
}

__global__ void commit_kernel(mark_pool::Arena a, const uint32_t *map,
                              uint32_t n) {
  if (blockIdx.x || threadIdx.x || atomicOr(a.status, 0u) != mark_pool::OK) return;
  *a.used = n ? map[n - 1] : 0;
}

__global__ void serial_kernel(mark_pool::Arena a, mark_pool::RootSpan *spans,
                              uint32_t span_count, uint32_t root_count,
                              uint32_t n, uint32_t *map,
                              mark_pool::Node *scratch) {
  if (blockIdx.x || threadIdx.x) return;
  if (n > a.capacity || !a.used || *a.used != n) {
    *a.status = mark_pool::MALFORMED;
    return;
  }
  *a.status = mark_pool::OK;
  for (uint32_t i = 0; i < n; ++i) map[i] = 0xffffffffu;
  for (uint32_t si = 0; si < span_count; ++si) {
    for (uint32_t j = 0; j < spans[si].count; ++j) {
      uint32_t ref = mark_pool::head(spans[si].cells[j]);
      for (uint32_t steps = 0; ref; ++steps) {
        if (ref > n || a.nodes[ref - 1].parent >= ref || steps > n) {
          *a.status = mark_pool::MALFORMED; return;
        }
        if (map[ref - 1] == 0xfffffffeu) break;
        map[ref - 1] = 0xfffffffeu;
        ref = a.nodes[ref - 1].parent;
      }
    }
  }
  uint32_t out = 0;
  for (uint32_t i = 0; i < n; ++i)
    if (map[i] == 0xfffffffeu) map[i] = ++out;
  uint32_t write = 0;
  for (uint32_t i = 0; i < n; ++i) {
    if (map[i] == 0xffffffffu) continue;
    uint32_t parent = a.nodes[i].parent ? map[a.nodes[i].parent - 1] : 0;
    scratch[write++] = {a.nodes[i].cp, parent};
  }
  for (uint32_t i = 0; i < write; ++i) a.nodes[i] = scratch[i];
  for (uint32_t si = 0; si < span_count; ++si) {
    for (uint32_t j = 0; j < spans[si].count; ++j) {
      uint32_t ref = mark_pool::head(spans[si].cells[j]);
      if (ref) mark_pool::set_head(spans[si].cells[j], map[ref - 1]);
    }
  }
  *a.used = write;
}

// Caller owns map/scratch/scan_temp and performs the final stream sync.
// RootSpan ranges must be non-overlapping; each logical root is visited once.
// scratch is reinterpreted as two uint32[n] pointer-jump buffers before the
// prefix scan, then as Node[n] compacted output after the scan.
static void parallel_compact(mark_pool::Arena a, mark_pool::RootSpan *spans,
                             uint32_t span_count, uint32_t n,
                             uint32_t root_count, uint32_t *map,
                             mark_pool::Node *scratch, void *scan_temp,
                             size_t scan_bytes) {
  if (use_serial(n, root_count)) {
    serial_kernel<<<1, 1>>>(a, spans, span_count, root_count, n, map, scratch);
    check(cudaGetLastError());
    return;
  }
  begin_kernel<<<1, 1>>>(a, n);
  check(cudaGetLastError());
  uint32_t *jump_a = reinterpret_cast<uint32_t *>(scratch);
  uint32_t *jump_b = n ? jump_a + n : nullptr;
  constexpr uint32_t block = 256;
  if (n) {
    init_kernel<<<(n + block - 1) / block, block>>>(a, map, jump_a, n);
    check(cudaGetLastError());
  }
  if (root_count)
    seed_kernel<<<(root_count + block - 1) / block, block>>>(a, spans, span_count, root_count, n, map), check(cudaGetLastError());
  for (uint32_t stride = 1; stride < n; stride <<= 1) {
    jump_kernel<<<(n + block - 1) / block, block>>>(a, map, jump_a, jump_b, n);
    check(cudaGetLastError());
    uint32_t *tmp = jump_a; jump_a = jump_b; jump_b = tmp;
  }
  if (n) {
    validate_kernel<<<(n + block - 1) / block, block>>>(a, map, n);
    check(cudaGetLastError());
    check(scan_prefix(scan_temp, scan_bytes, map, n));
    scatter_kernel<<<(n + block - 1) / block, block>>>(a, map, scratch, n);
    check(cudaGetLastError());
  }
  if (n)
    copy_kernel<<<(n + block - 1) / block, block>>>(a, scratch, map, n), check(cudaGetLastError());
  if (root_count)
    rewrite_kernel<<<(root_count + block - 1) / block, block>>>(a, spans, span_count, root_count, map, n), check(cudaGetLastError());
  commit_kernel<<<1, 1>>>(a, map, n);
  check(cudaGetLastError());
}

} // namespace mark_compaction_parallel
