#!/usr/bin/env python3
"""
Auto-recovery orchestrator wrapper.
- Clicks stop buttons before every poll
- Clears chat URL after 2 consecutive failures (forces fresh chat)
- 2-min poll cycle
"""
import asyncio
import subprocess
import sys
import time
from pathlib import Path

ORCH = Path(__file__).parent / ".venv/bin/python"
UNSTICK = Path(__file__).parent / "unstick_stop3.py"
ORCH_SCRIPT = Path(__file__).parent / "orchestrate_req.py"
STATUS = Path("/tmp/orchestrate_req_status.json")
PORT = 9222

FAIL_LOG = Path("/tmp/flyyy_fail_count.txt")

def fail_count() -> int:
    try:
        return int(FAIL_LOG.read_text().strip())
    except:
        return 0

def set_fail(v: int):
    FAIL_LOG.write_text(str(v))

async def run():
    proc = None
    last_fail = False
    while True:
        # Unstick before polling
        subprocess.run(
            [str(UNSTICK), str(PORT)],
            capture_output=True, timeout=30, cwd=UNSTICK.parent
        )

        if proc and proc.returncode is not None:
            # Orchestrator died
            print(f"[auto] orchestrator exited rc={proc.returncode}", flush=True)
            # Check if all done
            if proc.returncode == 0:
                print("[auto] ALL DONE!", flush=True)
                break
            proc = None

        if proc is None:
            print("[auto] starting orchestrator...", flush=True)
            # Clear saved chats on every restart for truly fresh context
            STATUS.unlink(missing_ok=True)
            proc = await asyncio.create_subprocess_exec(
                str(ORCH), str(ORCH_SCRIPT),
                "--port", str(PORT),
                "--prompts-file", "ART_PROMPTS_REQ.md",
                "--max-windows", "2",
                "--poll-sec", "120",
                "--no-skip-existing",
                "--rate-limit-ms", "120000",
                "--wait-login-ms", "60000",
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                cwd=ORCH_SCRIPT.parent,
                env={"PATH": "/usr/bin:/bin:/opt/homebrew/bin", "HOME": str(Path.home())}
            )

        # Read orchestrator output for 4 mins then check
        deadline = time.time() + 240
        any_output = False
        while time.time() < deadline:
            line = await proc.stdout.readline()
            if not line:
                break
            text = line.decode(errors="replace").rstrip()
            print(text, flush=True)
            any_output = True
            if "All REQ windows done" in text:
                print("[auto] ALL DONE!", flush=True)
                await proc.wait()
                return

        if not any_output and proc.returncode is not None:
            print(f"[auto] orchestrator died rc={proc.returncode}", flush=True)
            proc = None
            if fail_count() > 3:
                # Too many failures, try clearing chats
                print("[auto] clearing stale chats...", flush=True)
                subprocess.run([str(UNSTICK), str(PORT)], capture_output=True, timeout=30)
                set_fail(0)
            else:
                set_fail(fail_count() + 1)
            await asyncio.sleep(5)

    if proc:
        proc.terminate()

asyncio.run(run())
