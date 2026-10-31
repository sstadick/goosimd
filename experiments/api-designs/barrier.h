#ifndef API_DESIGN_BARRIER_H
#define API_DESIGN_BARRIER_H
#if (defined(__GNUC__) || defined(__clang__)) && !defined(__TINYC__)
static __attribute__((noinline)) int64_t bench_opaque(sl_u8 s) {
    __asm__ volatile("" : "+r"(s.len) : : "memory");
    return s.len;
}
#else
static int64_t bench_opaque(sl_u8 s) { return s.len; }
#endif
#endif
