#!/bin/bash
#
# ceph-rbd-reclaim-orphan-velero-snapshots-dryrun.sh
#
# DRY-RUN (reports only, deletes NOTHING). For a pre-vetted list of orphaned Velero
# VolumeSnapshots on the OLD `rbd.csi.ceph.com` driver, resolve each to its physical
# `csi-snap-*` RBD clone and classify it: safe-to-delete / already-gone / unsafe(kept).
#
# WHY THIS EXISTS
#   The retiring standalone ceph-csi-rbd driver's csi-snapshotter (v8.5.0) does NOT
#   reprocess VolumeSnapshotContents whose deletionTimestamp was set before the sidecar
#   started (v8.5 WatchListClient streaming-list informer), so `kubectl delete
#   volumesnapshot` on old orphans hangs forever with the physical csi-snap image left
#   behind. Velero CSI-snapshot cleanup on that driver is effectively broken. This is the
#   physical-first workaround: delete the RBD clone directly, THEN clear the k8s finalizers.
#   Run this dry-run first; then run ceph-rbd-reclaim-orphan-velero-snapshots.sh.
#
# REQUIRED INPUT ($LIST) — the orphan list, one snapshot per line, pipe-delimited:
#     <namespace>|<volumesnapshot-name>|<source-pvc>|<owning-backup>
#   Only include snapshots you have PROVEN are orphans: the source PVC no longer exists
#   AND the owning Velero backup is expired/gone. That vetting is the safety boundary —
#   this script trusts the list. Fields 3/4 are documentation only (not used for deletion).
#
# SAFETY: per snapshot, the physical csi-snap clone is only flagged DELETE when it has
#   NO rbd children (no live volume was restored from it) AND NO watchers (not in use).
#
# Usage:  ./ceph-rbd-reclaim-orphan-velero-snapshots-dryrun.sh [orphan-list-file]
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
echo "toolbox=$tb pool=$POOL list=$LIST"

# VSC name -> snapshotHandle (one API call), and the current image inventory (one call)
kubectl get volumesnapshotcontent -o json 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin)
for x in d["items"]:
    print(x["metadata"]["name"]+"|"+((x.get("status") or {}).get("snapshotHandle","") or ""))
' > /tmp/vsc_handles.txt
ex rbd ls "$POOL" | sort > /tmp/rbd_all.txt
echo "VSC handle map: $(wc -l < /tmp/vsc_handles.txt) | images in pool: $(wc -l < /tmp/rbd_all.txt)"
echo

DEL=/tmp/reclaim_delete.txt; SKIP=/tmp/reclaim_skip.txt; : > "$DEL"; : > "$SKIP"
n=0
while IFS='|' read ns name src bk; do
  [ -n "$name" ] || continue
  n=$((n+1))
  vsc=$(kubectl get volumesnapshot "$name" -n "$ns" -o jsonpath='{.status.boundVolumeSnapshotContentName}' 2>/dev/null)
  handle=$(grep "^${vsc}|" /tmp/vsc_handles.txt | head -1 | cut -d'|' -f2)
  [ -n "$handle" ] || { echo "SKIP|$ns/$name|no-handle" >>"$SKIP"; continue; }
  # snapshotHandle = 0001-0024-<clusterID w/ dashes>-<poolID>-<snapUUID>; the snap UUID is the
  # trailing standard 8-4-4-4-12 (clusterID ALSO has dashes, so ${handle##*-} is WRONG).
  uuid=$(printf '%s' "$handle" | grep -oiE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
  [ -n "$uuid" ] || { echo "SKIP|$ns/$name|bad-handle-format($handle)" >>"$SKIP"; continue; }
  img="csi-snap-$uuid"
  grep -qx "$img" /tmp/rbd_all.txt || { echo "SKIP|$ns/$name|$img|image-absent(already-gone)" >>"$SKIP"; continue; }
  ch=$(ex rbd children --all "$POOL/$img" 2>/dev/null | grep -c .)
  [ "${ch:-0}" = "0" ] || { echo "SKIP|$ns/$name|$img|HAS-$ch-CHILDREN(in-use)" >>"$SKIP"; continue; }
  w=$(ex rbd status "$POOL/$img" 2>/dev/null | grep -c watcher)
  [ "${w:-0}" = "0" ] || { echo "SKIP|$ns/$name|$img|HAS-WATCHER" >>"$SKIP"; continue; }
  sz=$(ex rbd info "$POOL/$img" 2>/dev/null | awk '/size/{print $2$3; exit}')
  echo "$ns|$name|$vsc|$img|$sz" >>"$DEL"
done < "$LIST"

echo "=================== DRY-RUN SUMMARY ==================="
echo "orphan snapshots examined: $n"
echo "WOULD DELETE (safe):       $(wc -l < "$DEL")"
echo "WOULD SKIP:                $(wc -l < "$SKIP")"
echo
echo "--- skip reasons ---"
cut -d'|' -f3- "$SKIP" | sed -E 's/csi-snap-[0-9a-f-]+/csi-snap-*/' | sort | uniq -c | sort -rn | sed 's/^/  /'
echo
echo "--- sample WOULD-DELETE (first 12) ---"
head -12 "$DEL" | awk -F'|' '{printf "  %-14s %-52s %-46s %s\n",$1,$2,$4,$5}'
echo
echo "NOTE: any HAS-CHILDREN / HAS-WATCHER lines are UNSAFE and must NOT be reclaimed."
echo "Lists written: $DEL (safe) and $SKIP (skipped)."
