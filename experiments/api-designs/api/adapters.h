#ifndef API_DESIGN_ADAPTERS_H
#define API_DESIGN_ADAPTERS_H
#include <stdint.h>
#include <string.h>

#if (defined(__GNUC__) || defined(__clang__)) && !defined(__TINYC__) && !defined(API_SCALAR)
#define INL static inline __attribute__((always_inline))
typedef uint8_t v16 __attribute__((vector_size(16)));
typedef uint8_t v32 __attribute__((vector_size(32)));
#define VECTOR_BACKEND 1
#else
#define INL static inline
#define VECTOR_BACKEND 0
#endif

#if defined(__clang__) && VECTOR_BACKEND
typedef _Bool bool16 __attribute__((ext_vector_type(16)));
typedef _Bool bool32 __attribute__((ext_vector_type(32)));
#endif

// Target-neutral vector expressions let Clang lower each simd fn version
// using its own instruction set, rather than a build-wide __AVX2__ branch.
#if VECTOR_BACKEND && defined(__GNUC__) && !defined(__clang__) && !defined(__AVX2__)
// GCC's baseline lowering of a 32-byte vector comparison expands lanes
// individually here. Keep the same public width but use native-size chunks.
// Loads must use the same chunks: one 32-byte memcpy leaves aggregate
// copies of array-backed vectors in GCC 13's baseline search loop.
#define LOAD(N, out, input) do { \
    for (int offset = 0; offset < N; offset += 16) \
        memcpy((uint8_t *)&(out) + offset, (input) + offset, 16); \
} while (0)
#define EQ(N, out, input, byte) do { \
    v16 broadcast; for (int i = 0; i < 16; ++i) broadcast[i] = byte; \
    for (int offset = 0; offset < N; offset += 16) { \
        v16 x; memcpy(&x, (const uint8_t *)&(input) + offset, 16); \
        x = (v16)(x == broadcast); memcpy((uint8_t *)&(out) + offset, &x, 16); \
    } \
} while (0)
#define AND(N, out, a, b) do { \
    for (int offset = 0; offset < N; offset += 16) { \
        v16 x, y; memcpy(&x, (const uint8_t *)&(a) + offset, 16); \
        memcpy(&y, (const uint8_t *)&(b) + offset, 16); \
        x &= y; memcpy((uint8_t *)&(out) + offset, &x, 16); \
    } \
} while (0)
#elif VECTOR_BACKEND
#define LOAD(N, out, input) memcpy(&(out), input, N)
#define EQ(N, out, input, byte) do { \
    v##N x, broadcast; memcpy(&x, &(input), N); \
    for (int i = 0; i < N; ++i) broadcast[i] = byte; \
    x = (v##N)(x == broadcast); memcpy(&(out), &x, N); \
} while (0)
#define AND(N, out, a, b) do { \
    v##N x, y; memcpy(&x, &(a), N); memcpy(&y, &(b), N); \
    x &= y; memcpy(&(out), &x, N); \
} while (0)
#else
#define LOAD(N, out, input) memcpy(&(out), input, N)
#define EQ(N, out, input, byte) do { \
    uint8_t x[N], r[N]; memcpy(x, &(input), N); \
    for (int i = 0; i < N; ++i) r[i] = x[i] == byte ? 255 : 0; \
    memcpy(&(out), r, N); \
} while (0)
#define AND(N, out, a, b) do { \
    uint8_t x[N], y[N]; memcpy(x, &(a), N); memcpy(y, &(b), N); \
    for (int i = 0; i < N; ++i) x[i] &= y[i]; memcpy(&(out), x, N); \
} while (0)
#endif

#if defined(__clang__) && VECTOR_BACKEND
// Masks contain only 0/255 lanes. Conversion to packed boolean lanes is
// intentionally not a general high-bit extraction operation.
#define BITS(N, m, r) do { \
    v##N x; memcpy(&x, &(m), N); \
    bool##N b = __builtin_convertvector(x, bool##N); \
    memcpy(&(r), &b, sizeof b); \
} while (0)
#elif VECTOR_BACKEND && defined(__SSE2__)
#include <immintrin.h>
INL uint32_t api_bits16(const void *p) {
    __m128i v; memcpy(&v, p, 16); return (uint32_t)_mm_movemask_epi8(v);
}
INL uint32_t api_bits32(const void *p) {
#if defined(__AVX2__)
    __m256i v; memcpy(&v, p, 32); return (uint32_t)_mm256_movemask_epi8(v);
#else
    return api_bits16(p) | (api_bits16((const uint8_t *)p + 16) << 16);
#endif
}
#define BITS(N, m, r) do { r = api_bits##N(&(m)); } while (0)
#else
#define BITS(N, m, r) do { \
    uint8_t x[N]; memcpy(x, &(m), N); \
    for (int i = 0; i < N; ++i) r |= (uint32_t)(x[i] >> 7) << i; \
} while (0)
#endif

#define ADAPTERS(P, N, V, M) \
INL V P##_load##N(sl_u8 s) { V v; LOAD(N, v, s.data); return v; } \
INL M P##_eq##N(V v, uint8_t byte) { M m; EQ(N, m, v, byte); return m; } \
INL M P##_and##N(M a, M b) { M m; AND(N, m, a, b); return m; } \
INL uint32_t P##_bits##N(M m) { uint32_t r = 0; BITS(N, m, r); return r; }

ADAPTERS(a, 16, concrete_U8x16_g8, concrete_Mask16_g8)
ADAPTERS(a, 32, concrete_U8x32_g8, concrete_Mask32_g8)
ADAPTERS(b, 16, generic_Vec_g7_a16_u8, generic_Mask_g7_a16_u8)
ADAPTERS(b, 32, generic_Vec_g7_a32_u8, generic_Mask_g7_a32_u8)

#if VECTOR_BACKEND && (defined(__x86_64__) || defined(_M_X64)) && !defined(API_DISABLE_AVX2)
#include <immintrin.h>
// Do not force-inline an AVX2 function into a baseline caller. That is
// illegal; the experiment measures whether targeted callers inline it.
#define AVX static inline __attribute__((target("avx2")))
static uint8_t c_supported(void) {
    return !!__builtin_cpu_supports("avx2");
}
INL isa_U8x32_g3 c_load32(sl_u8 s) {
    isa_U8x32_g3 v; memcpy(&v, s.data, 32); return v;
}
AVX isa_Mask32_g3 c_eq32(isa_U8x32_g3 v, uint8_t byte) {
    __m256i x; memcpy(&x, &v, 32);
    x = _mm256_cmpeq_epi8(x, _mm256_set1_epi8((char)byte));
    isa_Mask32_g3 r; memcpy(&r, &x, 32); return r;
}
AVX isa_Mask32_g3 c_and32(isa_Mask32_g3 a, isa_Mask32_g3 b) {
    __m256i x, y; memcpy(&x, &a, 32); memcpy(&y, &b, 32);
    x = _mm256_and_si256(x, y);
    isa_Mask32_g3 r; memcpy(&r, &x, 32); return r;
}
AVX uint32_t c_bits32(isa_Mask32_g3 m) {
    __m256i x; memcpy(&x, &m, 32); return (uint32_t)_mm256_movemask_epi8(x);
}
#else
static uint8_t c_supported(void) { return 0; }
// These keep the declarations compilable, not an advertised AVX2 backend.
ADAPTERS(c, 32, isa_U8x32_g3, isa_Mask32_g3)
#endif
#endif
