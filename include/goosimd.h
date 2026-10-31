#ifndef GOOSIMD_H
#define GOOSIMD_H

// c_headers places this after Goose's generated types. These names/layouts
// are compiler-specific, not a stable C ABI. memcpy permits packed values.
#include <stdint.h>
#include <string.h>

#if (defined(__GNUC__) || defined(__clang__)) && !defined(__TINYC__) && !defined(GOOSIMD_SCALAR)
#define GOOSIMD_INLINE static inline __attribute__((always_inline))
#define GOOSIMD_VECTOR_BACKEND 1
typedef uint8_t goosimd_v16 __attribute__((vector_size(16)));
typedef uint8_t goosimd_v32 __attribute__((vector_size(32)));
// GCC baseline needs matching 16-byte loads and operations to eliminate
// copies of array-backed vectors. Clang lowers each simd fn target itself.
#if !defined(__clang__) && !defined(__AVX2__)
#define GOOSIMD_WIDTH(N) 16
#else
#define GOOSIMD_WIDTH(N) N
#endif
#define GOOSIMD_TYPE_(N) goosimd_v##N
#define GOOSIMD_TYPE(N) GOOSIMD_TYPE_(N)
// GCC's scalar broadcast avoids stack temporaries. Clang's vector form
// produces better code for short mask combinations.
#if defined(__clang__)
#define GOOSIMD_BROADCAST(N, byte) \
    GOOSIMD_TYPE(GOOSIMD_WIDTH(N)) broadcast; \
    for (int i = 0; i < GOOSIMD_WIDTH(N); ++i) broadcast[i] = byte
#else
#define GOOSIMD_BROADCAST(N, byte) uint8_t broadcast = byte
#endif
#define GOOSIMD_LOAD(N, out, input) do { \
    for (int offset = 0; offset < N; offset += GOOSIMD_WIDTH(N)) \
        memcpy((uint8_t *)&(out) + offset, (input) + offset, GOOSIMD_WIDTH(N)); \
} while (0)
#define GOOSIMD_EQ(N, out, input, byte) do { \
    GOOSIMD_BROADCAST(N, byte); \
    for (int offset = 0; offset < N; offset += GOOSIMD_WIDTH(N)) { \
        GOOSIMD_TYPE(GOOSIMD_WIDTH(N)) x; \
        memcpy(&x, (const uint8_t *)&(input) + offset, sizeof x); \
        x = (GOOSIMD_TYPE(GOOSIMD_WIDTH(N)))(x == broadcast); \
        memcpy((uint8_t *)&(out) + offset, &x, sizeof x); \
    } \
} while (0)
#define GOOSIMD_BINARY(N, out, a, b, op) do { \
    for (int offset = 0; offset < N; offset += GOOSIMD_WIDTH(N)) { \
        GOOSIMD_TYPE(GOOSIMD_WIDTH(N)) x, y; \
        memcpy(&x, (const uint8_t *)&(a) + offset, sizeof x); \
        memcpy(&y, (const uint8_t *)&(b) + offset, sizeof y); \
        x = x op y; memcpy((uint8_t *)&(out) + offset, &x, sizeof x); \
    } \
} while (0)
#define GOOSIMD_NOT(N, out, input) do { \
    for (int offset = 0; offset < N; offset += GOOSIMD_WIDTH(N)) { \
        GOOSIMD_TYPE(GOOSIMD_WIDTH(N)) x; \
        memcpy(&x, (const uint8_t *)&(input) + offset, sizeof x); \
        x = ~x; memcpy((uint8_t *)&(out) + offset, &x, sizeof x); \
    } \
} while (0)
#else
#define GOOSIMD_INLINE static inline
#define GOOSIMD_VECTOR_BACKEND 0
#define GOOSIMD_LOAD(N, out, input) memcpy(&(out), input, N)
#define GOOSIMD_EQ(N, out, input, byte) do { \
    uint8_t x[N]; memcpy(x, &(input), N); \
    for (int i = 0; i < N; ++i) x[i] = x[i] == byte ? 255 : 0; \
    memcpy(&(out), x, N); \
} while (0)
#define GOOSIMD_BINARY(N, out, a, b, op) do { \
    uint8_t x[N], y[N]; memcpy(x, &(a), N); memcpy(y, &(b), N); \
    for (int i = 0; i < N; ++i) x[i] = x[i] op y[i]; \
    memcpy(&(out), x, N); \
} while (0)
#define GOOSIMD_NOT(N, out, input) do { \
    uint8_t x[N]; memcpy(x, &(input), N); \
    for (int i = 0; i < N; ++i) x[i] = (uint8_t)~x[i]; \
    memcpy(&(out), x, N); \
} while (0)
#endif

