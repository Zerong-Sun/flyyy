#!/usr/bin/env python3
"""Click the ChatGPT stop button on specified tabs to unstick generation."""
import asyncio, sys
from playwright.async_api import async_playwright

async def unstick(port: int = 9222):
    pw = await async_playwright().start()
    browser = await pw.chromium.connect_over_cdp(f"http://127.0.0.1:{port}")
    click_count = 0
    for page in browser.contexts[0].pages:
        if "chatgpt.com/c/" not in page.url:
            continue
        try:
            stop_btn = page.locator(
                'button[aria-label*="Stop" i], [data-testid="stop-button"], button:has-text("Stop")'
            )
            count = await stop_btn.count()
            if count > 0:
                title = (await page.title())[:60]
                print(f"  Clicking stop on: {title}", flush=True)
                await stop_btn.first.click()
                click_count += 1
                await page.wait_for_timeout(1000)
            else:
                print(f"  No stop button on: {(await page.title())[:60]}", flush=True)
        except Exception as e:
            print(f"  Error on page {page.url[:60]}: {e}", flush=True)
    print(f"Clicked {click_count} stop buttons", flush=True)
    await browser.close()
    await pw.stop()

if __name__ == "__main__":
    asyncio.run(unstick(int(sys.argv[1]) if len(sys.argv) > 1 else 9222))
