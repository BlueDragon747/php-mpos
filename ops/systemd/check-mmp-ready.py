#!/usr/bin/env python3
import json
import sys
import time
import urllib.request

port = sys.argv[1]
expected = int(sys.argv[2])
payload = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "getaux", "params": []}).encode()
req = urllib.request.Request(
    f"http://127.0.0.1:{port}/",
    data=payload,
    headers={"Content-Type": "application/json"},
)
last = "no response"
for _ in range(120):
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            body = json.loads(resp.read())
        result = body.get("result") if isinstance(body, dict) else None
        if isinstance(result, dict):
            ready = int(result.get("ready_count") or 0)
            total = int(result.get("total_chains") or 0)
            if ready == total == expected:
                print(f"proxy aux templates: {ready}/{total} ready")
                sys.exit(0)
            waiting = result.get("waiting_chains") or []
            names = [str(row.get("chain") or row.get("alias") or "?") for row in waiting]
            last = f"{ready}/{total} ready"
            if names:
                last += "; waiting on " + ", ".join(names)
    except Exception as exc:
        last = str(exc)
    time.sleep(1)
print(f"ERROR: merged-mining proxy not fully ready: {last}", file=sys.stderr)
sys.exit(1)
