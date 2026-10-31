namespace generic;
import std;

struct Vec<Lanes> { lanes: Lanes }
struct Mask<Lanes> { lanes: Lanes }
type U8x16 = Vec<u8[16]>;
type U8x32 = Vec<u8[32]>;

// Only the extern boundary enumerates concrete instantiations.
extern fn load16_raw(s: const u8[:]) -> U8x16 = "b_load16";
extern fn load32_raw(s: const u8[:]) -> U8x32 = "b_load32";
extern fn eq_impl(v: U8x16, x: u8) -> Mask<u8[16]> = "b_eq16";
extern fn eq_impl(v: U8x32, x: u8) -> Mask<u8[32]> = "b_eq32";
extern fn and_impl(a: Mask<u8[16]>, b: Mask<u8[16]>) -> Mask<u8[16]> = "b_and16";
extern fn and_impl(a: Mask<u8[32]>, b: Mask<u8[32]>) -> Mask<u8[32]> = "b_and32";
extern fn bits_impl(m: Mask<u8[16]>) -> u32 = "b_bits16";
extern fn bits_impl(m: Mask<u8[32]>) -> u32 = "b_bits32";

inline fn load_as(v: U8x16, s: const u8[:]) -> U8x16 {
    assert(s.len >= 16);
    return load16_raw(s);
}
inline fn load_as(v: U8x32, s: const u8[:]) -> U8x32 {
    assert(s.len >= 32);
    return load32_raw(s);
}
inline fn load<V>(s: const u8[:]) -> V { return load_as(default<V>(), s); }
inline fn eq<L>(v: Vec<L>, x: u8) -> Mask<L> { return eq_impl(v, x); }
inline fn bit_and<L>(a: Mask<L>, b: Mask<L>) -> Mask<L> { return and_impl(a, b); }
inline fn to_bits<L>(m: Mask<L>) -> u32 { return bits_impl(m); }
inline fn first<L>(m: Mask<L>) -> i64 {
    let bits = m.to_bits();
    return if bits == 0 { -1 } else { ctz(bits) };
}
