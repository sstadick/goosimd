# SIMD API experiments

Three isolated library prototypes. They do not change the existing goosimd
API or the Goose compiler. This is a byte-search experiment, not a complete
SIMD library: load, equality, mask AND, bit extraction, and first matching
lane are implemented. A and B support 16 and 32 byte lanes; C exposes AVX2
32-byte operations. Masks are comparison results (0/255 lanes).

## A: concrete portable vectors

```goose
let v = concrete::load32(bytes);
let hit = v.eq(needle).first();
```

`U8x16`, `U8x32`, `Mask16`, and `Mask32` are concrete structs. Width describes
the value, not the ISA: a 32-byte operation can use two SSE2 registers.
This is the simplest interface; B now matches its GCC baseline bulk speed.

## B: generic vector façade

```goose
type Bytes = generic::Vec<u8[32]>;
let v = generic::load<Bytes>(bytes);
let hit = v.eq(needle).first();
```

`generic::U8x32` is an alias for `Vec<u8[32]>`. The façade and masks are
generic; only the extern declarations enumerate concrete instantiations.
Unsupported widths fail overload resolution, rather than silently falling
back to scalar code. Type inference supports method-style calls across the
package boundary.

Goose does not accept a specialized function name such as `load<U8x32>` as
a function-value expression in this compiler. Passing it to the shared
kernel needs a compile-time block:

```goose
pair_kernel(bytes, a, b, 32) { s => generic::load<generic::U8x32>(s) }
```

The block introduces no runtime closure. Clang removes the façade's copies.
GCC 13's baseline backend needs loads split into 16-byte chunks to eliminate
copies of array-backed values. This is internal to the header; the generic
API and storage layout are unchanged. See the investigation below.

## C: explicit AVX2 bindings

```goose
if isa::supported() {
    let hit = isa::load32(bytes).eq(needle).first();
}
```

`isa` means AVX2 in this prototype. Its native primitives carry an AVX2
target attribute. Availability includes compiler support and the CPU/OS
feature check. TinyCC reports unavailable; `c_auto` then uses A instead.
Raw C-style primitives require the caller to check availability.

An AVX2 primitive cannot inline into a baseline-target loop. The baseline
C kernel consequently calls helpers for each operation. An AVX2-targeted
kernel removes those calls. Availability alone does not ensure good code.

## Static and runtime selection

All three use the same Goose two-byte search algorithm in `kernels.goose`.
Its loader is a compile-time function argument. `a32`, `b32`, and `c32`
are ordinary functions; `a_auto`, `b_auto`, and C's `c_targeted` use
Goose's existing `simd fn` multiversioning. `c_auto` checks AVX2 availability
before entering the explicit-ISA kernel and otherwise falls back to A.

- Static AVX2: compile emitted C with `-mavx2 -DGS_SIMD=0`. The executable
  requires AVX2 even if a runtime availability check would say otherwise.
- Runtime selection: Clang/x86, baseline compilation with `-DGS_SIMD=1`.
  Goose emits a baseline and an AVX2 kernel, selecting outside the loop.
  Its AVX2 level also requires FMA, BMI1/2, LZCNT, and POPCNT, not just AVX2.
- Forced baseline: `-DGS_SIMD=0 -DAPI_DISABLE_AVX2` exercises C's fallback.
- GCC currently ignores `simd fn`: A/B stay at the build target, while C's
  availability check can enter AVX2 helpers without getting a targeted loop.
- TinyCC uses scalar A/B adapters, with no SIMD acceleration.

A/B's Clang adapters use target-neutral vector expressions and packed
boolean masks, allowing each function version to lower independently.
The runtime AVX2 loops of all three contain vector comparisons and mask
extraction with no primitive calls. The detected runtime level on Marvin
was 1 (AVX2). This experiment does not add a public runtime policy object
or a mechanism to force a particular function version.

## Measurements on Marvin

Ryzen 9 3950X, Clang 18.1.3 / GCC 13.3.0, `-O2`, CPU 2. Medians of five
samples with randomized interleaving. Each process warms up once, uses an
opaque compiler barrier to prevent invariant searches being hoisted, and
checks its checksum. Times include the barrier call. Goose binary reports
`v2026.3-145-g6958c54e-dirty`, runtime `f2981814a754` (with `c_headers`).

| 1 MiB pair miss | A | B | C |
| --- | ---: | ---: | ---: |
| Clang, static AVX2 (`*32`) | 23.68 µs | 20.13 µs | 23.52 µs |
| Clang, runtime selected (`*-auto`) | 23.60 µs | 19.90 µs | 23.54 µs |
| GCC, static AVX2 (`*32`) | 31.23 µs | 23.80 µs | 26.85 µs |
| GCC, baseline build (`*32`) | 39.00 µs | 38.96 µs | 1117.56 µs |

