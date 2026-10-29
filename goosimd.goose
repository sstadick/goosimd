// Placeholder API for testing package-supplied headers, not a stable SIMD API.
namespace goosimd;
import std;

struct Bytes16 { a: u64, b: u64 }
struct Bytes32 { a: u64, b: u64, c: u64, d: u64 }

// Raw adapter: callers must supply at least 16 readable bytes. Use load16.
extern fn load16_raw(s: const u8[:]) -> Bytes16 = "goosimd_load16";
extern fn eq8(v: Bytes16, byte: u8) -> Bytes16 = "goosimd_eq8_16";
extern fn mask8(v: Bytes16) -> u32 = "goosimd_mask8_16";

// Raw adapter: callers must supply at least 32 readable bytes. Use load32.
extern fn load32_raw(s: const u8[:]) -> Bytes32 = "goosimd_load32";
extern fn eq8(v: Bytes32, byte: u8) -> Bytes32 = "goosimd_eq8";
extern fn mask8(v: Bytes32) -> u32 = "goosimd_mask8";
extern fn load_u16_raw(s: const u8[:]) -> u16 = "goosimd_load_u16";
extern fn load_u32_raw(s: const u8[:]) -> u32 = "goosimd_load_u32";
extern fn load_u64_raw(s: const u8[:]) -> u64 = "goosimd_load_u64";

// Unaligned loads are allowed; only the first 16 bytes are read.
inline fn load16(s: const u8[:]) -> Bytes16 {
    assert(s.len >= 16);
    return load16_raw(s[..16]);
}

inline fn bit_and(x: Bytes16, y: Bytes16) -> Bytes16 {
    return Bytes16 { x.a & y.a, x.b & y.b };
}

inline fn bit_or(x: Bytes16, y: Bytes16) -> Bytes16 {
    return Bytes16 { x.a | y.a, x.b | y.b };
}

inline fn bit_not(x: Bytes16) -> Bytes16 {
    return Bytes16 { ~x.a, ~x.b };
}

// Unaligned loads are allowed; only the first 32 bytes are read.
inline fn load32(s: const u8[:]) -> Bytes32 {
    assert(s.len >= 32);
    return load32_raw(s[..32]);
}

inline fn bit_and(x: Bytes32, y: Bytes32) -> Bytes32 {
    return Bytes32 { x.a & y.a, x.b & y.b, x.c & y.c, x.d & y.d };
}

inline fn bit_or(x: Bytes32, y: Bytes32) -> Bytes32 {
    return Bytes32 { x.a | y.a, x.b | y.b, x.c | y.c, x.d | y.d };
}

inline fn bit_not(x: Bytes32) -> Bytes32 {
    return Bytes32 { ~x.a, ~x.b, ~x.c, ~x.d };
}

// Native-endian unaligned loads for bounded byte comparisons.
inline fn load_u16(s: const u8[:]) -> u16 {
    assert(s.len >= 2);
    return load_u16_raw(s[..2]);
}

inline fn load_u32(s: const u8[:]) -> u32 {
    assert(s.len >= 4);
    return load_u32_raw(s[..4]);
}

inline fn load_u64(s: const u8[:]) -> u64 {
    assert(s.len >= 8);
    return load_u64_raw(s[..8]);
}

// Example consumers: scan loops and scalar tails stay in Goose.
fn find_byte(s: const u8[:], byte: u8) -> i64 {
    var rest = s;
    while rest.len >= 32 {
        let hits = mask8(eq8(load32(rest), byte));
        if hits != 0 { return s.len - rest.len + ctz(hits); }
        rest = rest[32..];
    }
    for x, i in rest {
        if x == byte { return s.len - rest.len + i; }
    }
    return -1;
}

fn find_pair(s: const u8[:], a: u8, b: u8) -> i64 {
    var rest = s;
    while rest.len >= 33 {
        let x = eq8(load32(rest), a);
        let y = eq8(load32(rest[1..]), b);
        let hits = mask8(bit_and(x, y));
        if hits != 0 { return s.len - rest.len + ctz(hits); }
        rest = rest[32..];
    }
    for i in max(0, rest.len - 1) {
        if rest[i] == a && rest[i + 1] == b { return s.len - rest.len + i; }
    }
    return -1;
}