#if defined(__clang__) && GOOSIMD_VECTOR_BACKEND
typedef _Bool goosimd_bool16 __attribute__((ext_vector_type(16)));
typedef _Bool goosimd_bool32 __attribute__((ext_vector_type(32)));
// Conversion to packed booleans is for comparison masks, not arbitrary bytes.
#define GOOSIMD_BITS(N, m, r) do { \
    goosimd_v##N x; memcpy(&x, &(m), N); \
    goosimd_bool##N b = __builtin_convertvector(x, goosimd_bool##N); \
    memcpy(&(r), &b, sizeof b); \
} while (0)
#elif GOOSIMD_VECTOR_BACKEND && (defined(__SSE2__) || defined(__aarch64__))
#if defined(__SSE2__)
#include <immintrin.h>
GOOSIMD_INLINE uint32_t goosimd_extract16(const void *p) {
    __m128i x; memcpy(&x, p, 16); return (uint32_t)_mm_movemask_epi8(x);
}
#else
#include <arm_neon.h>
GOOSIMD_INLINE uint32_t goosimd_extract16(const void *p) {
    const uint8_t weights[16] = {1,2,4,8,16,32,64,128,1,2,4,8,16,32,64,128};
    uint8x16_t x; memcpy(&x, p, 16);
    x = vandq_u8(x, vld1q_u8(weights));
    return (uint32_t)vaddv_u8(vget_low_u8(x)) | (uint32_t)vaddv_u8(vget_high_u8(x)) << 8;
}
#endif
GOOSIMD_INLINE uint32_t goosimd_extract32(const void *p) {
#if defined(__AVX2__)
    __m256i x; memcpy(&x, p, 32); return (uint32_t)_mm256_movemask_epi8(x);
#else
    return goosimd_extract16(p) | (goosimd_extract16((const uint8_t *)p + 16) << 16);
#endif
}
#define GOOSIMD_BITS(N, m, r) do { r = goosimd_extract##N(&(m)); } while (0)
#else
#define GOOSIMD_BITS(N, m, r) do { \
    uint8_t x[N]; memcpy(x, &(m), N); \
    for (int i = 0; i < N; ++i) r |= (uint32_t)(x[i] >> 7) << i; \
} while (0)
#endif

#define GOOSIMD_ADAPTERS(N, V, M) \
GOOSIMD_INLINE V goosimd_load##N(sl_u8 s) { V v; GOOSIMD_LOAD(N, v, s.data); return v; } \
GOOSIMD_INLINE M goosimd_eq##N(V v, uint8_t byte) { M m; GOOSIMD_EQ(N, m, v, byte); return m; } \
GOOSIMD_INLINE M goosimd_and##N(M a, M b) { M m; GOOSIMD_BINARY(N, m, a, b, &); return m; } \
GOOSIMD_INLINE M goosimd_or##N(M a, M b) { M m; GOOSIMD_BINARY(N, m, a, b, |); return m; } \
GOOSIMD_INLINE M goosimd_not##N(M a) { M m; GOOSIMD_NOT(N, m, a); return m; } \
GOOSIMD_INLINE uint32_t goosimd_bits##N(M m) { uint32_t r = 0; GOOSIMD_BITS(N, m, r); return r; }

GOOSIMD_ADAPTERS(16, goosimd_Vec_g7_a16_u8, goosimd_Mask_g7_a16_u8)
GOOSIMD_ADAPTERS(32, goosimd_Vec_g7_a32_u8, goosimd_Mask_g7_a32_u8)

GOOSIMD_INLINE uint16_t goosimd_load_u16(sl_u8 s) {
    uint16_t r; memcpy(&r, s.data, sizeof r); return r;
}
GOOSIMD_INLINE uint32_t goosimd_load_u32(sl_u8 s) {
    uint32_t r; memcpy(&r, s.data, sizeof r); return r;
}
GOOSIMD_INLINE uint64_t goosimd_load_u64(sl_u8 s) {
    uint64_t r; memcpy(&r, s.data, sizeof r); return r;
}

#undef GOOSIMD_ADAPTERS
#undef GOOSIMD_BITS
#undef GOOSIMD_NOT
#undef GOOSIMD_BINARY
#undef GOOSIMD_EQ
#undef GOOSIMD_LOAD
#undef GOOSIMD_BROADCAST
#undef GOOSIMD_TYPE
#undef GOOSIMD_TYPE_
#undef GOOSIMD_WIDTH
#undef GOOSIMD_VECTOR_BACKEND
#undef GOOSIMD_INLINE
#endif
