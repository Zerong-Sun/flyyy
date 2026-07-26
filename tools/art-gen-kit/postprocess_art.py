#!/usr/bin/env python3
"""Post-process generated art: dealpha → strip_checker → audit (optional).

Usage:
  .venv/bin/python postprocess_art.py
  .venv/bin/python postprocess_art.py icon-*.webp scene-*.webp
"""

from __future__ import annotations

import glob
import subprocess
import sys
from pathlib import Path

from kit_paths import ART_DIR, KIT_DIR, TOOLS_DIR

VENV_PY = KIT_DIR / ".venv" / "bin" / "python"


def resolve_targets(patterns: list[str]) -> list[Path]:
    if not patterns:
        return sorted(ART_DIR.glob("*.webp"))
    out: list[Path] = []
    for pat in patterns:
        p = Path(pat)
        if p.is_absolute():
            out.extend(sorted(glob.glob(str(p))))
        else:
            out.extend(sorted(ART_DIR.glob(pat)))
            out.extend(sorted(ART_DIR.glob(p.name)))
    seen: set[str] = set()
    uniq: list[Path] = []
    for f in out:
        fp = str(Path(f).resolve())
        if fp in seen:
            continue
        seen.add(fp)
        uniq.append(Path(fp))
    return uniq


def run_dealpha() -> None:
    script = KIT_DIR / "dealpha.py"
    if not script.exists():
        return
    py = str(VENV_PY) if VENV_PY.exists() else sys.executable
    subprocess.run([py, str(script), "--apply"], cwd=KIT_DIR, check=False)


def main() -> int:
    targets = resolve_targets(sys.argv[1:])
    if not targets:
        print("no target files", flush=True)
        return 1

    print(f"postprocess {len(targets)} files…", flush=True)
    run_dealpha()

    if not TOOLS_DIR or not (TOOLS_DIR / "audit.py").exists():
        print(
            "skip audit/strip_checker (set ART_GEN_TOOLS_DIR to folder containing audit.py)",
            flush=True,
        )
        for path in targets:
            print(f"  {path.name:40s} dealpha-only", flush=True)
        return 0

    sys.path.insert(0, str(TOOLS_DIR))
    import audit as au  # noqa: E402
    import strip_checker as sc  # noqa: E402

    checker = broken = ok = 0
    for path in targets:
        before, killed = sc.process(str(path), write=True)
        state, note, share = au.classify(str(path))
        if state == "CHECKER":
            _, killed2 = sc.process(str(path), write=True)
            state, note, share = au.classify(str(path))
            killed += killed2
        icon = {"OK": "OK", "CHECKER": "CHECKER", "BROKEN": "BROKEN"}.get(state, state)
        print(
            f"  {path.name:40s} audit={icon:8s} strip_px={killed:6d} {note}",
            flush=True,
        )
        if state == "OK":
            ok += 1
        elif state == "CHECKER":
            checker += 1
        else:
            broken += 1

    print(f"summary OK={ok} CHECKER={checker} BROKEN={broken} / {len(targets)}", flush=True)
    return 1 if checker or broken else 0


if __name__ == "__main__":
    raise SystemExit(main())
