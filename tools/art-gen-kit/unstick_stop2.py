#!/usr/bin/env python3
"""Click all ChatGPT stop buttons via CDP with timeout."""
import json, sys, asyncio
import aiohttp

async def click_stop(port: int = 9222):
    async with aiohttp.ClientSession() as s:
        # List pages
        async with s.get(f"http://127.0.0.1:{port}/json") as r:
            pages = await r.json()
        ws_urls = []
        for p in pages:
            if "chatgpt.com/c/" in p.get("url", ""):
                ws_urls.append((p["id"], p["webSocketDebuggerUrl"], p.get("title", "?")))
        
        print(f"Found {len(ws_urls)} ChatGPT tabs", flush=True)
        
        for page_id, ws_url, title in ws_urls:
            try:
                async with aiohttp.ClientSession() as ws_sess:
                    async with ws_sess.ws_connect(ws_url, timeout=aiohttp.ClientTimeout(total=10)) as ws:
                        # Get stop button position
                        await ws.send_json({"id": 1, "method": "Runtime.evaluate", "params": {
                            "expression": """
                            (() => {
                                const sel = 'button[aria-label*="Stop" i], [data-testid="stop-button"]';
                                const btn = document.querySelector(sel);
                                if (!btn) return JSON.stringify({found: false});
                                const r = btn.getBoundingClientRect();
                                return JSON.stringify({found: true, x: r.x + r.width/2, y: r.y + r.height/2});
                            })()
                            """
                        }})
                        resp = await asyncio.wait_for(ws.receive_json(), timeout=5)
                        result = json.loads(resp["result"]["result"]["value"])
                        
                        if not result.get("found"):
                            print(f"  No stop button: {title[:50]}", flush=True)
                            continue
                        
                        x, y = result["x"], result["y"]
                        print(f"  Clicking stop at ({x:.0f},{y:.0f}): {title[:50]}", flush=True)
                        
                        # Click via Input.dispatchMouseEvent
                        for ev in ["mousePressed", "mouseReleased"]:
                            await ws.send_json({"id": 2, "method": "Input.dispatchMouseEvent", "params": {
                                "type": ev, "x": x, "y": y, "button": "left", "clickCount": 1
                            }})
                        await asyncio.sleep(0.5)
            except asyncio.TimeoutError:
                print(f"  Timeout: {title[:50]}", flush=True)
            except Exception as e:
                print(f"  Error [{title[:50]}]: {e}", flush=True)

asyncio.run(click_stop(int(sys.argv[1]) if len(sys.argv) > 1 else 9222))
