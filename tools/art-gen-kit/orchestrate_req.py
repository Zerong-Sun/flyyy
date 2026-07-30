#!/usr/bin/env python3
"""
Orchestrate ART_REQUIREMENTS P0+P1 generation.

  - max 2 ChatGPT tabs
  - one batch submit per tab at a time
  - poll / harvest every --poll-sec (default 600 = 10 min)

Priority windows: Desk → Tex → City → Mtn → Wind → Route

Usage:
  .venv/bin/python orchestrate_req.py --dry-run
  .venv/bin/python orchestrate_req.py --max-windows 2 --poll-sec 600 --skip-existing
"""

from __future__ import annotations

import argparse
import asyncio
import hashlib
import json
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

from batch_art_utils import ART_DIR, BatchJob, parse_batch_prompts_md
from kit_paths import PROMPTS_DIR
from chatgpt_gen_art import (
    build_batch_message,
    connect_browser,
    ensure_logged_in,
    get_chatgpt_page,
    wait_out_rate_limit,
)
from resume_dual_decks import dismiss_rate_limit, ensure_chat, generation_busy
from submit_map_windows import (
    missing_files,
    save_batch,
)
from chatgpt_gen_art import (
    collect_image_srcs,
    submit_prompt,
)

DEFAULT_PROMPTS_FILE = "ART_PROMPTS_REQ.md"
DEFAULT_WINDOW_ORDER = ["Desk", "Tex", "City", "Mtn", "Wind", "Route"]
P2_WINDOW_ORDER = ["CitiesA", "CitiesB", "BandA", "BandB", "BandC", "UI"]
P3_WINDOW_ORDER = ["Lot", "Rank"]
P45_WINDOW_ORDER = [
    "Rose",
    "Cargo",
    "NpcGuide",
    "NpcLang",
    "NpcPorter",
    "NpcGuard",
    "NpcHeal",
    "NpcSail",
    "NpcScribe",
    "NpcMonk",
    "NpcSeer",
]
REMAIN_WINDOW_ORDER = [
    "Region",
    "VenueDock",
    "VenueOfficial",
    "VenueHeal",
    "VenueScribe",
]
EXPLORE_WINDOW_ORDER = [
    "Temple",
    "Market",
    "Inn",
]
P0_WINDOW_ORDER = [
    "BookA",
    "BookB",
    "Desk",
    "LoadA",
    "LoadB",
    "LoadC",
    "FateUI",
    "Culture",
    "FaithA",
    "FaithB",
]
P1_WINDOW_ORDER = [
    "CityA",
    "CityB",
    "CityC",
    "SiteA",
    "SiteB",
    "SiteC",
    "RetainerGuide",
    "RetainerLang",
    "RetainerPorter",
    "RetainerGuard",
    "RetainerHeal",
    "RetainerSail",
    "RetainerScribe",
    "RetainerMonk",
    "RetainerSeer",
    "Contract",
]

# --- Project global style (Airborne Trader) ---
# Each batch in ART_PROMPTS_REQ.md carries its own complete style spec.
# No global style is injected — the per-batch prompt is used as-is via build_batch_message().



@dataclass
class Lane:
    name: str
    batches: list[BatchJob]
    prompts_stem: str = "ART_PROMPTS_REQ"
    page: object | None = None
    chat_url: str = ""
    waiting: bool = False
    done: bool = False
    pending_batch: BatchJob | None = None
    baseline_srcs: set[str] = field(default_factory=set)
    submitted_at: float = 0.0


