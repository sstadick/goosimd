namespace isa;
import std;

// Explicit AVX2 API: supported() must succeed before calling its primitives.
struct U8x32 { a: u64, b: u64, c: u64, d: u64 }
struct Mask32 { lanes: U8x32 }
extern fn supported() -> bool = "c_supported";
extern fn load32_raw(s: const u8[:]) -> U8x32 = "c_load32";
extern fn eq(v: U8x32, x: u8) -> Mask32 = "c_eq32";
extern fn bit_and(a: Mask32, b: Mask32) -> Mask32 = "c_and32";
extern fn to_bits(m: Mask32) -> u32 = "c_bits32";

inline fn load32(s: const u8[:]) -> U8x32 {
    assert(s.len >= 32);
    return load32_raw(s);
}
inline fn first(m: Mask32) -> i64 {
    let bits = m.to_bits();
    return if bits == 0 { -1 } else { ctz(bits) };
}
