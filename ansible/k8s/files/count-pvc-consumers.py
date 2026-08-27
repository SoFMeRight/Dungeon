#!/usr/bin/env python3
"""Count pods (from `kubectl get pods -o json` on stdin) that mount the PVC named in argv[1].
Used by rbd-rook-migrate-one.yml to wait until a volume is fully unmounted before the swap."""
import json
import sys

pods = json.load(sys.stdin)["items"]
target = sys.argv[1]
print(sum(1 for p in pods
         for v in (p["spec"].get("volumes") or [])
         if (v.get("persistentVolumeClaim") or {}).get("claimName") == target))
