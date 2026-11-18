#!/usr/bin/env python3
"""Print the migration plan for the ceph-csi-discover.py records in scope (JSON list on stdin)."""
import collections
import json
import sys

recs = json.load(sys.stdin)
groups = collections.OrderedDict()
others = collections.defaultdict(list)
for r in sorted(recs, key=lambda r: (r["group"] or r["key"])):
    (groups.setdefault(r["group"], []) if r["tier"] == "group" else others[r["tier"]]).append(r)

vols = [r for g in groups.values() for r in g]
print("migrate: %d group(s), %d volume(s) (%d rbd, %d cephfs), %d static (git flip)" % (
    len(groups), len(vols), sum(r["type"] == "rbd" for r in vols),
    sum(r["type"] == "cephfs" for r in vols), sum(r["static"] for r in vols)))
for key, g in groups.items():
    types = collections.Counter(r["type"] for r in g)
    static = sum(r["static"] for r in g)
    stops = " ".join(w["ref"] for w in g[0]["workloadInfo"]) or (
        "no workload" if g[0]["operatorPauses"] else "nothing (unused)")
    pauses = "; pauses " + " ".join("%s %s/%s" % (p["how"], p["namespace"], p["name"])
                                    for p in g[0]["operatorPauses"]) if g[0]["operatorPauses"] else ""
    print("  %s: %s%s; stops %s%s" % (key, ", ".join("%d %s" % (n, t) for t, n in sorted(types.items())),
                                      ", %d static" % static if static else "", stops, pauses))
if others:
    print("not migrated by this playbook:")
for tier in ("operator", "cnpg", "manual", "released"):
    rs = others.get(tier)
    if not rs:
        continue
    if tier == "cnpg":
        clusters = sorted({"%s/%s" % (r["namespace"], r["pvcLabels"]["cnpg.io/cluster"]) for r in rs})
        print("  cnpg: %d volume(s) in %d cluster(s) discovery could not read: %s" % (
            len(rs), len(clusters), ", ".join(clusters)))
    elif tier == "operator":
        by = collections.OrderedDict()
        for r in rs:
            by.setdefault(r["group"], []).append(r)
        print("  operator: %d volume(s) in %d group(s)" % (len(rs), len(by)))
        for key, g in by.items():
            print("    %s: %d volume(s); %s" % (key, len(g), g[0]["operator"]))
    else:
        print("  %s: %d volume(s)" % (tier, len(rs)))
        for r in rs:
            print("    %s: %s" % (r["key"], r["reason"]))
