#!/usr/bin/env python3
"""Wait for a quiet host, then run a focused same-round Foundation/kron comparison."""
import os
from pathlib import Path
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
THRESHOLD = 24.0
SAMPLES = 3
INTERVAL = 300

def load():
    with open('/proc/loadavg') as f:
        return float(f.read().split()[0])

def log(message):
    with (HERE / 'wait.log').open('a') as f:
        f.write(f'{time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())} load={load():.2f} {message}\n')

def main():
    if (HERE / 'run.log').exists() or (HERE / 'DONE').exists():
        print('refusing to overwrite an existing capture', file=sys.stderr)
        return 1
    quiet = 0
    while True:
        current = load()
        if current < THRESHOLD:
            quiet += 1
        else:
            quiet = 0
        log(f'quiet_samples={quiet}')
        if quiet >= SAMPLES:
            break
        time.sleep(INTERVAL)
    command = [
        sys.executable, str(ROOT / 'bench/cpp_reference/run.py'),
        '--output-dir', str(HERE),
        '--libraries', 'foundation,kron',
        '--events', '100000',
        '--warmup', '1000',
        '--repeats', '5',
        '--producers', '1,4',
        '--metadata', 'full',
        '--kron-schema', 'off',
        '--kron-modes', 'async,spsc',
        '--kron-storages', 'memory,mmap',
        '--affinity', 'auto',
    ]
    log('starting: ' + ' '.join(command))
    with (HERE / 'run.log').open('w') as output:
        result = subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT)
    log(f'exit={result.returncode}')
    (HERE / ('DONE' if result.returncode == 0 else 'FAILED')).write_text(f'{result.returncode}\n')
    return result.returncode

if __name__ == '__main__':
    sys.exit(main())
