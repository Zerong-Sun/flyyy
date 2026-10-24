from pathlib import Path
import json
import sys

import pytest

from tools.test_godot import isolated_config, log_passed, prepare_project
from tools.check_quality import run_stages, REQUIRED_STAGES


@pytest.mark.parametrize('code,output,expected', [
    (0, 'SMOKE_PERF_OK\n', True),
    (1, 'everything printed OK', False),
    (0, 'SCRIPT ERROR: invalid call\n', False),
    (0, 'boot\nERROR: missing asset\n', False),
    (0, 'SMOKE_PERF_FAIL\n', False),
    (0, 'VERIFY_MARKET_FAIL\n', False),
    (0, 'SKIP: no airports loaded\n', False),
    (0, 'WARNING: expected backup recovery\n', True),
    (0, '\x1b[31mERROR:\x1b[0m missing asset\n', False),
    (0, '   ERROR: missing asset\n', False),
    (0, '\x1b[33mSKIP:\x1b[0m missing world\n', False),
])
def test_engine_log_errors_cannot_pass_on_exit_zero(code, output, expected):
    assert log_passed(code, output) is expected


def test_isolated_save_path_replaces_only_the_configured_directory():
    original = '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="WanliTrader"\n'
    result = isolated_config(original, Path('/tmp/test-saves'))
    assert 'config/custom_user_dir_name="/tmp/test-saves"' in result
    assert 'WanliTrader' not in result


@pytest.mark.parametrize('config', [
    '[application]\n',
    'config/custom_user_dir_name="WanliTrader"\nconfig/use_custom_user_dir=false\n',
    'config/use_custom_user_dir=true\nconfig/custom_user_dir_name="one"\nconfig/custom_user_dir_name="two"\n',
    '; config/use_custom_user_dir=true\nconfig/custom_user_dir_name="WanliTrader"\n',
])
def test_isolation_fails_closed_when_project_configuration_changes(config):
    with pytest.raises(ValueError, match='isolate'):
        isolated_config(config, Path('/tmp/test-saves'))


@pytest.mark.parametrize('fresh', [False, True])
def test_import_cache_is_private(tmp_path, fresh):
    source, project = tmp_path / 'game', tmp_path / 'isolated'
    (source / '.godot').mkdir(parents=True)
    project.mkdir()
    (source / '.godot/cache').write_text('original')
    prepare_project(source, project, fresh)
    if fresh:
        assert not (project / '.godot').exists()
    else:
        (project / '.godot/cache').write_text('changed')
        assert (source / '.godot/cache').read_text() == 'original'


def test_partial_quality_run_cannot_reuse_previous_success(tmp_path):
    summary = tmp_path / 'summary.json'
    summary.write_text('[{"stage":"godot","exit_code":0}]')
    assert run_stages([('mobile', [sys.executable, '-c', 'print("ok")'], tmp_path, 5)], tmp_path) == 0
    report = json.loads(summary.read_text())
    assert report['status'] == 'partial'
    assert [row['stage'] for row in report['results']] == ['mobile']


def test_quality_full_success_and_failure_are_distinct(tmp_path):
    stages = [(name, [sys.executable, '-c', 'print("ok")'], tmp_path, 5) for name in REQUIRED_STAGES]
    assert run_stages(stages, tmp_path) == 0
    assert json.loads((tmp_path / 'summary.json').read_text())['status'] == 'passed'
    stages[1] = ('mobile', [sys.executable, '-c', 'raise SystemExit(3)'], tmp_path, 5)
    assert run_stages(stages, tmp_path) == 1
    report = json.loads((tmp_path / 'summary.json').read_text())
    assert report['status'] == 'failed'
    assert report['results'][1]['exit_code'] == 3


def test_interrupted_quality_run_does_not_leave_old_green_summary(tmp_path, monkeypatch):
    import tools.check_quality as quality
    (tmp_path / 'summary.json').write_text('{"status":"passed"}')
    def interrupt(*args, **kwargs):
        raise KeyboardInterrupt
    monkeypatch.setattr(quality, 'run_process', interrupt)
    with pytest.raises(KeyboardInterrupt):
        run_stages([('godot', ['unused'], tmp_path, 5)], tmp_path)
    report = json.loads((tmp_path / 'summary.json').read_text())
    assert report['status'] == 'running'
    assert report['results'][0]['exit_code'] is None


def test_timeout_stops_grandchild_work(tmp_path):
    import subprocess
    import time
    from tools.process_utils import run_process
    marker = tmp_path / 'orphan-finished'
    child = f'import time; from pathlib import Path; time.sleep(0.8); Path({str(marker)!r}).touch()'
    parent = f'import subprocess, sys, time; subprocess.Popen([sys.executable, "-c", {child!r}], start_new_session=True); time.sleep(10)'
    with pytest.raises(subprocess.TimeoutExpired):
        run_process([sys.executable, '-c', parent], timeout=0.3)
    time.sleep(0.8)
    assert not marker.exists(), 'a timed-out quality run must not leave Godot/ETL descendants running'
