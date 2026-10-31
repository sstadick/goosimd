// Experimental byte vectors. The API and representation are not stable.
namespace goosimd;
import std;

// A byte vector. Supported lane types are u8[16] and u8[32]. Width is a
// compile-time type choice, not an instruction-set requirement; use `load<V>`.
struct Vec<Lanes> { lanes: Lanes }
// Comparison masks contain only 0/255 lanes; do not construct arbitrary masks.
struct Mask<Lanes> { lanes: Lanes }
// A 16-byte vector, equivalent to `Vec<u8[16]>`.
type U8x16 = Vec<u8[16]>;
// A 32-byte vector, equivalent to `Vec<u8[32]>`; may use two 16-byte registers.
type U8x32 = Vec<u8[32]>;

// Concrete externs are the only width-specific part of the public façade.
extern fn load16_raw(s: const u8[:]) -> U8x16 = "goosimd_load16";
extern fn load32_raw(s: const u8[:]) -> U8x32 = "goosimd_load32";
extern fn eq_impl(v: U8x16, x: u8) -> Mask<u8[16]> = "goosimd_eq16";
extern fn eq_impl(v: U8x32, x: u8) -> Mask<u8[32]> = "goosimd_eq32";
extern fn and_impl(a: Mask<u8[16]>, b: Mask<u8[16]>) -> Mask<u8[16]> = "goosimd_and16";
extern fn and_impl(a: Mask<u8[32]>, b: Mask<u8[32]>) -> Mask<u8[32]> = "goosimd_and32";
extern fn or_impl(a: Mask<u8[16]>, b: Mask<u8[16]>) -> Mask<u8[16]> = "goosimd_or16";
extern fn or_impl(a: Mask<u8[32]>, b: Mask<u8[32]>) -> Mask<u8[32]> = "goosimd_or32";
extern fn not_impl(m: Mask<u8[16]>) -> Mask<u8[16]> = "goosimd_not16";
extern fn not_impl(m: Mask<u8[32]>) -> Mask<u8[32]> = "goosimd_not32";
extern fn bits_impl(m: Mask<u8[16]>) -> u32 = "goosimd_bits16";
extern fn bits_impl(m: Mask<u8[32]>) -> u32 = "goosimd_bits32";

// Unaligned, bounded loads. Raw adapters require the caller to check length.
inline fn load_as(v: U8x16, s: const u8[:]) -> U8x16 {
    assert(s.len >= 16);
    return load16_raw(s);
}
inline fn load_as(v: U8x32, s: const u8[:]) -> U8x32 {
    assert(s.len >= 32);
    return load32_raw(s);
}
// Read the first vector-width bytes without requiring alignment. V must be
// U8x16 or U8x32. Asserts that s contains at least that many bytes.
inline fn load<V>(s: const u8[:]) -> V { return load_as(default<V>(), s); }
// Compare each byte lane to x, returning 0xff for equal lanes and 0 otherwise.
inline fn eq<L>(v: Vec<L>, x: u8) -> Mask<L> { return eq_impl(v, x); }
// Keep lanes matched by both masks. The masks must have the same width.
inline fn bit_and<L>(a: Mask<L>, b: Mask<L>) -> Mask<L> { return and_impl(a, b); }
// Keep lanes matched by either mask. The masks must have the same width.
inline fn bit_or<L>(a: Mask<L>, b: Mask<L>) -> Mask<L> { return or_impl(a, b); }
// Invert every lane of a comparison mask, exchanging 0 and 0xff.
inline fn bit_not<L>(m: Mask<L>) -> Mask<L> { return not_impl(m); }
// Extract one bit per matched lane. Lane 0 is bit 0; bits above the mask
// width are zero. The input must contain only comparison-mask values.
inline fn to_bits<L>(m: Mask<L>) -> u32 { return bits_impl(m); }
// Return the lowest matching lane index, or -1 when no lanes match.
inline fn first<L>(m: Mask<L>) -> i64 {
    let bits = m.to_bits();
    return if bits == 0 { -1 } else { ctz(bits) };
}
// Return the highest matching lane index, or -1 when no lanes match.
inline fn last<L>(m: Mask<L>) -> i64 {
    let bits = m.to_bits();
    return if bits == 0 { -1 } else { 63 - clz(bits) };
}

extern fn load_u16_raw(s: const u8[:]) -> u16 = "goosimd_load_u16";
extern fn load_u32_raw(s: const u8[:]) -> u32 = "goosimd_load_u32";
extern fn load_u64_raw(s: const u8[:]) -> u64 = "goosimd_load_u64";

// Read the first two bytes as a native-endian integer, without alignment
// requirements. Asserts s.len >= 2. Not a portable serialization primitive.
inline fn load_u16(s: const u8[:]) -> u16 {
    assert(s.len >= 2);
    return load_u16_raw(s[..2]);
}
// Read the first four bytes as a native-endian integer, without alignment
// requirements. Asserts s.len >= 4. Not a portable serialization primitive.
inline fn load_u32(s: const u8[:]) -> u32 {
    assert(s.len >= 4);
    return load_u32_raw(s[..4]);
}
// Read the first eight bytes as a native-endian integer, without alignment
// requirements. Asserts s.len >= 8. Not a portable serialization primitive.
inline fn load_u64(s: const u8[:]) -> u64 {
    assert(s.len >= 8);
    return load_u64_raw(s[..8]);
}

// Return the first byte offset matching byte, or -1 if none exists.
// Example whole-loop runtime dispatch with simd fn on Clang/x86; other
// backends use their available target or scalar implementation.
simd fn find_byte(s: const u8[:], byte: u8) -> i64 {
    var pos = 0;
    while pos <= s.len - 32 {
        let at = load<U8x32>(s[pos..]).eq(byte).first();
        if at >= 0 { return pos + at; }
        pos += 32;
    }
    for i in pos..s.len { if s[i] == byte { return i; } }
    return -1;
}

// Return the first byte offset of adjacent bytes a, b, or -1 if absent.
// Empty and one-byte inputs cannot match. Uses the same whole-loop SIMD
// dispatch as find_byte.
simd fn find_pair(s: const u8[:], a: u8, b: u8) -> i64 {
    var pos = 0;
    while pos < s.len - 32 {
        let x = load<U8x32>(s[pos..]).eq(a);
        let y = load<U8x32>(s[pos + 1..]).eq(b);
        let at = x.bit_and(y).first();
        if at >= 0 { return pos + at; }
        pos += 32;
    }
    for i in pos..s.len - 1 {
        if s[i] == a && s[i + 1] == b { return i; }
    }
    return -1;
}
