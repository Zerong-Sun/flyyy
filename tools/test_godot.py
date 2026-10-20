#!/usr/bin/env python3
"""Isolated headless regression runner. Errors in logs fail even with exit code 0."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('scripts', nargs='*')
    parser.add_argument('--render', action='store_true', help='Open a real rendering window for UI captures')
    parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', '/Applications/Godot.app/Contents/MacOS/Godot'))
    parser.add_argument('--logs', type=Path, default=Path('/tmp/flyyy-upgrade-tests'))
    args = parser.parse_args()
    args.logs.mkdir(parents=True, exist_ok=True)
    scripts = args.scripts or [p.name for p in sorted((ROOT / 'game/scripts/dev').glob('Smoke*.gd'))]
    failures = []
    with tempfile.TemporaryDirectory(prefix='flyyy-godot-') as directory:
        project = Path(directory)
        for child in (ROOT / 'game').iterdir():
            if child.name != 'project.godot':
                (project / child.name).symlink_to(child, target_is_directory=child.is_dir())
        # Godot permits an absolute custom user dir; test saves never touch the player slot.
        config = (ROOT / 'game/project.godot').read_text()
        config = config.replace('config/custom_user_dir_name="WanliTrader"', f'config/custom_user_dir_name="{project / "saves"}"')
        (project / 'project.godot').write_text(config)
        for script in scripts:
            (project / 'project.godot').write_text(config.replace(str(project / 'saves'), str(project / 'saves' / script)))
            command = [args.godot] + (['--rendering-method', 'gl_compatibility'] if args.render else ['--headless']) + ['--path', str(project), '-s', 'res://scripts/dev/' + script]
            try:
                result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=100)
                output = result.stdout
                if script == 'SmokeUpgrade.gd' and result.returncode == 0:
                    reopened = subprocess.run(command + ['--', '--verify-reopen'], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30)
                    output += '\n--- Fresh-process save reload ---\n' + reopened.stdout
                    if reopened.returncode:
                        result = reopened
                ok = result.returncode == 0 and not re.search(r'(SCRIPT ERROR:|(?:^|\n)ERROR:)', output)
            except subprocess.TimeoutExpired as exc:
                output = (exc.stdout or b'').decode() if isinstance(exc.stdout, bytes) else (exc.stdout or '')
                output += '\nTIMEOUT after 100 seconds\n'
                ok = False
            (args.logs / (script + '.log')).write_text(output)
            print(('PASS ' if ok else 'FAIL ') + script, flush=True)
            if not ok:
                failures.append(script)
                print(output[-2500:], flush=True)
    return bool(failures)

if __name__ == '__main__':
    raise SystemExit(main())
