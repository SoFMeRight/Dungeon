#!/bin/bash
#
# ceph-rbd-reclaim-orphan-velero-snapshots.sh
#
# EXECUTE the physical-first reclaim of orphaned Velero VolumeSnapshots on the OLD
# `rbd.csi.ceph.com` driver. DESTRUCTIVE — run the companion *-dryrun.sh first and read
# its output before running this.
#
# WHY THIS EXISTS
#   The retiring standalone ceph-csi-rbd csi-snapshotter (v8.5.0) does NOT reprocess
#   VolumeSnapshotContents whose deletionTimestamp predates the sidecar start (v8.5
#   WatchListClient streaming-list informer). So `kubectl delete volumesnapshot` on old
#   orphans hangs forever with the physical csi-snap RBD image left behind — Velero
#   CSI-snapshot cleanup on that driver is effectively broken. This deletes the physical
#   clone directly, THEN clears the k8s finalizers. Doing physical-FIRST guarantees we
#   never orphan an RBD image by clearing finalizers on a still-present snapshot.
#
# WHAT IT DOES, per snapshot in $LIST:
#   1. resolve VolumeSnapshot -> boundVSC -> status.snapshotHandle -> csi-snap-<UUID>
#   2. re-verify safety AT ACTION TIME: no rbd children (no restore cloned from it) and
#      no watchers (not in use). If either -> SKIP-UNSAFE, leave k8s objects intact.
#   3. `rbd snap purge` + `rbd rm` the clone (physical FIRST).
#   4. ONLY after the physical image is gone, force-clear the k8s VSC + VS
#      `bound-protection` finalizers so the objects delete.
#   Then PHASE-C sweeps freed BASE images (csi-vol-*) whose snapshot children are now
#   gone: reclaimed only when they have no PV reference AND no csi-snap children AND no
#   watcher (base images whose snaps are still referenced by LIVE snapshots are kept).
#
# REQUIRED INPUT ($LIST) — the orphan list, one snapshot per line, pipe-delimited:
#     <namespace>|<volumesnapshot-name>|<source-pvc>|<owning-backup>
#   Only include PROVEN orphans (source PVC gone AND owning Velero backup expired/gone).
#   That vetting is the safety boundary — this script trusts the list.
#
# Usage:  ./ceph-rbd-reclaim-orphan-velero-snapshots.sh [orphan-list-file]
#   env:  POOL (default dungeon), OPERATOR_NS (default gorons-bracelet), KUBECONFIG
#
set -o pipefail
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
POOL="${POOL:-dungeon}"
OPERATOR_NS="${OPERATOR_NS:-gorons-bracelet}"
LIST="${1:-/tmp/prune_snaps.txt}"

[ -r "$LIST" ] || { echo "ERROR: orphan list not found/readable: $LIST" >&2
  echo "  Provide a pipe-delimited file: <ns>|<volumesnapshot>|<source-pvc>|<owning-backup>" >&2; exit 1; }

tb=$(kubectl get pods -n "$OPERATOR_NS" -o name 2>/dev/null | grep rbd-toolbox | head -1 | cut -d/ -f2)
[ -n "$tb" ] || { echo "ERROR: no rbd-toolbox pod in $OPERATOR_NS" >&2; exit 1; }
ex(){ kubectl exec -n "$OPERATOR_NS" "$tb" -- "$@" 2>/dev/null; }

kubectl get volumesnapshotcontent -o json 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin)
for x in d["items"]:
    print(x["metadata"]["name"]+"|"+((x.get("status") or {}).get("snapshotHandle","") or ""))
' > /tmp/vsc_handles.txt
ex rbd ls "$POOL" | sort > /tmp/rbd_all.txt

