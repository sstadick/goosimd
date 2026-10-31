#!/usr/bin/env python3
"""Build, check, inspect and optionally benchmark the three API prototypes."""
import argparse
import json
import os
from pathlib import Path
import random
import re
import shutil
import statistics
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--goose', default='goose')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--bench', action='store_true')
    parser.add_argument('--cpu', type=int, default=2)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    goose = shutil.which(args.goose)
    if not goose:
        parser.error('Goose compiler not found')
    env = dict(os.environ, GOOSE_HOME=str(out / 'home'))
    logs = []

    def run(cmd, quiet=False):
        cmd = [str(x) for x in cmd]
        r = subprocess.run(cmd, cwd=root, env=env, text=True, capture_output=True)
        logs.append('$ ' + ' '.join(cmd) + '\n' + r.stdout + r.stderr)
        (out / 'validation.log').write_text('\n'.join(logs))
        if r.returncode:
            raise RuntimeError(logs[-1])
        if not quiet:
            print('PASS', ' '.join(cmd), r.stdout.strip(), flush=True)
        return r.stdout

    for level in (0, 2):
        run([goose, 'run', '--debug', f'-O{level}', root / 'check.goose'])
    for name in ('check', 'bench'):
        run([goose, '--standalone', '-o', out / f'{name}.c', root / f'{name}.goose'])
    source = (out / 'check.c').read_text()
    assert re.search(r'static void check_g\(void \*\w+, int64_t \w+, uint8_t \w+, uint8_t \w+\)', source)
    libs = ['-lm', '-pthread', '-ldl']
    variants = {
        'clang-runtime': ['clang', '-O2', '-DGS_SIMD=1'],
        'clang-baseline': ['clang', '-O2', '-DGS_SIMD=0', '-DAPI_DISABLE_AVX2'],
        'clang-avx2': ['clang', '-O2', '-DGS_SIMD=0', '-mavx2'],
        'gcc-baseline': ['gcc', '-O2'],
        'gcc-avx2': ['gcc', '-O2', '-mavx2'],
        'scalar': ['clang', '-O2', '-DGS_SIMD=0', '-DAPI_SCALAR'],
        'sanitized': ['clang', '-O1', '-DGS_SIMD=1', '-fsanitize=address,undefined', '-fno-omit-frame-pointer'],
    }
    for name, flags in variants.items():
        binary = out / name
        run([*flags, out / 'check.c', *libs, '-o', binary])
        run([binary])
        run([*flags, '-I', out, root / 'guard.c', *libs, '-o', out / f'{name}-guard'])
        run([out / f'{name}-guard'])
        if name in ('scalar', 'sanitized'):
            continue
        run([*flags, out / 'bench.c', *libs, '-o', out / f'{name}-bench'])
        run([*flags, '-S', out / 'bench.c', '-o', out / f'{name}.s'])

    # These checks concern the actual specialized loops, not unrelated runtime
    # code that also contains vector instructions or function calls.
    asm = (out / 'clang-runtime.s').read_text()
    for name in ('a_auto_g_simd1', 'b_auto_g_simd1', 'c_targeted_g_simd1'):
        body = asm.split(name + ':', 1)[1].split('.size', 1)[0]
        assert re.search(r'vpcmpeqb.*%ymm', body), name
        assert 'vpmovmskb' in body, name
        assert not re.search(r'callq?\s+[abc]_(?:load|eq|and|bits)', body), name
        (out / f'{name}.s').write_text(body)
    print('PASS all three runtime AVX2 loops inline the primitives', flush=True)

    if not args.bench:
        return
    # Alternating randomized order, pinned CPU, warmup inside each process.
    # Includes the same opaque call and checksum in every measurement.
    workloads = [(24, 'miss', 1000000), (64, 'first', 1000000),
                 (64, 'last', 1000000), (1048576, 'miss', 500)]
    jobs = []
    for build in ('clang-runtime', 'clang-avx2', 'gcc-baseline', 'gcc-avx2'):
        for api in ('a16', 'b16', 'a32', 'b32', 'c32', 'a-auto', 'b-auto', 'c-auto'):
            for size, kind, iterations in workloads:
                jobs.append((build, api, size, kind, iterations))
    values = {job: [] for job in jobs}
    rng = random.Random(42)
    for sample in range(5):
        rng.shuffle(jobs)
        for job in jobs:
            build, api, size, kind, iterations = job
            output = run(['taskset', '-c', args.cpu, out / f'{build}-bench',
                          api, size, kind, iterations], quiet=True)
            elapsed, checksum = map(int, output.split())
            expected = 0 if kind == 'miss' else (1 if kind == 'first' else size - 1)
            assert checksum == expected * iterations
            values[job].append(elapsed / iterations)
        print(f'PASS benchmark sample {sample + 1}/5', flush=True)
    result = [dict(build=j[0], api=j[1], bytes=j[2], kind=j[3],
                   median_ns=statistics.median(v), samples_ns=v)
              for j, v in sorted(values.items())]
    (out / 'results.json').write_text(json.dumps(result, indent=2) + '\n')
    for row in result:
        print(row['build'], row['api'], row['bytes'], row['kind'], round(row['median_ns'], 2))


if __name__ == '__main__':
    main()