| Clang runtime-selected operation | A | B | C |
| --- | ---: | ---: | ---: |
| 24-byte miss (scalar tail) | 10.26 ns | 10.15 ns | 10.49 ns |
| 64-byte first hit | 3.12 ns | 2.93 ns | 3.36 ns |

These are untuned kernels, not bstr parity results. The common source still
produces different bounds-check sequences and loop layouts. B's Clang
bulk win is not evidence that generics are intrinsically faster. C's baseline
results are highly variable but consistently much slower; its per-operation
calls and aggregate copies are the wrong boundary for runtime dispatch.

B is the preferred public API now that its bulk copy penalty is resolved.
A remains a useful concrete control. C is useful as an explicitly targeted
expert layer, not the portable default.

### GCC baseline copy investigation

The original 32-byte `memcpy` load left aggregate assignments in GCC's
optimized C representation. B's inner search loop contained 16 redundant
16-byte stack stores per iteration, despite all primitives being inlined.
The default type tag and generic forwarding were not runtime calls.

Loading two 16-byte chunks, matching the baseline comparison backend,
removes those stores without changing `Vec<u8[32]>`, the Goose algorithm,
or compiler flags. Splitting loads unconditionally regressed GCC AVX2,
so the workaround applies only to the GCC non-AVX2 vector backend. For that
header-only change, the Clang baseline/runtime/AVX2 and GCC AVX2 benchmark
executables had identical `.text` sections before and after.

The header change reduced GCC baseline B's 1 MiB miss from 138.59 to
47.06 µs, matching A's 47.05 µs in a nine-sample comparison. It also changed
the generated scalar tails: B's 24-byte miss increased from 15.10 to
18.59 ns, and its 64-byte last hit from 18.69 to 25.11 ns.

### Fixed loop bounds

Both loops now compare their index against a fixed end: `s.len - width`
for vector loads and `s.len - 1` for scalar pairs. The scalar `for` loop
lets the compiler prove that both adjacent byte indexes are in range.
GCC's B tail uses one index and no per-iteration bounds checks. The generic
API, load adapters, and search order are unchanged.

Nine randomized, interleaved samples on CPU 2 compared the original binary,
the header-only fix, and the fixed-bound loops. With GCC baseline B:

- 24-byte miss: 18.46 → 13.48 ns (original: 14.98 ns).
- 64-byte last hit: 24.82 → 17.60 ns (original: 18.64 ns).
- 64-byte first hit: 2.36 → 2.11 ns.
- 1 MiB miss: 46.82 → 39.16 µs, preserving the bulk-copy improvement.

B's 16-byte-width tails improved too: 24-byte miss 8.17 → 6.49 ns and
64-byte last hit 15.53 → 11.73 ns. Clang runtime B improved from 15.43 to
10.44 ns for the 24-byte miss, 18.37 to 12.06 ns for the 64-byte last hit,
and 20.97 to 19.95 µs for the 1 MiB miss.

These results fix the reported B tail regressions, not every timing change:
GCC A32's 24-byte miss and 64-byte last hit returned near their original
timings (18.46 and 24.30 ns), slower than the intermediate header-only
build (14.97 and 17.87 ns). GCC B16's first hit likewise returned from
1.64 to its original 2.11 ns. Loop layout and scheduling still affect the
individual prototypes; the generic API does not imply identical machine code.

## Reproduce

From the repository root on an AVX2 Linux x86-64 machine with Clang and GCC:

```sh
python3 experiments/api-designs/run.py --goose /path/to/goose \
  --out .amp/in/artifacts/simd-designs --bench
```

The runner produces timing samples, compiler logs, full assembly, and the
three runtime AVX2 loop extracts. Benchmarks include both 16- and 32-byte
A/B widths. Its checks cover 42,032 pair cases,
8,192 byte-value/mask-lane cases, and 25,762 guard-page configurations.
TinyCC debug O0/O2, Clang/GCC baseline and AVX2, forced fallback, scalar
adapters, and ASan/UBSan passed. The existing package's Clang test runner
also passed. GCC emits optimization-attribute redeclaration warnings.

Fallback was forced on the AVX2 machine, not tested on non-AVX2 hardware.
ARM, Windows, AVX-512 execution, and broader numeric operations are untested.
The guard harness deliberately depends on the generated `check_g` name;
the runner checks its signature before compiling the harness.