def load_pending(
    skip_existing: bool,
    prompts_file: str,
    window_order: list[str] | None = None,
    *,
    strict_windows: bool = False,
) -> list[Lane]:
    path = PROMPTS_DIR / prompts_file
    if not path.exists():
        path = ART_DIR / prompts_file
    if not path.exists():
        raise SystemExit(f"Missing {path}")
    stem = Path(prompts_file).stem
    jobs = parse_batch_prompts_md(path.read_text(encoding="utf-8"), source=path.name)
    by: dict[str, list[BatchJob]] = {}
    order_seen: list[str] = []
    for j in jobs:
        w = j.window or "X"
        if skip_existing and not missing_files(j):
            print(f"  skip existing: {j.name}", flush=True)
            continue
        if w not in by:
            order_seen.append(w)
        by.setdefault(w, []).append(j)
    if window_order is None:
        upper = prompts_file.upper()
        if "REMAIN" in upper:
            window_order = REMAIN_WINDOW_ORDER
        elif "EXPLORE" in upper:
            window_order = EXPLORE_WINDOW_ORDER
        elif "P4" in upper or "P5" in upper or "P4P5" in upper:
            window_order = P45_WINDOW_ORDER
        elif "P3" in upper:
            window_order = P3_WINDOW_ORDER
        elif "P2" in upper:
            window_order = P2_WINDOW_ORDER
        elif "P1" in upper:
            window_order = P1_WINDOW_ORDER
        elif "P0" in upper:
            window_order = P0_WINDOW_ORDER
        else:
            window_order = DEFAULT_WINDOW_ORDER
    lanes: list[Lane] = []
    used: set[str] = set()
    for w in window_order:
        if w not in by:
            continue
        lanes.append(
            Lane(name=w, batches=by[w], prompts_stem=stem)
        )
        used.add(w)
    if not strict_windows:
        for w in order_seen:
            if w in used:
                continue
            lanes.append(
                Lane(name=w, batches=by[w], prompts_stem=stem)
            )
    return lanes


def _page_closed(page) -> bool:
    if page is None:
        return True
    try:
        return bool(page.is_closed())
    except Exception:
        return True


async def capture_stable_chat_url(page, lane: Lane, wait_ms: int = 15_000) -> None:
    """Prefer stable /c/<uuid>; ChatGPT often shows temporary /c/WEB: first."""
    deadline = time.time() + wait_ms / 1000
    while time.time() < deadline:
        url = (page.url or "").split("?")[0]
        if "/c/" in url and "/c/WEB:" not in url:
            lane.chat_url = url
            return
        await page.wait_for_timeout(500)
    url = (page.url or "").split("?")[0]
    if "/c/" in url and "/c/WEB:" not in url:
        lane.chat_url = url


async def open_lane(browser, lane: Lane) -> None:
    ctx = browser.contexts[0]
    if lane.page and not _page_closed(lane.page):
        try:
            await lane.page.close()
        except Exception:
            pass
    page = await ctx.new_page()
    url = lane.chat_url if lane.chat_url else "https://chatgpt.com/"
    await ensure_chat(page, url)
    lane.page = page
    await capture_stable_chat_url(page, lane, wait_ms=8_000)
    print(f"  [{lane.name}] tab ready {lane.chat_url or page.url}", flush=True)


async def ensure_lane_page(browser, lane: Lane) -> bool:
    """Reopen tab if Chrome closed it mid-wait. Returns False if reopen failed."""
    if not _page_closed(lane.page):
        return True
    print(f"  [{lane.name}] page closed — reopening {lane.chat_url or 'new chat'}…", flush=True)
    try:
        await open_lane(browser, lane)
        return not _page_closed(lane.page)
    except Exception as e:
        print(f"  [{lane.name}] reopen failed: {e}", flush=True)
        return False


async def submit_lane(browser, lane: Lane, rate_limit_ms: int) -> bool:
    if not await ensure_lane_page(browser, lane):
        return False
    page = lane.page
    assert page is not None
    while lane.batches:
        batch = lane.batches[0]
        miss = missing_files(batch)
        if not miss:
            print(f"  [{lane.name}] skip existing {batch.name}", flush=True)
            lane.batches.pop(0)
            continue
        try:
            await wait_out_rate_limit(page, pause_ms=rate_limit_ms)
            message = build_batch_message(batch)
            lane.baseline_srcs = await collect_image_srcs(page)
            print(
                f"  [{lane.name}] SUBMIT {batch.name} "
                f"({len(miss)} missing / {len(batch.files)} files) …",
                flush=True,
            )
            await submit_prompt(page, message, new_chat=False)
        except Exception as e:
            print(f"  [{lane.name}] submit failed: {e}", flush=True)
            try:
                await dismiss_rate_limit(page)
            except Exception:
                pass
            if "closed" in str(e).lower() or "TargetClosed" in type(e).__name__:
                lane.page = None
            return False
        lane.waiting = True
        lane.pending_batch = batch
        lane.submitted_at = time.time()
        await capture_stable_chat_url(page, lane, wait_ms=20_000)
        return True
    lane.done = True
    return False


