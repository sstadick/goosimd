namespace concrete;
import std;

struct U8x16 { lo: u64, hi: u64 }
struct U8x32 { a: u64, b: u64, c: u64, d: u64 }
struct Mask16 { lanes: U8x16 }
struct Mask32 { lanes: U8x32 }

extern fn load16_raw(s: const u8[:]) -> U8x16 = "a_load16";
extern fn load32_raw(s: const u8[:]) -> U8x32 = "a_load32";
extern fn eq(v: U8x16, x: u8) -> Mask16 = "a_eq16";
extern fn eq(v: U8x32, x: u8) -> Mask32 = "a_eq32";
extern fn bit_and(a: Mask16, b: Mask16) -> Mask16 = "a_and16";
extern fn bit_and(a: Mask32, b: Mask32) -> Mask32 = "a_and32";
extern fn to_bits(m: Mask16) -> u32 = "a_bits16";
extern fn to_bits(m: Mask32) -> u32 = "a_bits32";

inline fn load16(s: const u8[:]) -> U8x16 {
    assert(s.len >= 16);
    return load16_raw(s);
}
inline fn load32(s: const u8[:]) -> U8x32 {
    assert(s.len >= 32);
    return load32_raw(s);
}
inline fn first(m: Mask16) -> i64 {
    let bits = m.to_bits();
    return if bits == 0 { -1 } else { ctz(bits) };
}
inline fn first(m: Mask32) -> i64 {
    let bits = m.to_bits();
    return if bits == 0 { -1 } else { ctz(bits) };
}
