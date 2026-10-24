"""Bounded command execution that also stops child processes on timeout/interrupt."""
import os
import signal
import subprocess


def _descendants(pid):
    # Nested runners can start their own session, outside the parent's group.
    try:
        rows = subprocess.run(['ps', '-axo', 'pid=,ppid='], capture_output=True,
                              text=True, timeout=3, check=True).stdout.splitlines()
        pairs = [tuple(map(int, row.split())) for row in rows if row.strip()]
    except (OSError, ValueError, subprocess.SubprocessError):
        return []
    found, frontier = [], [pid]
    while frontier:
        frontier = [child for child, parent in pairs if parent in frontier]
        found.extend(frontier)
    return found


def run_process(command, *, timeout=None, capture_output=False, **kwargs):
    if capture_output:
        kwargs.update(stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    with subprocess.Popen(command, start_new_session=os.name != 'nt', **kwargs) as process:
        try:
            stdout, stderr = process.communicate(timeout=timeout)
        except BaseException:
            if os.name == 'nt':
                subprocess.run(['taskkill', '/F', '/T', '/PID', str(process.pid)],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            else:
                for child in reversed(_descendants(process.pid)):
                    try:
                        os.kill(child, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            process.kill()
            process.communicate()
            raise
        return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)
