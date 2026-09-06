#pragma once
// Bounded RFC 1950/1951 decoder. Input, output and Huffman workspace are device
// memory; no host codec or device heap. Caller supplies the exact output size.
namespace ct::inflate {
struct Bits {
  const unsigned char *data;
  size_t size, bit = 0;
  bool valid = true;
  __device__ unsigned read(unsigned n) {
    if (bit + n > size * 8) { valid = false; return 0; }
    if (!n) return 0;
    size_t offset = bit / 8;
    unsigned shift = bit % 8;
    unsigned value = data[offset];
    if (shift + n > 8) value |= unsigned(data[offset + 1]) << 8;
    if (shift + n > 16) value |= unsigned(data[offset + 2]) << 16;
    bit += n;
    return (value >> shift) & ((1u << n) - 1);
  }
};
template <int FastBits> struct Tree {
  unsigned short counts[16], symbols[288];
  unsigned short fast[1u << FastBits];
  __device__ bool build(const unsigned char *lengths, int n) {
    for (int i = 0; i < 16; ++i) counts[i] = 0;
    for (int i = 0; i < n; ++i) {
      if (lengths[i] > 15) return false;
      ++counts[lengths[i]];
    }
    int space = 1;
    for (int i = 1; i < 16; ++i) {
      space = 2 * space - counts[i];
      if (space < 0) return false;
    }
    // Empty distance alphabets and a single one-bit code are legal. Other
    // incomplete trees cannot arise from a valid DEFLATE encoder.
    if (space && counts[0] != n && !(counts[0] == n - 1 && counts[1] == 1))
      return false;
    int index = 0;
    for (int length = 1; length <= 15; ++length)
      for (int symbol = 0; symbol < n; ++symbol)
        if (lengths[symbol] == length) symbols[index++] = symbol;
    for (int i = 0; i < (1 << FastBits); ++i) fast[i] = 0;
    unsigned first = 0, offset = 0;
    for (int length = 1; length <= FastBits; ++length) {
      for (unsigned j = 0; j < counts[length]; ++j) {
        unsigned reversed = __brev(first + j) >> (32 - length);
        for (unsigned k = reversed; k < (1u << FastBits); k += 1u << length)
          fast[k] = (symbols[offset + j] << 4) | length;
      }
      offset += counts[length];
      first = (first + counts[length]) << 1;
    }
    return true;
  }
  __device__ int decode(Bits &bits) const {
    if (bits.bit + FastBits <= bits.size * 8) {
      unsigned entry = fast[bits.read(FastBits)];
      bits.bit -= FastBits;
      if (entry) { bits.bit += entry & 15; return entry >> 4; }
    }
    unsigned code = 0, first = 0, index = 0;
    for (int n = 1; n <= 15 && bits.valid; ++n) {
      code = (code << 1) | bits.read(1);
      unsigned count = counts[n];
      if (code >= first && code - first < count) return symbols[index + code - first];
      first = (first + count) << 1;
      index += count;
    }
    bits.valid = false;
    return -1;
  }
};
struct Token {
  unsigned short symbol, length, back, bits;
};
__device__ __constant__ unsigned short length_base[] = {
  3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258
};
struct Workspace {
  Tree<10> literal;
  Tree<7> distance, code;
  unsigned char lengths[320];
  Bits bits;
  unsigned char window[32768];
  Token tokens[512];
  unsigned long long sums[128], weights[128];
  unsigned checksum;
  int token_count;
  size_t pos, batch_start;
  unsigned length;
  int type;
  bool final, valid, end;
};
// A block speculates on Huffman token boundaries, commits the valid chain,
// and resolves LZ references in parallel through an immutable shared window.
__device__ bool decode(const unsigned char *in, size_t n, unsigned char *out,
                       size_t size, Workspace &w) {
  int lane = threadIdx.x;
  if (!lane) {
    w.valid = n >= 6 && (in[0] & 15) == 8 && (in[0] >> 4) <= 7 &&
              !(in[1] & 32) && ((unsigned(in[0]) << 8) + in[1]) % 31 == 0;
    w.bits = {in + 2, n >= 6 ? n - 6 : 0};
    w.pos = 0; w.final = false;
  }
  __syncthreads();
  while (w.valid && !w.final) {
    __syncthreads();
    if (!lane) {
      auto &bits = w.bits;
      w.final = bits.read(1);
      w.type = bits.read(2);
      w.end = false;
      if (w.type == 3) w.valid = false;
      if (!w.type) {
        bits.bit = (bits.bit + 7) & ~size_t(7);
        w.length = bits.read(16);
        unsigned inverse = bits.read(16);
        w.valid = bits.valid && (w.length ^ inverse) == 65535 &&
                  w.length <= size - w.pos && bits.bit / 8 + w.length <= bits.size;
      } else if (w.type == 1) {
        for (int i = 0; i < 288; ++i)
          w.lengths[i] = i < 144 ? 8 : i < 256 ? 9 : i < 280 ? 7 : 8;
        w.valid = w.literal.build(w.lengths, 288);
        for (int i = 0; i < 32; ++i) w.lengths[i] = 5;
        w.valid &= w.distance.build(w.lengths, 32);
      } else if (w.type == 2) {
        unsigned literals = bits.read(5) + 257;
        unsigned distances = bits.read(5) + 1;
        unsigned codes = bits.read(4) + 4;
        w.valid = literals <= 286 && bits.valid;
        const unsigned char order[] = {16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15};
        for (int i = 0; i < 19; ++i) w.lengths[i] = 0;
        for (unsigned i = 0; i < codes; ++i) w.lengths[order[i]] = bits.read(3);
        w.valid &= w.code.build(w.lengths, 19);
        unsigned at = 0;
        while (at < literals + distances && bits.valid && w.valid) {
          int symbol = w.code.decode(bits);
          if (symbol < 0) { w.valid = false; break; }
          if (symbol < 16) w.lengths[at++] = symbol;
          else {
            if (symbol == 16 && !at) { w.valid = false; break; }
            unsigned count = symbol == 16 ? bits.read(2) + 3 :
                             symbol == 17 ? bits.read(3) + 3 : bits.read(7) + 11;
            unsigned char length = symbol == 16 ? w.lengths[at - 1] : 0;
            if (count > literals + distances - at) { w.valid = false; break; }
            while (count--) w.lengths[at++] = length;
          }
        }
        if (w.valid)
          w.valid = bits.valid && w.lengths[256] && w.literal.build(w.lengths, literals) &&
                    w.distance.build(w.lengths + literals, distances);
      }
      w.valid &= bits.valid;
    }
    __syncthreads();
    if (!w.valid) break;
    if (!w.type) {
      for (unsigned i = lane; i < w.length; i += blockDim.x)
        out[w.pos + i] = w.bits.data[w.bits.bit / 8 + i];
      // Store only the final window: a stored block may exceed 32 KiB.
      for (unsigned i = lane; i < w.length && i < 32768; i += blockDim.x) {
        size_t at = w.pos + w.length - 1 - i;
        w.window[at & 32767] = w.bits.data[w.bits.bit / 8 + w.length - 1 - i];
      }
      __syncthreads();
      if (!lane) { w.pos += w.length; w.bits.bit += w.length * 8; }
      __syncthreads();
      continue;
    }
    while (w.valid && !w.end) {
      __syncthreads();
      // Speculate at each possible bit start in a small tile. Huffman lookup
      // and length/distance decoding run across the block; only the real chain
      // starting at the known bit position is committed. Invalid guesses are
      // ignored, and every selected token remains fully bounds checked.
      const size_t start_bit = w.bits.bit;
      // Dense LZ streams benefit from one direct token and a parallel copy;
      // literal-heavy streams amortize coordination over speculative tiles.
      const int guesses = n < size / 64 ? 1 : 512;
      for (int i = lane; i < guesses; i += blockDim.x) {
        Bits bits = w.bits;
        bits.bit += i;
        int symbol = w.literal.decode(bits);
        Token token{};
        token.symbol = symbol;
        if (symbol >= 0 && symbol < 256) token.length = 1;
        else if (symbol >= 257 && symbol <= 285) {
          int code = symbol - 257;
          unsigned extra = code < 8 || code == 28 ? 0 : (code - 4) / 4;
          token.length = length_base[code] + bits.read(extra);
          int dist = w.distance.decode(bits);
          if (dist < 0 || dist > 29) bits.valid = false;
          else {
            unsigned extra = dist < 4 ? 0 : dist / 2 - 1;
            token.back = (dist < 4 ? dist + 1 : ((2 + (dist & 1)) << extra) + 1) + bits.read(extra);
          }
        } else if (symbol != 256) bits.valid = false;
        if (bits.valid) token.bits = bits.bit - start_bit - i;
        w.tokens[i] = token;
      }
      __syncthreads();
      if (!lane) {
        size_t pos = w.pos, bit = start_bit;
        bool valid = true, end = false;
        w.batch_start = pos;
        int count = 0;
        while (bit - start_bit < size_t(guesses) && pos - w.batch_start < 16384 && valid && !end) {
          Token token = w.tokens[bit - start_bit];
          if (!token.bits || token.length > size - pos || token.back > pos) {
            valid = false; break;
          }
          bit += token.bits;
          if (token.symbol == 256) end = true;
          else {
            token.bits = pos - w.batch_start; // Output offset of selected token.
            w.tokens[count++] = token;
            pos += token.length;
          }
        }
        w.token_count = count;
        w.bits.bit = bit; w.pos = pos; w.valid = valid; w.end = end;
      }
      __syncthreads();
      if (!w.valid) break;
      // Stop each batch below 16 KiB plus one match, preserving its entire
      // output in the 32 KiB window for the next batch.
      for (size_t i = w.batch_start + lane; i < w.pos; i += blockDim.x) {
        size_t source = i;
        unsigned char value = 0;
        while (source >= w.batch_start) {
          unsigned offset = source - w.batch_start;
          int lo = 0, hi = w.token_count;
          while (lo + 1 < hi) {
            int mid = (lo + hi) / 2;
            if (w.tokens[mid].bits <= offset) lo = mid;
            else hi = mid;
          }
          Token token = w.tokens[lo];
          if (!token.back) { value = token.symbol; break; }
          source = w.batch_start + token.bits - token.back + (offset - token.bits) % token.back;
        }
        if (source < w.batch_start) value = w.window[source & 32767];
        out[i] = value;
      }
      __syncthreads();
      // Keep the previous history immutable while resolving all references.
      // Every dependency steps into an earlier token or the previous window.
      for (size_t i = w.batch_start + lane; i < w.pos; i += blockDim.x)
        w.window[i & 32767] = out[i];
      __syncthreads();
    }
  }
  if (!w.valid || !w.bits.valid || !w.final || w.pos != size ||
      (w.bits.bit + 7) / 8 != w.bits.size) return false;
  unsigned long long sum = 0, weighted = 0;
  for (size_t i = lane; i < size; i += blockDim.x) {
    unsigned value = out[i];
    sum += value; weighted += (size - i) * (unsigned long long)value;
  }
  w.sums[lane] = sum; w.weights[lane] = weighted;
  __syncthreads();
  if (!lane) {
    sum = weighted = 0;
    for (unsigned i = 0; i < blockDim.x; ++i) { sum += w.sums[i]; weighted += w.weights[i]; }
    w.checksum = (unsigned((weighted + size) % 65521) << 16) | unsigned((sum + 1) % 65521);
  }
  __syncthreads();
  unsigned expected = (unsigned(in[n-4]) << 24) | (unsigned(in[n-3]) << 16) |
                      (unsigned(in[n-2]) << 8) | in[n-1];
  return w.checksum == expected;
}
} // namespace ct::inflate
