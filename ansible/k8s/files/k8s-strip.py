#!/usr/bin/env python3
"""Strip runtime/server fields from a k8s object (stdin JSON) so it can be re-created with
`kubectl apply`. Used to escrow the old PV/PVC before an RBD driver migration and to recreate
them verbatim on rollback."""
import json
import sys

o = json.load(sys.stdin)
m = o.get("metadata", {}) or {}
for k in ("resourceVersion", "uid", "creationTimestamp", "generation",
          "managedFields", "finalizers", "selfLink"):
    m.pop(k, None)
(m.get("annotations") or {}).pop("kubectl.kubernetes.io/last-applied-configuration", None)
o.pop("status", None)

# A PV's claimRef carries the old PVC's uid/resourceVersion — drop them so the recreated PVC
# (with a fresh uid) can bind.
cr = (o.get("spec") or {}).get("claimRef")
if isinstance(cr, dict):
    cr.pop("uid", None)
    cr.pop("resourceVersion", None)

json.dump(o, sys.stdout)
