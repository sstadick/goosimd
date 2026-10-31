import api from "./api";
import kernels;
import os;

extern fn opaque_len(s: const u8[:]) -> i64 = "bench_opaque";

fn measure<F>(s: const u8[:], iterations: i64, expected: i64) {
    var elapsed = 0;
    var checksum = 0;
    for pass in 2 {
        checksum = 0;
        let start = clock_ns();
        for i in iterations { checksum += F(s[..opaque_len(s)], 255, 0) + 1; }
        elapsed = clock_ns() - start;
        assert(checksum == (expected + 1) * iterations);
    }
    print(elapsed, " ", checksum);
}

fn main() {
    let argv = args();
    assert(argv.len == 5);
    let size, size_ok = parse_int(argv[2]);
    let iterations, iter_ok = parse_int(argv[4]);
    assert(size_ok && iter_ok && size >= 2 && iterations > 0);
    var s: u8[>..] = [];
    s.resize(size, 7);
    var expected = -1;
    if argv[3] == "first" { expected = 0; }
    else if argv[3] == "last" { expected = size - 2; }
    else { assert(argv[3] == "miss"); }
    if expected >= 0 { s[expected] = 255; s[expected + 1] = 0; }
    if argv[1] == "a16" { measure(s, iterations, expected, a16); }
    else if argv[1] == "a32" { measure(s, iterations, expected, a32); }
    else if argv[1] == "b16" { measure(s, iterations, expected, b16); }
    else if argv[1] == "b32" { measure(s, iterations, expected, b32); }
    else if argv[1] == "a-auto" { measure(s, iterations, expected, a_auto); }
    else if argv[1] == "b-auto" { measure(s, iterations, expected, b_auto); }
    else if argv[1] == "c-auto" { measure(s, iterations, expected, c_auto); }
    else { assert(argv[1] == "c32" && isa::supported()); measure(s, iterations, expected, c32); }
}
