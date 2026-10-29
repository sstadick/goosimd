#!/usr/bin/env python3
"""Check the placeholder package through c_headers, never --include."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", default="goose", help="patched Goose compiler")
    parser.add_argument("--cc", default="cc", help="GCC/Clang-style C driver")
    parser.add_argument("--avx2", action="store_true", help="also run AVX2; requires an AVX2 CPU")
    args = parser.parse_args()
    goose = shutil.which(args.goose)
    cc = shutil.which(args.cc)
    if not goose or not cc:
        parser.error("both --goose and --cc must name available executables")
    goose, cc = str(Path(goose).resolve()), str(Path(cc).resolve())
    root = Path(__file__).resolve().parent.parent
    source = root / "test" / "check.goose"
    suffix = ".exe" if os.name == "nt" else ""
    with tempfile.TemporaryDirectory(prefix="goosimd-") as tmp:
        out = Path(tmp)
        env = dict(os.environ, GOOSE_HOME=str(out / "home"))

        def run(command, expected=None):
            result = subprocess.run([str(x) for x in command], cwd=out, env=env,
                                    capture_output=True, text=True, timeout=180)
            if result.returncode or (expected is not None and result.stdout.strip() != expected):
                raise RuntimeError(f"{command}\n{result.stdout}{result.stderr}")

        for level in (0, 2):
            run([goose, "run", f"-O{level}", source], "goosimd checks passed")
            print(f"PASS TinyCC -O{level}", flush=True)
        native = out / ("native" + suffix)
        run([goose, "build", "--cc", cc, "-o", native, source])
        run([native], "goosimd checks passed")
        print("PASS ordinary package build", flush=True)

        cfile = out / "check.c"
        run([goose, "--standalone", "-o", cfile, source])
        variants = [("native", []), ("scalar", ["-DGOOSIMD_SCALAR"])]
        if args.avx2:
            variants.append(("avx2", ["-mavx2"]))
        libs = [] if os.name == "nt" else ["-lm", "-pthread"]
        if sys.platform.startswith("linux"):
            libs.append("-ldl")
        for name, flags in variants:
            binary = out / (name + suffix)
            run([cc, "-O2", *flags, cfile, "-o", binary, *libs])
            run([binary], "goosimd checks passed")
            print(f"PASS emitted C ({name})", flush=True)


if __name__ == "__main__":
    main()
