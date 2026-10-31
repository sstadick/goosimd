import std;
import goosimd from "..";

fn check_search(s: const u8[:], a: u8, b: u8) {
    var byte_at = -1;
    var pair_at = -1;
    for x, i in s {
        if x == a {
            if byte_at < 0 { byte_at = i; }
            if pair_at < 0 && i + 1 < s.len && s[i + 1] == b { pair_at = i; }
        }
    }
    assert(goosimd::find_byte(s, a) == byte_at);
    assert(goosimd::find_pair(s, a, b) == pair_at);
}

fn check_mask<L>(m: goosimd::Mask<L>, expected: u32, width: i64) {
    var first = -1;
    var last = -1;
    for i in width {
        if expected & ((1 as u32) << i) != 0 {
            if first < 0 { first = i; }
            last = i;
        }
    }
    assert(m.to_bits() == expected);
    assert(m.first() == first);
    assert(m.last() == last);
}

fn main() {
    var data: u8[160] = [0; 160];
    // Every byte value, lane and alignment, including bit 31 of the mask.
    for offset in 32 {
        for value in 256 {
            for lane in 32 {
                for i in 32 { data[offset + i] = (value as u8) ^ 1; }
                data[offset + lane] = value as u8;
                let eq = goosimd::load<goosimd::U8x32>(data[offset..offset + 32]).eq(value as u8);
                check_mask(eq, (1 as u32) << lane, 32);
                let eq16 = goosimd::load<goosimd::U8x16>(data[offset..offset + 16]).eq(value as u8);
                let mask16: u32 = if lane < 16 { (1 as u32) << lane } else { 0 };
                check_mask(eq16, mask16, 16);
            }
        }
    }
    // Independent masks with mixed bits distinguish AND, OR, and NOT.
    // Expected bits come from scalar input bytes, never SIMD results.
    var state: u64 = 123456789;
    var other: u8[32] = [0; 32];
    for trial in 1000 {
        var left: u32 = 0;
        var right: u32 = 0;
        for i in 32 {
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            data[i] = ((state >> 56) & 1) as u8;
            other[i] = ((state >> 24) & 1) as u8;
            if data[i] == 1 { left |= (1 as u32) << i; }
            if other[i] == 1 { right |= (1 as u32) << i; }
        }
        let x = goosimd::load<goosimd::U8x32>(data).eq(1);
        let y = goosimd::load<goosimd::U8x32>(other).eq(1);
        check_mask(x.bit_and(y), left & right, 32);
        check_mask(x.bit_or(y), left | right, 32);
        check_mask(x.bit_not(), ~left, 32);
        check_mask(x.bit_or(x.bit_not()), 0xFFFFFFFF, 32);
        check_mask(x.bit_and(x.bit_not()), 0, 32);
        let x16 = goosimd::load<goosimd::U8x16>(data).eq(1);
        let y16 = goosimd::load<goosimd::U8x16>(other).eq(1);
        check_mask(x16.bit_and(y16), (left & right) & 0xFFFF, 16);
        check_mask(x16.bit_or(y16), (left | right) & 0xFFFF, 16);
        check_mask(x16.bit_not(), (~left) & 0xFFFF, 16);
        check_mask(x16.bit_or(x16.bit_not()), 0xFFFF, 16);
        check_mask(x16.bit_and(x16.bit_not()), 0, 16);
    }
    // Native-endian loads: repeated bytes have the same expected integer on
    // either endian. Nonuniform inputs distinguish both endpoints and widths.
    for offset in 32 {
        for value in [0, 1, 128, 255] {
            for i in 160 { data[i] = 7; }
            for i in 8 { data[offset + i] = value as u8; }
            assert(goosimd::load_u16(data[offset..offset + 2]) == (value as u16) * 0x0101);
            assert(goosimd::load_u32(data[offset..offset + 4]) == (value as u32) * 0x01010101);
            assert(goosimd::load_u64(data[offset..offset + 8]) == (value as u64) * 0x0101010101010101);
        }
        for i in 8 { data[offset + i] = (i + 1) as u8; }
        let a = goosimd::load_u16(data[offset..offset + 2]);
        let b = goosimd::load_u32(data[offset..offset + 4]);
        let c = goosimd::load_u64(data[offset..offset + 8]);
        assert(a == 0x0201 || a == 0x0102);
        assert(b == 0x04030201 || b == 0x01020304);
        assert(c == 0x0807060504030201 || c == 0x0102030405060708);
    }
    // Misses, first/last hits, unaligned loads, vector/tail boundaries,
    // and first-byte candidates whose following byte does not match.
    for offset in 8 {
        for len in 100 {
            for i in 160 { data[i] = 7; }
            check_search(data[offset..offset + len], 0, 255);
            for at in len {
                data[offset + at] = 0;
                check_search(data[offset..offset + len], 0, 255);
                if at + 1 < len {
                    data[offset + at + 1] = 255;
                    check_search(data[offset..offset + len], 0, 255);
                    data[offset + at + 1] = 7;
                }
                data[offset + at] = 7;
            }
        }
    }
    for i in 160 { data[i] = 255; }
    check_mask(goosimd::load<goosimd::U8x32>(data).eq(255), 0xFFFFFFFF, 32);
    check_search(data, 255, 255);
    check_search(data, 0, 0);
    print("goosimd checks passed");
}