async def harvest_lane(browser, lane: Lane, known: dict, quality: int) -> bool:
    if not await ensure_lane_page(browser, lane):
        return False
    page = lane.page
    assert page is not None
    elapsed = int(time.time() - lane.submitted_at) if lane.submitted_at else 0
    try:
        busy = await generation_busy(page)
    except Exception as e:
        print(f"  [{lane.name}] busy-check failed: {e}", flush=True)
        if "closed" in str(e).lower() or "TargetClosed" in type(e).__name__:
            lane.page = None
        return False
    if busy:
        print(f"  [{lane.name}] still generating… ({elapsed}s)", flush=True)
        # Stop-button can stick; after 15 min force harvest/resubmit path
        if elapsed < 900:
            return False
        print(f"  [{lane.name}] busy stuck {elapsed}s — forcing harvest attempt", flush=True)
    else:
        try:
            if await dismiss_rate_limit(page):
                return False
        except Exception as e:
            print(f"  [{lane.name}] rate-limit check failed: {e}", flush=True)
            if "closed" in str(e).lower() or "TargetClosed" in type(e).__name__:
                lane.page = None
            return False
    batch = lane.pending_batch
    if not batch:
        # After reconnect without waiting state: try harvest current head if files missing
        if lane.batches and missing_files(lane.batches[0]) and lane.chat_url:
            batch = lane.batches[0]
            lane.pending_batch = batch
            if not lane.submitted_at:
                lane.submitted_at = time.time() - 120
            lane.waiting = True
            elapsed = int(time.time() - lane.submitted_at)
        else:
            lane.waiting = False
            return False
    try:
        saved = await save_batch(
            page,
            batch,
            lane.baseline_srcs,
            quality,
            known,
            prompts_stem=lane.prompts_stem,
        )
    except Exception as e:
        print(f"  [{lane.name}] harvest error ({elapsed}s): {e}", flush=True)
        if "closed" in str(e).lower() or "TargetClosed" in type(e).__name__:
            lane.page = None
        if elapsed > 900:
            print(f"  [{lane.name}] reset wait — will resubmit", flush=True)
            lane.waiting = False
            lane.pending_batch = None
        return False
    still = missing_files(batch)
    if still:
        print(
            f"  [{lane.name}] partial saved={saved}; still {len(still)} after {elapsed}s",
            flush=True,
        )
        if elapsed > 900:
            print(f"  [{lane.name}] reset wait — will resubmit", flush=True)
            lane.waiting = False
            lane.pending_batch = None
        return False
    print(f"  [{lane.name}] DONE {batch.name}", flush=True)
    if lane.batches and lane.batches[0] is batch:
        lane.batches.pop(0)
    lane.waiting = False
    lane.pending_batch = None
    if not lane.batches:
        lane.done = True
    return True


def summarize(lanes: list[Lane]) -> None:
    for lane in lanes:
        left = sum(len(missing_files(b)) for b in lane.batches)
        flag = "DONE" if lane.done else ("WAIT" if lane.waiting else "IDLE")
        print(f"  {lane.name:8s} {flag:4s} batches_left={len(lane.batches)} files_left~{left}")


STATUS_PATH = Path("/tmp/orchestrate_req_status.json")


def load_saved_chats() -> dict[str, str]:
    if not STATUS_PATH.exists():
        return {}
    try:
        data = json.loads(STATUS_PATH.read_text())
        chats = data.get("chats") or {}
        out: dict[str, str] = {}
        for k, v in chats.items():
            s = str(v)
            if s and "/c/" in s and "/c/WEB:" not in s:
                out[str(k)] = s
        return out
    except Exception:
        return {}


