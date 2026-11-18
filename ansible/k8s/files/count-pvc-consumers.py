#!/usr/bin/env python3
"""Count pods (from `kubectl get pods -o json` on stdin) that mount any of the PVCs named in argv.
Terminating pods count: they hold the mount until they're gone. Finished pods (Succeeded, Failed)
don't: they hold no mount, and a CronJob's completed pods stay listed indefinitely. Used to wait
until a volume (or a whole quiesce group's volumes) is fully unmounted before the swap."""
import json
import sys

pods = json.load(sys.stdin)["items"]
targets = set(sys.argv[1:])
print(sum(1 for p in pods
         if p.get("status", {}).get("phase") not in ("Succeeded", "Failed")
         for v in (p["spec"].get("volumes") or [])
         if (v.get("persistentVolumeClaim") or {}).get("claimName") in targets))
