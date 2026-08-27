#!/usr/bin/env python3
"""Count VolumeAttachments (from `kubectl get volumeattachment -o json` on stdin) that still
attach the PV named in argv[1]. Used by rbd-rook-swap-core.yml to wait for an RBD volume to fully
DETACH from its node after scale-down before deleting the PVC/PV — deleting while still attached is
what made `kubectl delete pvc --wait` hang and falsely trip the rollback."""
import json
import sys

items = json.load(sys.stdin).get("items", [])
pv = sys.argv[1]
print(sum(1 for a in items
         if (a.get("spec", {}).get("source", {}) or {}).get("persistentVolumeName") == pv))