rm_ok=0; gone=0; cleared=0; unsafe=0; rmfail=0
echo "===== PHASE-A: per-snapshot physical delete + finalizer clear ====="
while IFS='|' read ns name src bk; do
  [ -n "$name" ] || continue
  vsc=$(kubectl get volumesnapshot "$name" -n "$ns" -o jsonpath='{.status.boundVolumeSnapshotContentName}' 2>/dev/null)
  handle=$(grep "^${vsc}|" /tmp/vsc_handles.txt | head -1 | cut -d'|' -f2)
  uuid=$(printf '%s' "$handle" | grep -oiE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
  img="csi-snap-$uuid"
  physical_ok=false

  if [ -n "$uuid" ] && grep -qx "$img" /tmp/rbd_all.txt; then
    # re-verify safety RIGHT NOW (never trust stale dry-run data)
    ch=$(ex rbd children --all "$POOL/$img" 2>/dev/null | grep -c .)
    w=$(ex rbd status "$POOL/$img" 2>/dev/null | grep -c watcher)
    if [ "${ch:-0}" != "0" ] || [ "${w:-0}" != "0" ]; then
      echo "SKIP-UNSAFE $ns/$name $img children=$ch watchers=$w (k8s objects left intact)"
      unsafe=$((unsafe+1)); continue
    fi
    ex rbd snap purge "$POOL/$img" >/dev/null 2>&1
    if ex rbd rm "$POOL/$img" >/dev/null 2>&1; then
      echo "RECLAIMED $img"; rm_ok=$((rm_ok+1)); physical_ok=true
    else
      echo "RM-FAILED $ns/$name $img (k8s objects left intact)"; rmfail=$((rmfail+1)); continue
    fi
  else
    gone=$((gone+1)); physical_ok=true   # physical already absent -> safe to clear k8s
  fi

  if [ "$physical_ok" = "true" ]; then
    [ -n "$vsc" ] && kubectl patch volumesnapshotcontent "$vsc" --type=merge -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1
    kubectl delete volumesnapshot "$name" -n "$ns" --ignore-not-found --wait=false >/dev/null 2>&1
    kubectl patch volumesnapshot "$name" -n "$ns" --type=merge -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1
    cleared=$((cleared+1))
  fi
done < "$LIST"

echo
echo "PHASE-A DONE: physical-rm=$rm_ok already-gone=$gone k8s-cleared=$cleared unsafe-left=$unsafe rm-failed=$rmfail"
echo
echo "===== PHASE-B: verify snapshot objects gone ====="
left=0
while IFS='|' read ns name src bk; do
  [ -n "$name" ] || continue
  kubectl get volumesnapshot "$name" -n "$ns" >/dev/null 2>&1 && left=$((left+1))
done < "$LIST"
echo "orphan VolumeSnapshots still present: $left"
echo
echo "===== PHASE-C: reclaim freed base images (no PV ref, no csi-snap children, no watchers) ====="
kubectl get pv -o json 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print("\n".join((p["spec"].get("csi") or {}).get("volumeAttributes",{}).get("imageName","") for p in d["items"] if (p["spec"].get("csi") or {}).get("volumeAttributes",{}).get("imageName")))' | sort -u > /tmp/ref_final.txt
ex rbd ls "$POOL" | grep "^csi-vol" | sort > /tmp/all_final.txt
base_freed=0
while read img; do
  grep -qx "$img" /tmp/ref_final.txt && continue                  # still PV-referenced -> keep
  ch=$(ex rbd children --all "$POOL/$img" 2>/dev/null | grep -c csi-snap)
  [ "${ch:-0}" != "0" ] && continue                                # still has snapshot children -> keep
  w=$(ex rbd status "$POOL/$img" 2>/dev/null | grep -c watcher)
  [ "${w:-0}" != "0" ] && continue                                 # in use -> keep
  sz=$(ex rbd info "$POOL/$img" 2>/dev/null | awk '/size/{print $2$3; exit}')
  ex rbd snap purge "$POOL/$img" >/dev/null 2>&1
  if ex rbd rm "$POOL/$img" >/dev/null 2>&1; then echo "BASE-RECLAIMED $img ($sz)"; base_freed=$((base_freed+1)); fi
done < /tmp/all_final.txt
echo
echo "RECLAIM-DONE: csi-snap-clones-removed=$rm_ok base-images-removed=$base_freed"
