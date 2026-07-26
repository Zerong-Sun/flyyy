#!/usr/bin/env bash
# Launch Chrome with remote debugging so chatgpt_gen_art.py can attach.
#
# Usage:
#   ./launch_chrome_debug.sh              # separate profile (safe; login once)
#   ./launch_chrome_debug.sh 9222
#   USE_DEFAULT_PROFILE=1 ./launch_chrome_debug.sh
#     → uses your normal Chrome profile (must fully Quit Chrome first)
set -euo pipefail

PORT="${1:-9222}"
CHROME_BIN="${CHROME_BIN:-}"

if [[ -z "$CHROME_BIN" ]]; then
  if [[ -x "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ]]; then
    CHROME_BIN="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  elif [[ -x "/Applications/Chromium.app/Contents/MacOS/Chromium" ]]; then
    CHROME_BIN="/Applications/Chromium.app/Contents/MacOS/Chromium"
  elif command -v google-chrome >/dev/null 2>&1; then
    CHROME_BIN="$(command -v google-chrome)"
  elif command -v chromium >/dev/null 2>&1; then
    CHROME_BIN="$(command -v chromium)"
  else
    echo "Chrome not found. Set CHROME_BIN to your browser binary." >&2
    exit 1
  fi
fi

if curl -sf "http://127.0.0.1:${PORT}/json/version" >/dev/null 2>&1; then
  echo "Already listening on :${PORT}"
  curl -s "http://127.0.0.1:${PORT}/json/version" | head -c 400
  echo
  exit 0
fi

ARGS=(
  --remote-debugging-port="$PORT"
  --no-first-run
  --no-default-browser-check
  "https://chatgpt.com/"
)

if [[ "${USE_DEFAULT_PROFILE:-0}" == "1" ]]; then
  echo "USE_DEFAULT_PROFILE=1 — using your normal Chrome profile."
  echo "If Chrome is already running WITHOUT debugging, Quit it first (Cmd+Q)."
else
  PROFILE_DIR="${CHROME_DEBUG_PROFILE:-$HOME/.cache/art-gen-chrome-debug}"
  mkdir -p "$PROFILE_DIR"
  ARGS=(--user-data-dir="$PROFILE_DIR" "${ARGS[@]}")
  echo "Profile: $PROFILE_DIR"
fi

echo "Starting Chrome debug on :${PORT}"
echo "Log in to https://chatgpt.com/ in this window, then run chatgpt_gen_art.py"

exec "$CHROME_BIN" "${ARGS[@]}"