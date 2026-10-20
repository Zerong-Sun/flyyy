#!/usr/bin/env python3
"""Build portable desktop archives from the checked Godot export presets.

Requires Godot 4.7.1 export templates and the generated game/data JSON files.
Run from anywhere: python3 tools/build_desktop_release.py v0.4.0
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import zipfile


ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / "game"


def require_data() -> None:
    paths = [
        GAME / "data/world.json",
        GAME / "data/achievements.json",
        GAME / "data/product_market_tags.json",
        GAME / "data/flights/_manifest.json",
    ]
    missing = [str(path.relative_to(ROOT)) for path in paths if not path.is_file()]
    if missing:
        raise RuntimeError("Missing generated data: " + ", ".join(missing))
    world = json.loads((GAME / "data/world.json").read_text())
    manifest = json.loads((GAME / "data/flights/_manifest.json").read_text())
    if len(world.get("airports", [])) < 500 or len(manifest) < 500:
        raise RuntimeError("Generated world or flight manifest is incomplete")
    for directory in ("flights", "markets", "transfers"):
        count = len(list((GAME / "data" / directory).glob("*.json")))
        if count < 500:
            raise RuntimeError(f"Incomplete generated data: game/data/{directory} ({count} files)")


def archive(source: Path, destination: Path) -> None:
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as output:
        for path in sorted(source.rglob("*")):
            if path.is_dir():
                continue
            output.write(path, path.relative_to(source.parent).as_posix())


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def smoke_pack(godot: str, pack: Path) -> None:
    result = subprocess.run(
        [godot, "--headless", "--main-pack", str(pack), "--quit-after", "30"],
        check=True,
        capture_output=True,
        text=True,
    )
    log = result.stdout + result.stderr
    if (
        "DataService loaded: 500 airports" not in log
        or not re.search(r"I18nService loaded: zh=[1-9]\d* en=[1-9]\d* ui keys", log)
        or "missing res://" in log
    ):
        raise RuntimeError("Exported pack failed the data, language, or audio manifest startup check:\n" + log)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", help="release tag, for example v0.4.0")
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN") or shutil.which("godot"))
    parser.add_argument("--output", type=Path, default=ROOT / "dist")
    args = parser.parse_args()
    if not args.godot:
        parser.error("Godot executable not found; pass --godot or set GODOT_BIN")
    if not args.version.startswith("v") or "/" in args.version:
        parser.error("version must be a safe tag beginning with v")
    require_data()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    build = output / f"WanliTrader-{args.version}"
    build.mkdir(exist_ok=True)
    targets = (
        ("Windows Desktop", "windows-x64", build / "windows" / "WanliTrader.exe"),
        ("macOS", "macos-universal", build / "macos" / "WanliTrader.app"),
    )
    archives = []
    for preset, platform, target in targets:
        target.parent.mkdir(exist_ok=True)
        subprocess.run(
            [args.godot, "--headless", "--path", str(GAME), "--export-release", preset, str(target)],
            check=True,
        )
        if platform == "windows-x64":
            if not target.is_file() or not target.with_suffix(".pck").is_file():
                raise RuntimeError("Windows export is missing its executable or PCK")
            smoke_pack(args.godot, target.with_suffix(".pck"))
            source = target.parent
        else:
            if not target.is_dir() or not (target / "Contents/MacOS").is_dir():
                raise RuntimeError("macOS export is missing its app bundle")
            source = target
        artifact = output / f"WanliTrader-{args.version}-{platform}.zip"
        archive(source, artifact)
        archives.append(artifact)
        print(f"Built {artifact} ({artifact.stat().st_size:,} bytes)", flush=True)
    checksums = output / f"WanliTrader-{args.version}-SHA256SUMS.txt"
    checksums.write_text("".join(f"{sha256(path)}  {path.name}\n" for path in archives))
    print(f"Checksums: {checksums}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, subprocess.CalledProcessError) as exc:
        print(f"Release build failed: {exc}", file=sys.stderr)
        sys.exit(1)
