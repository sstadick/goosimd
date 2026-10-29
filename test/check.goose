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
            }
        }
    }
    // Arbitrary bytes, not just comparison results. Compute the expected AND
    // byte by byte independently of the package's four-u64 implementation.
    var state: u64 = 123456789;
    var other: u8[32] = [0; 32];
    var combined: u8[32] = [0; 32];
    for trial in 1000 {
        var expected: u32 = 0;
        for i in 32 {
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            data[i] = (state >> 56) as u8;
            other[i] = (state >> 24) as u8;
            combined[i] = data[i] & other[i];
            if data[i] >= 128 { expected |= (1 as u32) << i; }
        }
        assert(goosimd::mask8(goosimd::load32(data)) == expected);
        let got = goosimd::bit_and(goosimd::load32(data), goosimd::load32(other));
        let want = goosimd::load32(combined);
        assert(got.a == want.a && got.b == want.b && got.c == want.c && got.d == want.d);
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
