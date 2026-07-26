#!/usr/bin/env bash
# One-time setup for art-gen-kit (run from this directory)
set -euo pipefail
cd "$(dirname "$0")"
python3 -m venv .venv
.venv/bin/pip install -U pip
.venv/bin/pip install -r requirements-art-gen.txt
.venv/bin/playwright install chromium
echo "Done. Next: ./launch_chrome_debug.sh && .venv/bin/python orchestrate_req.py --dry-run"
