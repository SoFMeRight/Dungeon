#!/usr/bin/env python3
"""Count pods (from `kubectl get pods -o json` on stdin) that mount any of the PVCs named in argv.
Every pod object counts, finished ones (Succeeded, Failed) included: they hold no mount, but PVC
protection keeps a PVC from being deleted while any pod object references it. The group task
deletes a group's finished pods (completed Job history) before waiting on this. Used to wait until
nothing references a volume (or a whole quiesce group's volumes) before the swap.
With --finished, prints the names of the finished pods that reference them instead of a count."""
import json
import sys

pods = json.load(sys.stdin)["items"]
args = sys.argv[1:]
finished = args[:1] == ["--finished"]
targets = set(args[1:] if finished else args)
users = [p for p in pods
         if any((v.get("persistentVolumeClaim") or {}).get("claimName") in targets
                for v in (p["spec"].get("volumes") or []))]
if finished:
    for p in users:
        if p.get("status", {}).get("phase") in ("Succeeded", "Failed"):
            print(p["metadata"]["name"])
else:
    print(len(users))
