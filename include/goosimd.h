#ifndef GOOSIMD_H
#define GOOSIMD_H

// c_headers inserts this after Goose's generated types. The generated name
// for goosimd::Bytes32 is goosimd_Bytes32_g7; this is not a stable C ABI.
// memcpy avoids alignment and aliasing assumptions about packed Goose values.
#include <stdint.h>
#include <string.h>

#if (defined(__clang__) || defined(__GNUC__)) && !defined(__TINYC__)
#define GOOSIMD_INLINE static inline __attribute__((always_inline))
#else
#define GOOSIMD_INLINE static inline
#endif

#if !defined(__TINYC__) && !defined(GOOSIMD_SCALAR)
#if defined(__AVX2__)
#include <immintrin.h>
#define GOOSIMD_AVX2
#elif defined(__aarch64__)
#include <arm_neon.h>
#define GOOSIMD_NEON
#elif defined(__SSE2__)
#include <emmintrin.h>
#define GOOSIMD_SSE2
#endif
#endif

GOOSIMD_INLINE goosimd_Bytes32_g7 goosimd_load32(sl_u8 s) {
    goosimd_Bytes32_g7 r;
    memcpy(&r, s.data, 32);
    return r;
}

GOOSIMD_INLINE goosimd_Bytes32_g7 goosimd_eq8(goosimd_Bytes32_g7 v, uint8_t byte) {
    goosimd_Bytes32_g7 r;
#if defined(GOOSIMD_AVX2)
    __m256i x;
    memcpy(&x, &v, 32);
    x = _mm256_cmpeq_epi8(x, _mm256_set1_epi8((char)byte));
    memcpy(&r, &x, 32);
#elif defined(GOOSIMD_NEON)
    uint8x16_t x[2];
    memcpy(x, &v, 32);
    x[0] = vceqq_u8(x[0], vdupq_n_u8(byte));
    x[1] = vceqq_u8(x[1], vdupq_n_u8(byte));
    memcpy(&r, x, 32);
#elif defined(GOOSIMD_SSE2)
    __m128i x[2];
    memcpy(x, &v, 32);
    x[0] = _mm_cmpeq_epi8(x[0], _mm_set1_epi8((char)byte));
    x[1] = _mm_cmpeq_epi8(x[1], _mm_set1_epi8((char)byte));
    memcpy(&r, x, 32);
#else
    uint8_t x[32];
    memcpy(x, &v, 32);
    for (int i = 0; i < 32; i++) x[i] = x[i] == byte ? 255 : 0;
    memcpy(&r, x, 32);
#endif
    return r;
}

// Bit i is byte i's high bit, including bit 31; accepts arbitrary byte values.
GOOSIMD_INLINE uint32_t goosimd_mask8(goosimd_Bytes32_g7 v) {
#if defined(GOOSIMD_AVX2)
    __m256i x;
    memcpy(&x, &v, 32);
    return (uint32_t)_mm256_movemask_epi8(x);
#elif defined(GOOSIMD_NEON)
    uint8x16_t x[2];
    const uint8_t weights[16] = {1,2,4,8,16,32,64,128,1,2,4,8,16,32,64,128};
    const uint8x16_t w = vld1q_u8(weights);
    memcpy(x, &v, 32);
    x[0] = vandq_u8(vreinterpretq_u8_s8(vshrq_n_s8(vreinterpretq_s8_u8(x[0]), 7)), w);
    x[1] = vandq_u8(vreinterpretq_u8_s8(vshrq_n_s8(vreinterpretq_s8_u8(x[1]), 7)), w);
    return (uint32_t)vaddv_u8(vget_low_u8(x[0]))
        | (uint32_t)vaddv_u8(vget_high_u8(x[0])) << 8
        | (uint32_t)vaddv_u8(vget_low_u8(x[1])) << 16
        | (uint32_t)vaddv_u8(vget_high_u8(x[1])) << 24;
#elif defined(GOOSIMD_SSE2)
    __m128i x[2];
    memcpy(x, &v, 32);
    return (uint32_t)_mm_movemask_epi8(x[0]) | (uint32_t)_mm_movemask_epi8(x[1]) << 16;
#else
    uint8_t x[32];
    uint32_t r = 0;
    memcpy(x, &v, 32);
    for (int i = 0; i < 32; i++) r |= (uint32_t)(x[i] >> 7) << i;
    return r;
#endif
}

#endif
