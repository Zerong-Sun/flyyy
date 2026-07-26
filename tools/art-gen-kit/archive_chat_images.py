#!/usr/bin/env python3
"""Archive ALL generated images from ChatGPT chats into assets/art/_archive/chats/.

Does not overwrite production filenames — dumps every variant for safekeeping.
Respects generation pause: never submits prompts.

Usage:
  .venv/bin/python archive_chat_images.py
  .venv/bin/python archive_chat_images.py --url https://chatgpt.com/c/...
"""

from __future__ import annotations

import argparse
import asyncio
import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path

from batch_art_utils import ART_DIR
from chatgpt_gen_art import connect_browser, fetch_image_bytes
from resume_dual_decks import ensure_chat

ARCHIVE = ART_DIR / "_archive" / "chats"
CHAT_ID_RE = re.compile(r"/c/([A-Za-z0-9:-]+)")


def chat_id(url: str) -> str:
    m = CHAT_ID_RE.search(url or "")
    return (m.group(1) if m else "unknown").replace(":", "_")


async def collect_srcs(page) -> list[str]:
    return await page.evaluate(
        """() => {
          const main = document.querySelector('main') || document.body;
          const out = [], seen = new Set();
          const isGen = (src) => src && (
            src.includes('estuary/content') || src.includes('oaiusercontent.com') ||
            src.includes('oaidalle') || src.includes('/backend-api/') || src.startsWith('blob:'));
          for (const img of main.querySelectorAll('img')) {
            const src = img.currentSrc || img.src || '';
            if (!src || seen.has(src) || src.startsWith('data:image/svg')) continue;
            if (src.includes('avatar') || src.includes('/icon')) continue;
            const w = Math.max(img.naturalWidth || 0, img.getBoundingClientRect().width || 0);
            const h = Math.max(img.naturalHeight || 0, img.getBoundingClientRect().height || 0);
            if (!isGen(src) && (w < 120 || h < 120)) continue;
            if (w < 80 || h < 80) continue;
            seen.add(src);
            out.push(src);
          }
          return out;
        }"""
    )


async def sidebar_chat_urls(page) -> list[str]:
    await page.goto("https://chatgpt.com/", wait_until="domcontentloaded", timeout=90_000)
    await page.wait_for_timeout(2500)
    urls = await page.evaluate(
        """() => [...document.querySelectorAll('a[href*="/c/"]')]
          .map(a => a.href.split('?')[0])
          .filter((v, i, a) => a.indexOf(v) === i)"""
    )
    return [u for u in (urls or []) if "/c/WEB:" not in u]


async def open_tab_urls(browser) -> list[str]:
    out: list[str] = []
    for ctx in browser.contexts:
        for p in ctx.pages:
            u = (p.url or "").split("?")[0]
            if "chatgpt.com/c/" in u and "/c/WEB:" not in u:
                out.append(u)
    return list(dict.fromkeys(out))


