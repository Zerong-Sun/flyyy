#!/usr/bin/env python3
"""Upload a desktop release in small parts when large uploads stall.

The manifest is uploaded last, so CI never assembles an incomplete release.
"""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[1]
TAG = "v0.4.0"
CHUNK_SIZE = 8 * 1024 * 1024
SOURCES = {
    "windows": ROOT / "dist/WanliTrader-v0.4.0-windows-x64.zip",
    "macos_shell": ROOT / "dist/WanliTrader-v0.4.0-macos-shell.zip",
}


def split_file(source: Path, target_dir: Path) -> tuple[list[Path], str]:
    digest = hashlib.sha256()
    parts: list[Path] = []
    with source.open("rb") as stream:
        for index, block in enumerate(iter(lambda: stream.read(CHUNK_SIZE), b"")):
            digest.update(block)
            part = target_dir / f"{source.name}.part{index:03d}"
            part.write_bytes(block)
            parts.append(part)
    return parts, digest.hexdigest()


def upload(path: Path) -> str:
    command = ["gh", "release", "upload", TAG, str(path), "--clobber"]
    for attempt in range(1, 5):
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode == 0:
            return path.name
        if attempt == 4:
            raise RuntimeError(f"{path.name}: {result.stderr.strip()}")
        time.sleep(5 * attempt)
    raise AssertionError("unreachable")


def main() -> None:
    chunk_dir = ROOT / "dist/release-chunks"
    chunk_dir.mkdir(parents=True, exist_ok=True)
    manifest = {}
    all_parts: list[Path] = []
    for key, source in SOURCES.items():
        if not source.is_file():
            raise RuntimeError(f"Missing release source: {source}")
        parts, sha = split_file(source, chunk_dir)
        manifest[key] = {"name": source.name, "sha256": sha, "parts": [p.name for p in parts]}
        all_parts.extend(parts)
        print(f"{key}: {len(parts)} parts, SHA-256 {sha}", flush=True)
    with ThreadPoolExecutor(max_workers=8) as pool:
        futures = [pool.submit(upload, part) for part in all_parts]
        for count, future in enumerate(as_completed(futures), 1):
            print(f"Uploaded {count}/{len(all_parts)}: {future.result()}", flush=True)
    manifest_path = chunk_dir / f"WanliTrader-{TAG}-chunks.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print("Uploaded manifest:", upload(manifest_path), flush=True)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError) as exc:
        print(f"Chunk upload failed: {exc}", file=sys.stderr)
        sys.exit(1)
