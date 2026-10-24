#!/usr/bin/env python3
"""Run Python, mobile logic and isolated Godot regressions; retain every log."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time

if __package__:
    from .process_utils import run_process
else:
    from process_utils import run_process

ROOT = Path(__file__).resolve().parents[1]
REQUIRED_STAGES = ('python', 'mobile', 'godot')


def write_summary(path, report):
    temporary = path.with_suffix('.json.tmp')
    temporary.write_text(json.dumps(report, indent=2), encoding='utf-8')
    temporary.replace(path)


def run_stages(stages, logs):
    """A report covers this invocation only; an interrupted run stays incomplete."""
    report = {
        'schema_version': 1,
        'started_at': datetime.now(timezone.utc).isoformat(),
        'status': 'running',
        'required_stages': list(REQUIRED_STAGES),
        'selected_stages': [name for name, *_ in stages],
        'results': [],
    }
    summary = logs / 'summary.json'
    write_summary(summary, report)
    for name, command, cwd, timeout in stages:
        started = time.monotonic()
        print('RUN ' + name, flush=True)
        log = logs / (name + '.log')
        row = {'stage': name, 'status': 'running', 'exit_code': None, 'log': str(log)}
        report['results'].append(row)
        write_summary(summary, report)
        with log.open('w', encoding='utf-8') as output:
            try:
                code = run_process(command, cwd=cwd, stdout=output, stderr=subprocess.STDOUT, timeout=timeout).returncode
            except (OSError, subprocess.TimeoutExpired) as error:
                output.write(str(error) + '\n')
                code = 1
        row.update(status='passed' if code == 0 else 'failed', exit_code=code,
                   seconds=round(time.monotonic() - started, 2))
        write_summary(summary, report)
        print(('PASS ' if code == 0 else 'FAIL ') + name + ' — ' + str(log), flush=True)
    failed = not stages or any(row['exit_code'] != 0 for row in report['results'])
    complete = set(report['selected_stages']) == set(REQUIRED_STAGES)
    report['status'] = 'failed' if failed else ('passed' if complete else 'partial')
    report['completed_at'] = datetime.now(timezone.utc).isoformat()
    write_summary(summary, report)
    print('QUALITY ' + report['status'].upper(), flush=True)
    return int(failed)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--logs', type=Path, default=ROOT / 'dist' / 'quality')
    parser.add_argument('--godot', help='Godot executable; otherwise use GODOT_BIN or PATH')
    parser.add_argument('--stage', nargs='+', choices=['python', 'mobile', 'godot'],
                        help='Run selected stages only; report partial validation without reusing old results')
    args = parser.parse_args()
    args.logs = args.logs.resolve()
    args.logs.mkdir(parents=True, exist_ok=True)
    # Clear stale success even if preflight fails before any test can start.
    write_summary(args.logs / 'summary.json', {
        'schema_version': 1, 'status': 'preflight', 'results': [],
        'started_at': datetime.now(timezone.utc).isoformat(),
    })
    if sys.version_info < (3, 11):
        parser.error('Python 3.11+ is required; activate the ETL virtual environment first')
    dependencies = [name for name in ('pytest', 'yaml', 'PIL', 'numpy') if importlib.util.find_spec(name) is None]
    if dependencies:
        parser.error('Missing dependencies: ' + ', '.join(dependencies) + '. Install etl/requirements.txt with this Python interpreter')
    required = ['game/data/world.json', 'game/data/flights/_manifest.json', 'etl/out/coverage_report.json',
                'game/data/product_market_tags.json', 'game/data/achievements.json',
                'game/data/steam_achievements.json', 'game/data/news_events.json']
    missing = [name for name in required if not (ROOT / name).is_file()]
    if missing:
        parser.error('Generate full ETL data before validation: ' + ', '.join(missing))
    node = shutil.which('node')
    if not node:
        parser.error('Node.js is required for mobile logic tests')
    engine = [sys.executable, str(ROOT / 'tools/test_godot.py'), '--import', '--scenes', '--logs', str(args.logs / 'godot')]
    if args.godot:
        engine += ['--godot', args.godot]
    stages = [
        ('python', [sys.executable, '-m', 'pytest', '-q', '-ra'], ROOT, 900),
        ('mobile', [node, '--test', *[str(p) for p in sorted((ROOT / 'ios/expo/src/__tests__').glob('*.test.mjs'))]], ROOT / 'ios/expo', 120),
        ('godot', engine, ROOT, 1800),
    ]
    return run_stages([stage for stage in stages if not args.stage or stage[0] in args.stage], args.logs)


if __name__ == '__main__':
    raise SystemExit(main())
