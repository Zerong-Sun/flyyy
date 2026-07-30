#!/usr/bin/env python3
"""Click all ChatGPT stop buttons using JS click (no nav wait)."""
import asyncio, sys
from playwright.async_api import async_playwright

async def unstick(port: int = 9222):
    pw = await async_playwright().start()
    browser = await pw.chromium.connect_over_cdp(f"http://127.0.0.1:{port}")
    for page in browser.contexts[0].pages:
        if "chatgpt.com/c/" not in page.url:
            continue
        title = (await page.title())[:50]
        try:
            found = await page.evaluate("""() => {
                const sel = 'button[aria-label*="Stop" i], [data-testid="stop-button"]';
                const btn = document.querySelector(sel);
                if (!btn) return false;
                btn.click();
                return true;
            }""")
            if found:
                print(f"  Clicked stop: {title}", flush=True)
                await page.wait_for_timeout(1000)
            else:
                print(f"  No stop button: {title}", flush=True)
        except Exception as e:
            print(f"  Error [{title}]: {e}", flush=True)
    await browser.close()
    await pw.stop()

asyncio.run(unstick(int(sys.argv[1]) if len(sys.argv) > 1 else 9222))
