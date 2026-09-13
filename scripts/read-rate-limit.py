#!/usr/bin/env python3
"""Read the primary Codex reset timestamp through app-server JSON-RPC."""
import json
import os
import subprocess
import sys
import time

if len(sys.argv) != 2:
    sys.exit("usage: read-rate-limit.py /absolute/path/to/codex")

process = subprocess.Popen(
    [sys.argv[1], "app-server", "--stdio"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    env=os.environ.copy(),
)

def request(request_id, method, params):
    payload = {"jsonrpc": "2.0", "id": request_id, "method": method, "params": params}
    process.stdin.write(json.dumps(payload) + "\n")
    process.stdin.flush()
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        line = process.stdout.readline()
        if not line:
            break
        message = json.loads(line)
        if message.get("id") == request_id:
            if "error" in message:
                raise RuntimeError(message["error"])
            return message["result"]
    raise RuntimeError(f"no response to {method}")

try:
    request(1, "initialize", {"clientInfo": {"name": "codex-limit-saver", "version": "1.0"}})
    result = request(2, "account/rateLimits/read", {"excludeResetCreditDetails": True})
    resets_at = result["rateLimits"]["primary"]["resetsAt"]
    if not isinstance(resets_at, int) or resets_at <= 0:
        raise RuntimeError("primary reset timestamp is unavailable")
    print(resets_at)
finally:
    if process.stdin:
        process.stdin.close()
    process.terminate()
    try:
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        process.kill()
