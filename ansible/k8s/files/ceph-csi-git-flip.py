#!/usr/bin/env python3
"""Point the git definitions of migrated static PVs at their new driver.

  ceph-csi-git-flip.py [--check] <repo_dir> <old_secret_ns> <new_secret_ns> < records.json

records.json is a list of ceph-csi-discover.py records with static=true. In each record's gitFile,
only the YAML document declaring that PV changes: its `driver:` line goes from the record's old
driver to its new one, and each secret ref's `namespace:` from old_secret_ns to new_secret_ns.
Lines and formatting are otherwise left as found.

--check changes nothing; it confirms every record's file and lines are where the flip expects, so a
plan run catches a PV that is declared somewhere the flip can't reach (a patch, a base without the
driver) before anything is migrated. Prints one changed file per line; exits 1 on any problem.
"""
import json
import os
import re
import sys

args = sys.argv[1:]
check = args[:1] == ["--check"]
if check:
    args = args[1:]
repo_dir, old_ns, new_ns = args
recs = json.load(sys.stdin)

by_file = {}
for r in recs:
    by_file.setdefault(r["gitFile"], []).append(r)

problems, changed = [], []
for rel, rs in sorted(by_file.items()):
    path = os.path.join(repo_dir, rel)
    if not rel or not os.path.isfile(path):
        problems.append("%s: no git file for %s" % (rel or "-", ", ".join(r["pv"] for r in rs)))
        continue
    docs = re.split(r"(?m)^(---[ \t]*\n)", open(path).read())
    for r in rs:
        name_re = re.compile(r"(?m)^  name:[ \t]*[\"']?%s[\"']?[ \t]*$" % re.escape(r["pv"]))
        idx = [i for i, d in enumerate(docs)
               if re.search(r"(?m)^kind:[ \t]*PersistentVolume[ \t]*$", d) and name_re.search(d)]
        if len(idx) != 1:
            problems.append("%s: %d documents declare PV %s" % (rel, len(idx), r["pv"]))
            continue
        d = docs[idx[0]]
        drv = re.compile(r"(?m)^(\s+driver:[ \t]*)[\"']?%s[\"']?[ \t]*$" % re.escape(r["oldDriver"]))
        if len(drv.findall(d)) != 1:
            problems.append("%s: PV %s has no single 'driver: %s' line" % (rel, r["pv"], r["oldDriver"]))
            continue
        d = drv.sub(lambda m: m.group(1) + r["newDriver"], d)
        ns_re = re.compile(r"(?m)^(\s+namespace:[ \t]*)[\"']?%s[\"']?[ \t]*$" % re.escape(old_ns))
        n_refs = len(r["secretRefs"])
        if len(ns_re.findall(d)) != n_refs:
            problems.append("%s: PV %s has %d 'namespace: %s' lines for %d secret refs"
                            % (rel, r["pv"], len(ns_re.findall(d)), old_ns, n_refs))
            continue
        docs[idx[0]] = ns_re.sub(lambda m: m.group(1) + new_ns, d)
    if not check:
        open(path, "w").write("".join(docs))
    changed.append(rel)

for p in problems:
    sys.stderr.write("FLIP: %s\n" % p)
print("\n".join(changed))
sys.exit(1 if problems else 0)
