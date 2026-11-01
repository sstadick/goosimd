# goosimd

Compare 16 or 32 bytes at a time in [Goose](https://github.com/aardappel/goose),
combine the results as masks, and find matching positions.

**[API reference and examples](API.md)** · [Releases](https://github.com/sstadick/goosimd/releases)

**This is an experimental placeholder and will be replaced with a different
implementation.** Do not rely on stable types, layout, or API compatibility.

## Get started

Save this as `main.goose`. Goose downloads the package automatically:

```goose
import goosimd from "github.com/sstadick/goosimd@main";

fn main() {
    let bytes = "abcdefghijklmnopqrstuvwxyz012345";
    let v = goosimd::load<goosimd::U8x32>(bytes);
    let matches = v.eq('a').bit_or(v.eq('z'));
    print(matches.first());    // 0
    print(matches.last());     // 25
    print(matches.to_bits());  // 33554433: bits 0 and 25
}
```

```sh
goose run main.goose
goose build main.goose -O2 -o demo
```

Use a Goose compiler with package `c_headers` support. No `--include` flag
or separate library build is needed. The example follows `main`; use a
commit instead for a reproducible dependency.

## Compare and combine

`U8x16` and `U8x32` are shorthand for `Vec<u8[16]>` and `Vec<u8[32]>`.
Choose the width in your code. Only these byte-vector types are supported.
Each byte position is called a *lane*.

Inside `main()`, with the import above:

```goose
let v = goosimd::load<goosimd::U8x16>("red,green;blue___");
let separators = v.eq(',').bit_or(v.eq(';'));
assert(separators.first() == 3);
assert(separators.last() == 9);
assert(separators.to_bits() == 520); // Bits 3 and 9.
assert(separators.bit_not().first() == 0);
assert(v.eq('?').first() == -1);
```

| Operation | Result |
| --- | --- |
| `load<V>(bytes)` | Read the first 16 or 32 bytes; input must be at least that long. Alignment is not required. |
| `v.eq(byte)` | A mask marking lanes equal to the byte. |
| `m.bit_and(n)` | Lanes matched by both masks. |
| `m.bit_or(n)` | Lanes matched by either mask. |
| `m.bit_not()` | All lanes not matched by the mask. |
| `m.to_bits()` | A `u32` with one bit per matching lane; lane 0 is bit 0. |
| `m.first()`, `m.last()` | First or last matching lane, or -1 for no match. |

Combine masks of the same width. Create them through comparisons, not by
setting their fields: masks must contain only 0/255 lanes. Bits above the
vector width are zero in `to_bits()`.

For short byte comparisons, `load_u16`, `load_u32`, and `load_u64` read
unaligned integers with length checks. These use **native byte order**, so
they are not portable serialization functions.

## Search a whole slice

The package also provides simple searches that handle short inputs and tails:

```goose
assert(goosimd::find_byte("hello", 'l') == 2);
assert(goosimd::find_pair("hello", 'l', 'o') == 3);
assert(goosimd::find_byte("hello", '?') == -1);
```

For substring search, splitting, and other byte-string operations, use
[goostr](https://github.com/sstadick/goostr).

## Choose a compiler and target

Vector width and CPU instruction set are separate choices: a 32-byte vector
does not require an AVX2 CPU.

| Build | Behavior |
| --- | --- |
| `goose run` with TinyCC | Scalar fallback; no SIMD acceleration. |
| Native GCC | Uses the build target, normally SSE2 on x86-64. |
| Native Clang on x86 | Uses the build target in ordinary functions; Goose `simd fn` enables runtime selection. |

For runtime selection in your own algorithms, put the whole scan loop in
a `simd fn`. The included `find_byte` and `find_pair` use this approach.
Build with `goose build main.goose --cc clang -O2 -o demo` to use it.
GCC does not provide runtime selection for Goose's `simd fn`.

This complete example finds either separator, including in a short input or
the tail after the last full vector:

```goose
import goosimd from "github.com/sstadick/goosimd@main";

simd fn find_separator(bytes: const u8[:]) -> i64 {
    var pos = 0;
    while pos <= bytes.len - 32 {
        let v = goosimd::load<goosimd::U8x32>(bytes[pos..]);
        let at = v.eq(',').bit_or(v.eq(';')).first();
        if at >= 0 { return pos + at; }
        pos += 32;
    }
    for i in pos..bytes.len {
        if bytes[i] == ',' || bytes[i] == ';' { return i; }
    }
    return -1;
}

fn main() {
    assert(find_separator("red,green") == 3);
    assert(find_separator("abcdefghijklmnopqrstuvwxyz012345;") == 32);
    assert(find_separator("no separators") == -1);
}
```

To require AVX2 at compile time, compile emitted C with `-mavx2`; the resulting
executable requires an AVX2 CPU. For example, on Linux x86-64:

```sh
goose --standalone -O2 -o demo.c main.goose
clang -O2 -DGS_SIMD=0 -mavx2 demo.c -o demo -lm -pthread -ldl
./demo
```

`-DGS_SIMD=0` disables runtime selection in this fixed-target build.
Clang's runtime AVX2 selection also checks FMA, BMI1/2, LZCNT, POPCNT, and
OS support. Tested on Linux x86-64; ARM and Windows are unverified.

## Contributing

Tests require Python 3, Goose, and GCC or Clang:

```sh
python3 test/run.py --goose /path/to/goose --cc clang
# On an AVX2-capable machine:
python3 test/run.py --goose /path/to/goose --cc gcc --avx2
```

Edit API documentation in the source comments, not `API.md`. With
[goosdoc v0.2.0](https://github.com/sstadick/goosdoc/releases/tag/v0.2.0)
checked out at `../goosdoc`, run:

```sh
scripts/docs.sh
scripts/docs.sh --check
scripts/doctest.sh
scripts/doctest.sh --cc gcc
scripts/doctest.sh --cc clang
```

Set `GOOSDOC=/path/to/goosdoc/main.goose` for another location. Every API
declaration needs an executable example; see the
[example conventions](https://github.com/sstadick/goosdoc#executable-examples).
CI checks the reference and runs examples and tests before publishing releases.

## License

MIT; see [LICENSE](LICENSE). The search examples draw on
[memchr](https://github.com/BurntSushi/memchr) by Andrew Gallant and contributors;
memchr-derived material uses its
[Unlicense option](https://docs.rs/crate/memchr/2.8.3/source/UNLICENSE).
