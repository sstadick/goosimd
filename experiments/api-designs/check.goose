import api from "./api";
import kernels;

fn check(s: const u8[:], a: u8, b: u8) {
    var expected = -1;
    for i in max(0, s.len - 1) {
        if s[i] == a && s[i + 1] == b { expected = i; break; }
    }
    assert(a16(s, a, b) == expected);
    assert(a32(s, a, b) == expected);
    assert(b16(s, a, b) == expected);
    assert(b32(s, a, b) == expected);
    assert(a_auto(s, a, b) == expected);
    assert(b_auto(s, a, b) == expected);
    assert(c_auto(s, a, b) == expected);
    if isa::supported() { assert(c32(s, a, b) == expected); }
}

fn main() {
    var data: u8[160] = [7; 160];
    var cases = 0;
    for offset in 8 {
        for len in 97 {
            let s = data[offset..offset + len];
            check(s, 255, 0);
            check(s, 7, 7);
            cases += 2;
            for at in max(0, len - 1) {
                data[offset + at] = 255;
                data[offset + at + 1] = 0;
                check(s, 255, 0);
                data[offset + at] = 7;
                data[offset + at + 1] = 7;
                cases += 1;
            }
        }
    }
    var state: u64 = 123456789;
    for trial in 2000 {
        for i in 160 {
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            data[i] = (state >> 56) as u8;
        }
        let len = trial % 159;
        let s = data[1..len + 1];
        check(s, data[17], data[18]);
        check(s, 0, 255);
        cases += 2;
    }
    // Every byte value and mask lane, including bit 31; width 16 must
    // exclude hits in the upper half. No expected value uses a SIMD API.
    for value in 256 {
        for lane in 32 {
            for i in 160 { data[i] = (value as u8) ^ 1; }
            data[lane] = value as u8;
            let want = (1 as u32) << lane;
            let narrow = if lane < 16 { want } else { 0 };
            assert(concrete::load32(data).eq(value as u8).to_bits() == want);
            assert(generic::load<generic::U8x32>(data).eq(value as u8).to_bits() == want);
            assert(concrete::load16(data).eq(value as u8).to_bits() == narrow);
            assert(generic::load<generic::U8x16>(data).eq(value as u8).to_bits() == narrow);
            if isa::supported() {
                assert(isa::load32(data).eq(value as u8).to_bits() == want);
            }
        }
    }
    print(cases, " pair cases; 8192 mask cases passed; explicit AVX2: ", isa::supported());
}
