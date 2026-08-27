#!/usr/bin/env python3
"""Count pods (from `kubectl get pods -o json` on stdin) directly owned by the StatefulSet named
in argv[1]. Used by rbd-rook-migrate-sts.yml to wait until the STS is fully scaled down before
swapping its PVCs."""
import json
import sys

pods = json.load(sys.stdin)["items"]
sts = sys.argv[1]
print(sum(1 for p in pods
         for o in (p["metadata"].get("ownerReferences") or [])
         if o["kind"] == "StatefulSet" and o["name"] == sts))
