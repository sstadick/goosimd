// Placeholder API for testing package-supplied headers, not a stable SIMD API.
namespace goosimd;
import std;

struct Bytes32 { a: u64, b: u64, c: u64, d: u64 }

// Raw adapter: callers must supply at least 32 readable bytes. Use load32.
extern fn load32_raw(s: const u8[:]) -> Bytes32 = "goosimd_load32";
extern fn eq8(v: Bytes32, byte: u8) -> Bytes32 = "goosimd_eq8";
extern fn mask8(v: Bytes32) -> u32 = "goosimd_mask8";

// Unaligned loads are allowed; only the first 32 bytes are read.
inline fn load32(s: const u8[:]) -> Bytes32 {
    assert(s.len >= 32);
    return load32_raw(s[..32]);
}

inline fn bit_and(x: Bytes32, y: Bytes32) -> Bytes32 {
    return Bytes32 { x.a & y.a, x.b & y.b, x.c & y.c, x.d & y.d };
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
