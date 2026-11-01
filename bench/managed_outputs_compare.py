#!/usr/bin/env python3
"""Paired complete-process managed API comparison with a full JSON output oracle."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import statistics
import subprocess
import tempfile

MODES = ('sync', 'memory', 'mmap', 'spsc_memory', 'spsc_mmap')

def validate_output(path, iterations):
    expected = list(range(1000)) + list(range(iterations))
    count = 0
    with path.open() as source:
        for count, line in enumerate(source, 1):
            event = json.loads(line)
            if count > len(expected):
                raise ValueError('unexpected output record')
            if event['attributes'] != {'id': expected[count - 1], 'payload': 'constant-value'} or event['message'] != 'managed output' or event['scope'] != 'managed.bench' or event['severity'] != 'info':
                raise ValueError('wrong workload or incomplete JSON')
    if count != len(expected):
        raise ValueError('missing output records')
    return count

def trial(binary, mode, args, label, repetition, cpus):
    with tempfile.TemporaryDirectory(prefix='kron-managed-') as directory:
        command = [str(binary.resolve()), mode, directory, str(args.iterations)]
        if cpus:
            command = ['taskset', '-c', ','.join(map(str, cpus))] + command
        result = subprocess.run(command, check=True, capture_output=True, text=True, timeout=60)
        lines = result.stdout.splitlines()
        if len(lines) != 1:
            raise ValueError('wrong report cardinality')
        report = json.loads(lines[0])
        expected = args.iterations + 1000
        if report['iterations'] != args.iterations or report['warmup'] != 1000 or report['accepted'] != expected or report['written'] != expected or report['pending'] != 0 or report['runtime_allocations'] != 0 or report['backend'] != 'portable' or report['mode'] != mode:
            raise ValueError('invalid completion or workload report')
        if report['producer_ns'] <= 0 or report['complete_ns'] < report['producer_ns']:
            raise ValueError('invalid timing')
        report['verified_json_records'] = validate_output(Path(directory) / 'events.jsonl', args.iterations)
        report.update(label=label, repetition=repetition, cpus=cpus)
        return report

def summarize(rows):
    result = []
    rng = random.Random(2147)
    for mode in MODES:
        pair = {label: sorted((r for r in rows if r['mode'] == mode and r['label'] == label), key=lambda r: r['repetition']) for label in ('before', 'after')}
        item = {'mode': mode, 'trials_per_version': len(pair['before'])}
        for metric in ('producer_ns', 'complete_ns', 'initialization_ns'):
            before = [r[metric] for r in pair['before']]
            after = [r[metric] for r in pair['after']]
            ratios = [b / a for b, a in zip(before, after)]
            draws = sorted(statistics.median(rng.choices(ratios, k=len(ratios))) for _ in range(10000))
            lower, upper = draws[249], draws[9749]
            item[metric] = {'before_median': statistics.median(before), 'after_median': statistics.median(after), 'paired_speed_ratio': statistics.median(ratios), 'paired_ratio_ci95': [lower, upper], 'assessment': 'improvement' if lower > 1 else 'regression' if upper < 1 else 'inconclusive'}
        result.append(item)
    return result

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--before', type=Path, required=True)
    parser.add_argument('--after', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--iterations', type=int, default=20000)
    parser.add_argument('--repetitions', type=int, default=12)
    args = parser.parse_args()
    if not 1000 <= args.iterations <= 1000000 or not 5 <= args.repetitions <= 30:
        parser.error('bounded iterations and 5..30 repetitions required')
    args.out.mkdir(parents=True, exist_ok=True)
    cpus = sorted(os.sched_getaffinity(0))[:2] if hasattr(os, 'sched_getaffinity') else []
    metadata = {'iterations': args.iterations, 'repetitions': args.repetitions, 'cpus': cpus, 'platform': dict(zip(('sysname', 'nodename', 'release', 'version', 'machine'), os.uname())), 'binaries': {label: hashlib.sha256(path.read_bytes()).hexdigest() for label, path in [('before', args.before), ('after', args.after)]}, 'loadavg_before': os.getloadavg(), 'semantics': 'producer capture through written shutdown; initialization separately reported; warmup drained before timing'}
    rows = []
    raw = args.out / 'trials.jsonl'
    with raw.open('w') as destination:
        for repetition in range(args.repetitions):
            for mode in MODES[repetition % len(MODES):] + MODES[:repetition % len(MODES)]:
                order = ('before', 'after') if repetition % 2 == 0 else ('after', 'before')
                for label in order:
                    row = trial(getattr(args, label), mode, args, label, repetition, cpus)
                    rows.append(row)
                    destination.write(json.dumps(row) + '\n')
                    destination.flush()
            print(f'{repetition+1}/{args.repetitions} paired rounds; {len(rows)} fully verified trials', flush=True)
    metadata.update(loadavg_after=os.getloadavg(), verified_json_records=sum(r['verified_json_records'] for r in rows), trials=len(rows))
    (args.out / 'metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
    (args.out / 'comparison.json').write_text(json.dumps(summarize(rows), indent=2) + '\n')

if __name__ == '__main__':
    main()
