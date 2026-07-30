#!/usr/bin/env python3
"""Launch Chrome with remote debugging via Playwright and keep alive."""
import asyncio
import signal
import sys
from playwright.async_api import async_playwright

async def main():
    pw = await async_playwright().start()
    browser = await pw.chromium.launch(
        headless=False,
        args=[
            "--remote-debugging-port=9222",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-features=TranslateUI",
            "--disable-sync",
            "--no-sandbox",
            "--disable-gpu-sandbox",
        ],
    )
    print(f"Browser launched on :9222", flush=True)

    stop = asyncio.Event()

    def _handler():
        print("\nShutting down...", flush=True)
        stop.set()

    loop = asyncio.get_running_loop()
    for s in (signal.SIGTERM, signal.SIGINT):
        try:
            loop.add_signal_handler(s, _handler)
        except NotImplementedError:
            pass

    await stop.wait()
    await browser.close()
    await pw.stop()
    print("Browser closed.", flush=True)

if __name__ == "__main__":
    asyncio.run(main())