async def archive_chat(page, url: str, known_hashes: dict[str, str]) -> dict:
    cid = chat_id(url)
    out_dir = ARCHIVE / cid
    out_dir.mkdir(parents=True, exist_ok=True)
    await ensure_chat(page, url)
    await page.wait_for_timeout(2000)
    title = await page.title()
    users = await page.evaluate(
        """() => [...document.querySelectorAll('[data-message-author-role="user"]')]
          .map(m => (m.innerText || '').slice(0, 240))"""
    )
    srcs = await collect_srcs(page)
    saved = 0
    skipped = 0
    files: list[str] = []
    for i, src in enumerate(srcs, 1):
        try:
            raw = await fetch_image_bytes(page, src)
        except Exception as e:
            print(f"  [{cid}] img{i} fetch fail: {e}", flush=True)
            continue
        dig = hashlib.md5(raw).hexdigest()
        # Prefer lossless-ish webp of original bytes via PIL path
        try:
            from io import BytesIO

            from PIL import Image

            im = Image.open(BytesIO(raw)).convert("RGBA")
            # keep original pixel size; store as webp
            buf = BytesIO()
            im.save(buf, format="WEBP", quality=95, method=6)
            data = buf.getvalue()
            w, h = im.size
        except Exception:
            data = raw
            w = h = 0
        name = f"img-{i:02d}-{dig[:10]}.webp"
        path = out_dir / name
        if path.exists() and path.stat().st_size > 0:
            skipped += 1
            files.append(name)
            continue
        # also skip if identical content already archived elsewhere
        other = known_hashes.get(dig)
        if other and other != str(path.relative_to(ARCHIVE)):
            # write tiny pointer note instead of duplicating bytes
            (out_dir / f"img-{i:02d}-{dig[:10]}.dup.txt").write_text(
                f"duplicate of {other}\n", encoding="utf-8"
            )
            skipped += 1
            files.append(name + " (dup)")
            continue
        path.write_bytes(data)
        known_hashes[dig] = str(path.relative_to(ARCHIVE))
        saved += 1
        files.append(name)
        print(f"  [{cid}] saved {name} ({w}x{h}, {len(data)}B)", flush=True)

    meta = {
        "url": url.split("?")[0],
        "chat_id": cid,
        "title": title,
        "archived_at": datetime.now(timezone.utc).isoformat(),
        "user_prompts": users or [],
        "image_count": len(srcs),
        "saved": saved,
        "skipped": skipped,
        "files": files,
    }
    (out_dir / "meta.json").write_text(json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")
    print(
        f"[{cid}] title={title!r} imgs={len(srcs)} saved={saved} skipped={skipped}",
        flush=True,
    )
    return meta


async def run(urls: list[str], also_sidebar: bool) -> int:
    ARCHIVE.mkdir(parents=True, exist_ok=True)
    browser = await connect_browser(9222)
    known: dict[str, str] = {}
    # seed known from existing archive
    for p in ARCHIVE.rglob("*.webp"):
        try:
            known[hashlib.md5(p.read_bytes()).hexdigest()] = str(p.relative_to(ARCHIVE))
        except Exception:
            pass

    try:
        page = await browser.contexts[0].new_page()
        discovered = list(urls)
        discovered.extend(await open_tab_urls(browser))
        if also_sidebar:
            try:
                discovered.extend(await sidebar_chat_urls(page))
            except Exception as e:
                print(f"sidebar scan failed: {e}", flush=True)
        # unique, stable /c/ only
        clean: list[str] = []
        seen: set[str] = set()
        for u in discovered:
            u = (u or "").split("?")[0]
            if "/c/" not in u or "/c/WEB:" in u:
                continue
            if u in seen:
                continue
            seen.add(u)
            clean.append(u)
        print(f"archiving {len(clean)} chats → {ARCHIVE}", flush=True)
        results = []
        for u in clean:
            try:
                results.append(await archive_chat(page, u, known))
            except Exception as e:
                print(f"FAIL {u}: {e}", flush=True)
                results.append({"url": u, "error": str(e)})
        summary = {
            "archived_at": datetime.now(timezone.utc).isoformat(),
            "chats": len(results),
            "images_saved": sum(r.get("saved", 0) for r in results if isinstance(r, dict)),
            "results": results,
        }
        (ARCHIVE / "index.json").write_text(
            json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8"
        )
        print(
            f"DONE chats={summary['chats']} newly_saved={summary['images_saved']}",
            flush=True,
        )
        await page.close()
        return 0
    finally:
        pw = getattr(browser, "_fq_pw", None)
        try:
            await browser.close()
        except Exception:
            pass
        if pw:
            await pw.stop()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", action="append", default=[])
    ap.add_argument("--no-sidebar", action="store_true")
    args = ap.parse_args()
    seeds = list(args.url)
    if not seeds:
        seeds = [
            "https://chatgpt.com/c/6a6238a3-2538-83e8-9744-d2fdde3cac40",  # Sail
            "https://chatgpt.com/c/6a6238af-6488-83ee-af44-a0a60613405b",  # Scribe
            "https://chatgpt.com/c/6a623da7-dd7c-83ee-aba9-e340ff65bc53",  # Monk
            "https://chatgpt.com/c/6a62427f-1a18-83e8-919d-1055c1f769bb",  # Seer
            "https://chatgpt.com/c/6a62535a-7d60-83ee-aa91-a78fb9a96e5e",  # Region
            "https://chatgpt.com/c/6a62b97d-0590-83ee-80b4-d98d764da598",  # Dock
            "https://chatgpt.com/c/6a6224f4-e1e8-83ee-a780-4f70dcc16754",  # Guide
            "https://chatgpt.com/c/6a6224f5-8c64-83ee-afbb-507212b2d791",  # Lang
            "https://chatgpt.com/c/6a622b3b-fb0c-83ee-9aae-bc60ee7594b7",  # Porter
            "https://chatgpt.com/c/6a622280-d640-83ee-b73b-c2cf1c9608cb",  # Rose
            "https://chatgpt.com/c/6a622281-a518-83ee-a62a-f9acc154807d",  # Cargo
        ]
    raise SystemExit(asyncio.run(run(seeds, also_sidebar=not args.no_sidebar)))


if __name__ == "__main__":
    main()
