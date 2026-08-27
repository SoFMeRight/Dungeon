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

# Drop a PV's claimRef ENTIRELY. On restore the PV comes back Available and the re-created PVC
# (which pins spec.volumeName) re-binds it deterministically. Keeping the claimRef — even with
# uid/resourceVersion stripped — can leave the restored PVC stuck 'Lost' after a rollback
# (the binder won't reconcile a pre-claimed PV against a freshly-created claim).
if o.get("kind") == "PersistentVolume":
    (o.get("spec") or {}).pop("claimRef", None)

json.dump(o, sys.stdout)
