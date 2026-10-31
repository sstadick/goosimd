import api from "./api";

// One algorithm, specialized by a compile-time function argument.
inline fn pair_kernel<Load>(s: const u8[:], a: u8, b: u8, width: i64) -> i64 {
    var pos = 0;
    while pos < s.len - width {
        let x = Load(s[pos..]).eq(a);
        let y = Load(s[pos + 1..]).eq(b);
        let at = x.bit_and(y).first();
        if at >= 0 { return pos + at; }
        pos += width;
    }
    for i in pos..s.len - 1 {
        if s[i] == a && s[i + 1] == b { return i; }
    }
    return -1;
}

fn a16(s: const u8[:], a: u8, b: u8) -> i64 {
    return pair_kernel(s, a, b, 16, concrete::load16);
}
fn a32(s: const u8[:], a: u8, b: u8) -> i64 {
    return pair_kernel(s, a, b, 32, concrete::load32);
}
fn b16(s: const u8[:], a: u8, b: u8) -> i64 {
    return pair_kernel(s, a, b, 16) { bytes => generic::load<generic::U8x16>(bytes) };
}
fn b32(s: const u8[:], a: u8, b: u8) -> i64 {
    return pair_kernel(s, a, b, 32) { bytes => generic::load<generic::U8x32>(bytes) };
}
fn c32(s: const u8[:], a: u8, b: u8) -> i64 {
    return pair_kernel(s, a, b, 32, isa::load32);
}
simd fn a_auto(s: const u8[:], a: u8, b: u8) -> i64 {
    return pair_kernel(s, a, b, 32, concrete::load32);
}
simd fn b_auto(s: const u8[:], a: u8, b: u8) -> i64 {
    return pair_kernel(s, a, b, 32) { bytes => generic::load<generic::U8x32>(bytes) };
}
simd fn c_targeted(s: const u8[:], a: u8, b: u8) -> i64 {
    return pair_kernel(s, a, b, 32, isa::load32);
}
fn c_auto(s: const u8[:], a: u8, b: u8) -> i64 {
    if isa::supported() { return c_targeted(s, a, b); }
    return a32(s, a, b);
}
