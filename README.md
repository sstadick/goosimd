# goosimd

**Placeholder only. This implementation is experimental and may be entirely
replaced.** Types, layout, and backend choices are not a stable API or ABI.
The generic byte-vector interface replaces the original `Bytes16`/`Bytes32`
experiment; there is no compatibility layer for that API.

Goose owns the algorithms. A package-supplied C header provides inline load,
comparison, and mask primitives. No consumer `--include`, separate SIMD
object, or LTO is needed. Requires a Goose compiler with `c_headers`
([merged PR](https://github.com/aardappel/goose/pull/141)).

## Releases

Current version: [v0.1.0](https://github.com/sstadick/goosimd/releases/tag/v0.1.0).
Versions are Git tags (`vMAJOR.MINOR.PATCH`). Pushing a version tag runs CI
and publishes a GitHub source release only after tests pass. CI also runs
on branch pushes and pull requests. The examples below track `main`.

## Use it in a Goose project

Save this as `main.goose` in your project. Goose fetches the package from
GitHub; no sibling checkout or consumer `--include` flag is needed.

```goose
import goosimd from "github.com/sstadick/goosimd@main";

type Bytes = goosimd::Vec<u8[32]>;

fn main() {
    let bytes = "abcdefghijklmnopqrstuvwxyz012345";
    let v = goosimd::load<Bytes>(bytes);
    let matches = v.eq('a').bit_or(v.eq('z'));
    print(matches.first());    // 0
    print(matches.last());     // 25
    print(matches.to_bits());  // bits 0 and 25
}
```

Run it with `goose run main.goose`, or build an executable with
`goose build main.goose -O2 -o demo`. These commands require a Goose version
with `c_headers` support. `@main` follows the development branch; use a
commit instead for a reproducible dependency.

## Byte vectors and masks

`U8x16` and `U8x32` are aliases for `Vec<u8[16]>` and `Vec<u8[32]>`.
Width describes the value, not the instruction set: a 32-byte vector can
use two SSE2 registers. Only these byte-vector instantiations are supported;
other element types and widths fail overload resolution.

| Operation | Contract |
| --- | --- |
| `load<V>(bytes)` | Read exactly the first vector-width bytes, allowing unaligned input; assert sufficient length. |
| `v.eq(byte)` | Produce `Mask<Lanes>` with `0xff` for equal lanes and zero otherwise. |
| `m.bit_and(n)`, `m.bit_or(n)`, `m.bit_not()` | Combine/invert masks of the same width. |
| `m.to_bits()` | Return a `u32`; lane 0 maps to bit 0. Bits above the mask width are zero. |
| `m.first()`, `m.last()` | Return the first/last matching lane, or -1 for an empty mask. |
| `load_u16/32/64(bytes)` | Checked, unaligned native-endian integer loads for byte comparisons. |

Masks are comparison results, **not arbitrary byte vectors**. Do not construct
or mutate masks with values other than 0/255. `to_bits()` is not a general
high-bit extraction operation. Use the checked loads, not the exposed raw
extern adapters. Integer loads are not portable serialization primitives.

## Compile-time and runtime selection

Ordinary `fn` consumers use the C compiler's build target. Compile emitted
C with `-mavx2` for an AVX2-only executable; without it, x86-64 uses SSE2.
Selecting `U8x16` versus `U8x32` is a compile-time type choice independent
of that target. The generic façade introduces no runtime type dispatch.

To select at runtime, put the **whole scan loop** in a Goose `simd fn`,
not a wrapper around each primitive. The included `find_byte` and `find_pair`
functions demonstrate this: Clang/x86 compiles target-specific versions and
dispatches outside the loop. The same `load`, `eq`, and mask methods inline
into each version; the header does not use a build-wide AVX2 choice for Clang.

```goose
// This calls the runtime-selected example loop.
let at = goosimd::find_pair("hello", 'l', 'o');  // 3
```

- Clang/x86 runtime AVX2 requires Goose's full target level: AVX2, FMA,
  BMI1/2, LZCNT, and POPCNT, plus OS register-state support. It is not an
  AVX2-only CPU check. `-DGS_SIMD=0` disables multiversioning in emitted C;
  `-DGS_SIMD=1` caps it at AVX2.
- GCC ignores Goose's `simd fn` multiversioning and uses the build target.
  Its baseline backend uses 16-byte chunks to avoid aggregate-copy penalties.
- TinyCC uses scalar adapters, not SIMD acceleration.
- Clang/GCC vector operations also support native targets such as AArch64.
  This revision is verified on Linux x86-64; ARM and Windows are unverified.
- `-DGOOSIMD_SCALAR` forces scalar adapters. Package build settings do not
  propagate architecture flags to the consumer's C compilation.

The example searches are not tuned bstr replacements. goostr implements its
own algorithms using these primitives. Generic functions taking a loader
can use a compile-time block, for example `{ s => goosimd::load<Bytes>(s) }`;
this avoids Goose's restriction on passing `load<Bytes>` as a function value.

## Representation

The header relies on Goose's generated struct names, such as
`goosimd_Vec_g7_a32_u8`, and the inline array layout. This is a compiler
integration detail, not a stable C type contract. Loads and vector conversions
use `memcpy`, without imposing alignment or aliasing requirements on callers.
The header contains primitives only, not search loops.

## Tests

```sh
python3 test/run.py --goose /path/to/goose --cc clang
# On an AVX2-capable machine:
python3 test/run.py --goose /path/to/goose --cc clang --avx2
python3 test/run.py --goose /path/to/goose --cc gcc --avx2
```

The runner uses ordinary `goose run` and `goose build` with a fresh
`GOOSE_HOME`, plus emitted C compiled natively, with scalar adapters, and
optionally with AVX2. It never passes `--include`. Tests cover every byte
value, vector lane and alignment; mask composition, inversion, first/last
positions; unaligned integer loads; and searches across vector/tail boundaries.

`experiments/api-designs/` retains the A/B/C comparison and measurements
that led to this generic interface. It is not part of the public API.

## License and attribution

MIT; see [LICENSE](LICENSE). The search examples follow the packed-pair
approach used by [memchr](https://github.com/BurntSushi/memchr), by Andrew
Gallant and contributors. For any memchr-derived material, we select its
[Unlicense option](https://docs.rs/crate/memchr/2.8.3/source/UNLICENSE).
The bstr-specific port and its notices belong to
[goostr](https://github.com/sstadick/goostr), not this package.
