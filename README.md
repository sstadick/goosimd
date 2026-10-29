# goosimd

**Placeholder only. This entire implementation will be replaced with a
different implementation.** The current API, types, layout, and backend choices
are experimental and will not be preserved for compatibility. Do not depend on
this package for production use.

This repository exists to test the proposed Goose `c_headers` package-build
option ([draft PR](https://github.com/aardappel/goose/pull/141)), not to establish a
finished SIMD library. It packages the byte-comparison experiment from goostr
as a small, standalone consumer of that option.

## Compiler requirement

Use a Goose compiler containing `feat/package-c-headers-upstream` from
[sstadick/goose](https://github.com/sstadick/goose/tree/feat/package-c-headers-upstream).
An unpatched compiler rejects `c_headers` as an unknown build setting.

The package's `goosimd.build` contains:

```goose
c_headers = ["include/goosimd.h"];
```

No consumer `--include`, `.c` source, separate SIMD object, or LTO is needed.
The header follows Goose's generated types in the consumer's C translation
unit, so the native C compiler can inline the adapters into Goose loops.

## Try it

```goose
import goosimd from "github.com/sstadick/goosimd@main";

fn main() {
    print(goosimd::find_byte("hello", 108));       // 2
    print(goosimd::find_pair("hello", 108, 111));  // 3
}
```

Save that as `demo.goose` and use the patched compiler:

```sh
goose run demo.goose
goose build -o demo demo.goose
./demo
```

For an adjacent local checkout, use `import goosimd from "../goosimd";`.
The `main` reference is intentionally moving; pin a commit when reproducing
a particular experiment.

## Temporary API

All names below are in `goosimd::`.

| Operation | Behavior |
| --- | --- |
| `load32(bytes)` | Read the first 32 bytes, allowing unaligned input; asserts at least 32 bytes are available. |
| `eq8(block, byte)` | Compare each byte; return `0xff` for equal lanes and zero otherwise. |
| `mask8(block)` | Extract each byte's high bit into bit `i` of a `u32`; byte 0 maps to bit 0. |
| `bit_and(a, b)` | Bitwise AND of two 32-byte blocks, implemented in Goose. |
| `find_byte(bytes, byte)` | Example Goose loop returning the first match index, or -1. |
| `find_pair(bytes, a, b)` | Example Goose loop finding adjacent bytes, or -1. |

`Bytes32` is temporarily four `u64` fields. The header relies on Goose's
generated type name and layout; this is not a stable vector ABI. The exposed
`load32_raw` adapter is unchecked; use `load32` instead.

## Backends and limitations

- Native x86-64: SSE2 by default, AVX2 when compiled with `-mavx2`.
- Native AArch64: NEON.
- TinyCC: scalar fallback, **not SIMD acceleration**.
- Other native targets: scalar fallback; `-DGOOSIMD_SCALAR` forces it.
- Selection is compile-time only. There is **no runtime CPU dispatch**;
  AVX2 executables require an AVX2-capable CPU.
- The search loops are examples, not tuned bstr replacements. This package
  does not claim performance parity with bstr or goostr's production kernels.
- `c_headers` does not propagate package C flags to the application. Pass
  architecture flags to the native compiler when building emitted C.

## Test with the patched build

The runner exercises ordinary `goose run` and `goose build` with a fresh
`GOOSE_HOME`, plus emitted C compiled natively and with the scalar fallback.
It never passes `--include`. Python 3 and a GCC/Clang-style C driver are needed.

```sh
python3 test/run.py --goose /path/to/patched/goose --cc clang

# On Marvin (AVX2-capable x86-64):
python3 test/run.py \
  --goose /home/seth/dev/goose_book/.tools/goose/build/goose \
  --cc clang --avx2
```

Repeat with `--cc gcc` to test GCC. `--avx2` applies to the additional emitted-C
build; ordinary `goose build` retains its default target. Tests cover every
byte value, vector lane and alignment, arbitrary high-bit masks, bitwise AND,
and byte/pair searches across vector and tail boundaries. They check
correctness, not throughput.