async def run(args: argparse.Namespace) -> int:
    lanes = load_pending(
        skip_existing=args.skip_existing,
        prompts_file=args.prompts_file,
        window_order=args.window_order,
        strict_windows=bool(args.window_order),
    )
    saved_chats = load_saved_chats()
    for lane in lanes:
        if lane.name in saved_chats and not lane.chat_url:
            lane.chat_url = saved_chats[lane.name]
            print(f"  resume chat [{lane.name}] {lane.chat_url}", flush=True)
    print(
        f"Prompts {args.prompts_file} · Queue: {len(lanes)} windows (max {args.max_windows})",
        flush=True,
    )
    for lane in lanes:
        n = sum(len(missing_files(b)) for b in lane.batches)
        print(f"  {lane.name}: {len(lane.batches)} batches, ~{n} files", flush=True)
    if args.dry_run:
        return 0
    if not lanes:
        print("Nothing pending.")
        return 0

    browser = await connect_browser(args.port)
    login = await get_chatgpt_page(browser)
    await ensure_logged_in(login, wait=True, wait_ms=args.wait_login_ms)
    await wait_out_rate_limit(login, pause_ms=args.rate_limit_ms)

    known: dict[str, str] = {}
    for p in ART_DIR.glob("*.webp"):
        try:
            known[hashlib.md5(p.read_bytes()).hexdigest()] = p.name
        except Exception:
            pass

    active: list[Lane] = []
    queue = list(lanes)
    round_i = 0
    try:
        while True:
            round_i += 1
            print(f"\n=== poll #{round_i} @ {time.strftime('%H:%M:%S')} ===", flush=True)

            # harvest waiting (or resume prior chats that still need files)
            for lane in list(active):
                if lane.waiting or (
                    lane.chat_url
                    and lane.batches
                    and missing_files(lane.batches[0])
                    and not lane.done
                ):
                    try:
                        await harvest_lane(browser, lane, known, args.quality)
                    except Exception as e:
                        print(f"  [{lane.name}] harvest crash: {e}", flush=True)
                        lane.page = None
                if lane.done:
                    print(f"  [{lane.name}] lane complete", flush=True)
                    active.remove(lane)

            # fill slots
            while len(active) < args.max_windows and queue:
                lane = queue.pop(0)
                opened = False
                for attempt in range(1, 4):
                    try:
                        await open_lane(browser, lane)
                        opened = True
                        break
                    except Exception as e:
                        print(
                            f"  [{lane.name}] open failed (try {attempt}/3): {e}",
                            flush=True,
                        )
                        lane.page = None
                        await asyncio.sleep(2)
                if not opened:
                    queue.insert(0, lane)
                    break
                # Prefer harvest-first if we already submitted this chat earlier
                if lane.chat_url and lane.batches and missing_files(lane.batches[0]):
                    lane.waiting = True
                    lane.pending_batch = lane.batches[0]
                    if not lane.submitted_at:
                        lane.submitted_at = time.time() - 300
                active.append(lane)

            # submit idle active lanes
            for lane in active:
                if not lane.waiting and not lane.done:
                    try:
                        await submit_lane(browser, lane, args.rate_limit_ms)
                    except Exception as e:
                        print(f"  [{lane.name}] submit crash: {e}", flush=True)
                        lane.page = None

            # Immediate harvest pass (resume chats may already be ready)
            for lane in list(active):
                if lane.waiting and not lane.done:
                    try:
                        await harvest_lane(browser, lane, known, args.quality)
                    except Exception as e:
                        print(f"  [{lane.name}] harvest crash: {e}", flush=True)
                        lane.page = None
                if lane.done and lane in active:
                    print(f"  [{lane.name}] lane complete", flush=True)
                    active.remove(lane)

            # drop completed again
            active = [l for l in active if not l.done]

            summarize(lanes)
            STATUS_PATH.write_text(
                json.dumps(
                    {
                        "round": round_i,
                        "active": [l.name for l in active],
                        "queue": [l.name for l in queue],
                        "done": [l.name for l in lanes if l.done],
                        "chats": {l.name: l.chat_url for l in lanes if l.chat_url},
                    },
                    indent=2,
                )
            )

            if all(l.done for l in lanes):
                print("\nAll REQ windows done.")
                return 0
            if not active and not queue:
                print("No active lanes; exiting.")
                return 1

            print(f"  sleeping {args.poll_sec}s …", flush=True)
            await asyncio.sleep(args.poll_sec)
    finally:
        pw = getattr(browser, "_fq_pw", None)
        try:
            await browser.close()
        except Exception:
            pass
        if pw:
            await pw.stop()


def main() -> None:
    ap = argparse.ArgumentParser(description="Orchestrate ART_REQUIREMENTS art gen")
    ap.add_argument("--port", type=int, default=9222)
    ap.add_argument("--prompts-file", default=DEFAULT_PROMPTS_FILE)
    ap.add_argument(
        "--window-order",
        nargs="*",
        default=None,
        help="Optional window id order override",
    )
    ap.add_argument("--max-windows", type=int, default=2)
    ap.add_argument("--poll-sec", type=int, default=600)
    ap.add_argument("--skip-existing", action="store_true", default=True)
    ap.add_argument("--no-skip-existing", action="store_false", dest="skip_existing")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--quality", type=int, default=90)
    ap.add_argument("--rate-limit-ms", type=int, default=600_000)
    ap.add_argument("--wait-login-ms", type=int, default=600_000)
    args = ap.parse_args()
    raise SystemExit(asyncio.run(run(args)))


if __name__ == "__main__":
    main()
