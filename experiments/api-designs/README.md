# SIMD API comparisons

This directory compares three byte-search interfaces using the same Goose
search kernels. It is benchmark tooling, not the supported package API.
For library usage, see the [package README](../../README.md) and
[API reference](../../API.md).

## Interfaces

| Interface | Example | Supported widths |
| --- | --- | --- |
| A: concrete vectors | `concrete::load32(bytes).eq(needle).first()` | 16 and 32 bytes |
| B: generic vectors | `generic::load<generic::U8x32>(bytes).eq(needle).first()` | 16 and 32 bytes |
| C: explicit AVX2 | `isa::load32(bytes).eq(needle).first()` | 32 bytes |

Vector width does not prescribe an instruction set: a 32-byte operation
can use two SSE2 registers. Masks contain comparison results (0/255 lanes).
C requires an availability check with `isa::supported()` before calling its
primitives. TinyCC reports C unavailable and uses A for `c_auto`.

The loaders are compile-time arguments to the kernels in `kernels.goose`:

```goose
pair_kernel(bytes, a, b, 32) { s => generic::load<generic::U8x32>(s) }
```

The block introduces no runtime closure. An AVX2 primitive cannot inline
into a baseline-target loop; the explicit-ISA comparison includes both
per-operation calls and a targeted whole-loop implementation.

## Build configurations

- Static AVX2: `-mavx2 -DGS_SIMD=0`. The executable requires AVX2.
- Runtime selection: Clang/x86 with `-DGS_SIMD=1`. Goose's `simd fn`
  selects a target-specific whole loop. The AVX2 level also requires FMA,
  BMI1/2, LZCNT, POPCNT, and OS support.
- Forced baseline: `-DGS_SIMD=0 -DAPI_DISABLE_AVX2` exercises C's fallback.
- GCC: A/B use the build target. C can select AVX2 helpers, but `simd fn`
  does not provide a runtime-selected whole loop.
- TinyCC: scalar A/B adapters, without SIMD acceleration.

## Run the checks and benchmarks

From the repository root on AVX2-capable Linux x86-64, with Goose, Clang,
GCC, and Python 3 installed:

```sh
python3 experiments/api-designs/run.py --goose /path/to/goose \
  --out /tmp/goosimd-designs --bench
```

The runner writes timing samples, compiler logs, assembly, and runtime
AVX2 loop extracts. It checks pair searches, byte-value/mask-lane operations,
and guard-page boundaries. The guard harness uses the generated `check_g`
symbol and checks its signature before compiling.

Benchmarks include 16- and 32-byte A/B widths, misses, early/late hits, and
short inputs. They warm up each process, use an opaque compiler barrier,
check result checksums, and interleave samples. Times include the barrier
call. These are API/kernel comparisons, not bstr parity measurements.
Inspect compiler output alongside timings: inlining alone does not ensure
that aggregate copies or bounds checks have been eliminated.

Forced fallback on an AVX2 CPU does not validate non-AVX2 hardware. ARM,
Windows, AVX-512 execution, and broader numeric operations are unverified.
