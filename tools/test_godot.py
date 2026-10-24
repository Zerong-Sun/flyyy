#!/usr/bin/env python3
"""Isolated headless regression runner. Errors in logs fail even with exit code 0."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

if __package__:
    from .process_utils import run_process
else:
    from process_utils import run_process

ROOT = Path(__file__).resolve().parents[1]

def find_godot():
    configured = os.environ.get('GODOT_BIN') or os.environ.get('GODOT')
    mac = Path('/Applications/Godot.app/Contents/MacOS/Godot')
    return configured or shutil.which('godot') or shutil.which('godot4') or (str(mac) if mac.is_file() else None)

def log_passed(returncode, output):
    output = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', output)
    return returncode == 0 and not re.search(r'(SCRIPT ERROR:|(?:^|\n)\s*(?:ERROR:|SKIP:)|SMOKE_\w*_FAIL|VERIFY_\w*_FAIL)', output)

def isolated_config(config, save_dir):
    # Fail closed if the project layout changes; never silently use player saves.
    config, count = re.subn(r'^config/custom_user_dir_name=.*$',
                           lambda _: 'config/custom_user_dir_name="' + save_dir.as_posix() + '"',
                           config, flags=re.MULTILINE)
    enabled = re.findall(r'^config/use_custom_user_dir\s*=\s*(\w+)\s*$', config, re.MULTILINE)
    if count != 1 or enabled != ['true']:
        raise ValueError('Cannot isolate user data in project.godot')
    return config

def prepare_project(source, project, fresh_import=False):
    for child in source.iterdir():
        target = project / child.name
        if child.name == 'project.godot':
            continue
        if child.name == '.godot':
            # Imports write this cache. Never share it with the developer's editor.
            if not fresh_import:
                shutil.copytree(child, target)
            continue
        try:
            target.symlink_to(child, target_is_directory=child.is_dir())
        except OSError:
            # Windows without Developer Mode cannot create symlinks.
            if child.is_dir():
                shutil.copytree(child, target)
            else:
                shutil.copy2(child, target)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('scripts', nargs='*')
    parser.add_argument('--render', action='store_true', help='Open a real rendering window for UI captures')
    parser.add_argument('--godot', default=find_godot())
    parser.add_argument('--logs', type=Path, default=Path(tempfile.gettempdir()) / 'flyyy-upgrade-tests')
    parser.add_argument('--scenes', action='store_true', help='Also run every tests/verify_*.tscn scene')
    parser.add_argument('--import', dest='import_project', action='store_true', help='Force asset import (automatic without an import cache)')
    parser.add_argument('--timeout', type=float, default=100, help='Timeout per test in seconds')
    args = parser.parse_args()
    if not args.godot:
        parser.error('Godot not found: pass --godot or set GODOT_BIN')
    if args.timeout <= 0:
        parser.error('--timeout must be positive')
    args.logs.mkdir(parents=True, exist_ok=True)
    scripts = args.scripts or [p.name for p in sorted((ROOT / 'game/scripts/dev').glob('Smoke*.gd'))]
    if args.scenes:
        scripts += [p.name for p in sorted((ROOT / 'game/tests').glob('verify_*.tscn'))]
    if not scripts:
        parser.error('No Godot tests found')
    for script in scripts:
        base = ROOT / 'game' / ('tests' if script.endswith('.tscn') else 'scripts/dev')
        if Path(script).name != script or not (base / script).is_file():
            parser.error('Unknown test: ' + script)
    failures = []
    with tempfile.TemporaryDirectory(prefix='flyyy-godot-') as directory:
        project = Path(directory)
        prepare_project(ROOT / 'game', project, args.import_project)
        # Godot permits an absolute custom user dir; test saves never touch the player slot.
        config = (ROOT / 'game/project.godot').read_text(encoding='utf-8')
        (project / 'project.godot').write_text(isolated_config(config, project / 'saves' / 'import'), encoding='utf-8')
        if args.import_project or not (project / '.godot' / 'global_script_class_cache.cfg').is_file():
            try:
                imported = run_process([args.godot, '--headless', '--path', str(project), '--import'],
                                          capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=180)
                output = imported.stdout + imported.stderr
                (args.logs / 'import.log').write_text(output, encoding='utf-8')
                if not log_passed(imported.returncode, output):
                    print('FAIL asset import\n' + output[-2500:])
                    return 1
            except subprocess.TimeoutExpired:
                (args.logs / 'import.log').write_text('TIMEOUT after 180 seconds\n', encoding='utf-8')
                return 1
        for script in scripts:
            (project / 'project.godot').write_text(isolated_config(config, project / 'saves' / script), encoding='utf-8')
            target = ['res://tests/' + script] if script.endswith('.tscn') else ['-s', 'res://scripts/dev/' + script]
            command = [args.godot] + (['--rendering-method', 'gl_compatibility'] if args.render else ['--headless']) + ['--path', str(project)] + target
            try:
                result = run_process(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace', timeout=args.timeout)
                output = result.stdout
                if script == 'SmokeUpgrade.gd' and result.returncode == 0:
                    reopened = run_process(command + ['--', '--verify-reopen'], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace', timeout=30)
                    output += '\n--- Fresh-process save reload ---\n' + reopened.stdout
                    if reopened.returncode:
                        result = reopened
                ok = log_passed(result.returncode, output)
            except subprocess.TimeoutExpired as exc:
                output = (exc.stdout or b'').decode('utf-8', errors='replace') if isinstance(exc.stdout, bytes) else (exc.stdout or '')
                output += f'\nTIMEOUT after {exc.timeout} seconds\n'
                ok = False
            (args.logs / (script + '.log')).write_text(output, encoding='utf-8')
            print(('PASS ' if ok else 'FAIL ') + script, flush=True)
            if not ok:
                failures.append(script)
                print(output[-2500:], flush=True)
    return bool(failures)

if __name__ == '__main__':
    raise SystemExit(main())
