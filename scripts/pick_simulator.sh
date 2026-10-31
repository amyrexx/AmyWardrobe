#!/usr/bin/env bash
# Печатает UDID первого доступного iPhone-симулятора (самый новый runtime).
set -euo pipefail
xcrun simctl list devices available -j | python3 -c '
import json, sys
data = json.load(sys.stdin)["devices"]
best = None
for runtime, devs in data.items():
    if "iOS" not in runtime:
        continue
    ver = runtime.rsplit("iOS-", 1)[-1]
    key = tuple(int(x) for x in ver.split("-") if x.isdigit())
    for d in devs:
        if d.get("isAvailable", True) and d["name"].startswith("iPhone"):
            cand = (key, d["name"], d["udid"])
            if best is None or cand[0] > best[0] or (cand[0] == best[0] and "Pro" not in cand[1] and "Pro" in best[1]):
                best = cand
if not best:
    sys.exit("Нет доступных iPhone-симуляторов")
print(best[2])
'
