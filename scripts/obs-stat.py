#!/usr/bin/env python3
"""Live OBS performance stats through the obs-websocket v5 API.

This is how the before/after numbers in the README were measured. It reports
the render-skip percentage in real time, which is the metric that tells you
whether OBS can keep up.

Enable the server first:
    OBS -> Tools -> WebSocket Server Settings -> Enable
    (set a password; never commit it)

Usage:
    OBS_WS_PASSWORD=secret ./scripts/obs-stat.py --duration 20
    ./scripts/obs-stat.py -p secret --url ws://127.0.0.1:4455 --start

Options:
    --start     start a recording automatically for the duration, then stop it.
                Without it, polling only works while OBS is already recording.

Requires: pip install websockets   (or: sudo apt install python3-websockets)
"""

import argparse
import asyncio
import base64
import hashlib
import json
import os
import sys

try:
    import websockets
except ImportError:  # pragma: no cover
    sys.exit(
        "Missing dependency 'websockets'.\n"
        "  pip install websockets\n"
        "  # or: sudo apt install python3-websockets"
    )

# obs-websocket v5 opcodes
OP_HELLO = 0
OP_IDENTIFY = 1
OP_IDENTIFIED = 2
OP_EVENT = 5
OP_REQUEST = 6
OP_REQUEST_RESPONSE = 7


def auth_string(password: str, salt: str, challenge: str) -> str:
    """obs-websocket v5 authentication: base64(sha256(base64(sha256(pw+salt))+challenge))."""
    secret = base64.b64encode(hashlib.sha256((password + salt).encode()).digest()).decode()
    return base64.b64encode(hashlib.sha256((secret + challenge).encode()).digest()).decode()


class Client:
    def __init__(self, ws):
        self.ws = ws
        self._n = 0

    async def request(self, request_type: str, data=None) -> dict:
        self._n += 1
        req_id = str(self._n)
        payload = {"requestType": request_type, "requestId": req_id}
        if data is not None:
            payload["requestData"] = data
        await self.ws.send(json.dumps({"op": OP_REQUEST, "d": payload}))
        while True:
            msg = json.loads(await self.ws.recv())
            if msg.get("op") == OP_EVENT:
                continue
            if msg.get("op") == OP_REQUEST_RESPONSE and msg["d"].get("requestId") == req_id:
                return msg["d"]


async def identify(ws, password: str) -> None:
    hello = json.loads(await ws.recv())
    if hello.get("op") != OP_HELLO:
        raise RuntimeError(f"Unexpected first message: {hello}")

    payload = {"rpcVersion": 1, "eventSubscriptions": 0}
    auth = hello["d"].get("authentication")
    if auth:
        if not password:
            sys.exit("This OBS WebSocket server requires a password. Use -p / OBS_WS_PASSWORD.")
        payload["authentication"] = auth_string(password, auth["salt"], auth["challenge"])

    await ws.send(json.dumps({"op": OP_IDENTIFY, "d": payload}))
    reply = json.loads(await ws.recv())
    if reply.get("op") != OP_IDENTIFIED:
        sys.exit(f"Identification failed: {reply}")


def fmt(value, suffix=""):
    return f"{value:.2f}{suffix}" if isinstance(value, (int, float)) else str(value)


async def run(args):
    password = args.password or os.environ.get("OBS_WS_PASSWORD", "")

    async with websockets.connect(args.url, max_size=None) as ws:
        await identify(ws, password)
        client = Client(ws)

        if args.start:
            r = await client.request("StartRecord")
            ok = r["requestStatus"].get("result")
            print("StartRecord:", "ok" if ok else r["requestStatus"])
            if not ok:
                return
            await asyncio.sleep(1)

        print(f"{'t':>4}  {'activeFps':>9}  {'avgRender':>10}  {'renderSkip':>16}  {'cpu%':>5}")
        print("-" * 54)

        samples = []
        for i in range(args.duration):
            stats = (await client.request("GetStats")).get("responseData", {})
            rf = stats.get("renderTotalFrames") or 0
            rs = stats.get("renderSkippedFrames") or 0
            pct = (100.0 * rs / rf) if rf else 0.0
            samples.append((pct, stats))
            print(
                f"{i + 1:>4}  {fmt(stats.get('activeFps')):>9}  "
                f"{fmt(stats.get('averageFrameRenderTime'), 'ms'):>10}  "
                f"{f'{rs}/{rf} ({pct:.1f}%)':>16}  "
                f"{fmt(stats.get('cpuUsage')):>5}"
            )
            await asyncio.sleep(1)

        if args.start:
            r = await client.request("StopRecord")
            print("StopRecord:", "ok" if r["requestStatus"].get("result") else r["requestStatus"])

    if samples:
        last_pct, last = samples[-1]
        rf = last.get("renderTotalFrames") or 0
        rs = last.get("renderSkippedFrames") or 0
        verdict = "OK" if last_pct < 1 else ("BORDERLINE" if last_pct < 5 else "BAD")
        print("-" * 54)
        print(f"FINAL renderSkip={rs}/{rf} ({last_pct:.1f}%)  -> {verdict}")
        if last_pct >= 1:
            print("See the Troubleshooting table in README.md.")


def main():
    p = argparse.ArgumentParser(description="Live OBS performance stats (obs-websocket v5).")
    p.add_argument("-u", "--url", default="ws://127.0.0.1:4455", help="WebSocket URL")
    p.add_argument("-p", "--password", default=None, help="WebSocket password (or set OBS_WS_PASSWORD)")
    p.add_argument("-d", "--duration", type=int, default=15, help="how many seconds to sample")
    p.add_argument("--start", action="store_true", help="start recording for the duration, then stop")
    args = p.parse_args()

    try:
        asyncio.run(run(args))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
