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

fn main() {
    var data: u8[160] = [0; 160];
    // Every byte value, lane and alignment, including bit 31 of the mask.
    for offset in 32 {
        for value in 256 {
            for lane in 32 {
                for i in 32 { data[offset + i] = (value as u8) ^ 1; }
                data[offset + lane] = value as u8;
                let eq = goosimd::eq8(goosimd::load32(data[offset..]), value as u8);
                assert(goosimd::mask8(eq) == (1 as u32) << lane);
                var expected: u8[32] = [0; 32];
                expected[lane] = 255;
                let want = goosimd::load32(expected);
                assert(eq.a == want.a && eq.b == want.b && eq.c == want.c && eq.d == want.d);
                let eq16 = goosimd::eq8(goosimd::load16(data[offset..offset + 16]), value as u8);
                let mask16: u32 = if lane < 16 { (1 as u32) << lane } else { 0 };
                assert(goosimd::mask8(eq16) == mask16);
                assert(eq16.a == want.a && eq16.b == want.b);
            }
        }
    }
    // Arbitrary bytes, not just comparison results. Compute bitwise results
    // byte by byte independently of the package's four-u64 implementation.
    var state: u64 = 123456789;
    var other: u8[32] = [0; 32];
    var combined: u8[32] = [0; 32];
    var union: u8[32] = [0; 32];
    var inverted: u8[32] = [0; 32];
    for trial in 1000 {
        var expected: u32 = 0;
        for i in 32 {
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            data[i] = (state >> 56) as u8;
            other[i] = (state >> 24) as u8;
            combined[i] = data[i] & other[i];
            union[i] = data[i] | other[i];
            inverted[i] = ~data[i];
            if data[i] >= 128 { expected |= (1 as u32) << i; }
        }
        assert(goosimd::mask8(goosimd::load32(data)) == expected);
        let got = goosimd::bit_and(goosimd::load32(data), goosimd::load32(other));
        let want = goosimd::load32(combined);
        assert(got.a == want.a && got.b == want.b && got.c == want.c && got.d == want.d);
        let either = goosimd::bit_or(goosimd::load32(data), goosimd::load32(other));
        let want_or = goosimd::load32(union);
        assert(either.a == want_or.a && either.b == want_or.b && either.c == want_or.c && either.d == want_or.d);
        let flip = goosimd::bit_not(goosimd::load32(data));
        let want_not = goosimd::load32(inverted);
        assert(flip.a == want_not.a && flip.b == want_not.b && flip.c == want_not.c && flip.d == want_not.d);
        let x16 = goosimd::load16(data);
        let y16 = goosimd::load16(other);
        assert(goosimd::mask8(x16) == (expected & 0xFFFF));
        let and16 = goosimd::bit_and(x16, y16);
        let or16 = goosimd::bit_or(x16, y16);
        let not16 = goosimd::bit_not(x16);
        assert(and16.a == want.a && and16.b == want.b);
        assert(or16.a == want_or.a && or16.b == want_or.b);
        assert(not16.a == want_not.a && not16.b == want_not.b);
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
    assert(goosimd::mask8(goosimd::load32(data)) == 4294967295);
    check_search(data, 255, 255);
    check_search(data, 0, 0);
    print("goosimd checks passed");
}
