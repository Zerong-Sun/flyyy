#!/usr/bin/env python3
"""Run multiple prompt files in parallel — one ChatGPT tab per file.

Usage:
  .venv/bin/python run_parallel.py ART_PROMPTS_A.md ART_PROMPTS_B.md
  .venv/bin/python run_parallel.py --max-tabs 2 prompts1.md prompts2.md

Each subprocess calls orchestrate_req.py with --max-windows 1.
Total concurrent tabs = number of prompt files (keep ≤ 2–3 to avoid rate limits).
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path

KIT = Path(__file__).resolve().parent
VENV = KIT / ".venv" / "bin" / "python"

ORCH_ARGS = [
    "--max-windows",
    "1",
    "--poll-sec",
    "600",
    "--skip-existing",
    "--wait-login-ms",
    "600000",
    "--rate-limit-ms",
    "600000",
]


def pending(prompts_file: str) -> int:
    r = subprocess.run(
        [str(VENV), "orchestrate_req.py", "--prompts-file", prompts_file, "--dry-run", "--skip-existing"],
        cwd=KIT,
        capture_output=True,
        text=True,
    )
    out = (r.stdout or "") + (r.stderr or "")
    if "Queue: 0" in out:
        return 0
    return sum(1 for line in out.splitlines() if line.startswith("  ") and "batches" in line)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("prompts_files", nargs="+", help="ART_PROMPTS*.md filenames")
    ap.add_argument("--postprocess", action="store_true", default=True)
    ap.add_argument("--no-postprocess", action="store_false", dest="postprocess")
    args = ap.parse_args()

    files = [pf for pf in args.prompts_files if pending(pf) > 0]
    if not files:
        print("Nothing pending.", flush=True)
        return 0

    print(f"Parallel: {len(files)} orchestrator(s)", flush=True)
    procs: list[tuple[str, subprocess.Popen]] = []
    for pf in files:
        print(f"  launch {pf}", flush=True)
        p = subprocess.Popen(
            [str(VENV), "orchestrate_req.py", "--prompts-file", pf, *ORCH_ARGS],
            cwd=KIT,
        )
        procs.append((pf, p))
        time.sleep(3)

    rc = 0
    for pf, p in procs:
        code = p.wait()
        print(f"  {pf} exit={code}", flush=True)
        if code != 0:
            rc = code

    if args.postprocess:
        subprocess.run([str(VENV), "postprocess_art.py"], cwd=KIT)
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
