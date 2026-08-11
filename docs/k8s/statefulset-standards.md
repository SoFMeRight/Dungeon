# StatefulSet Standards for Persistent Data Services

## Policy: Use StatefulSets for All Persistent Data

**ALL services with persistent storage MUST use StatefulSets, not Deployments.**

## Why StatefulSets?

- ✅ **Stable PVC names** - No PVC multiplication on updates
- ✅ **Predictable pod names** - `app-0`, `app-1`, etc.
- ✅ **Ordered deployment** - Pods start/stop in sequence
- ✅ **Persistent storage lifecycle** - PVCs persist across pod restarts
- ✅ **No data loss** on configuration changes

## When to Use StatefulSets

### Required for:
- Database services (PostgreSQL, Redis, etc.)
- Search engines (Meilisearch, Elasticsearch)
- Media servers with configuration (Plex, Calibre-web)
- Any service that writes important data to disk

### Not needed for:
- Stateless web applications
- Load balancers/proxies
- Pure compute jobs
- Services using only ConfigMaps/Secrets

## StatefulSet Template

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: service-name
  namespace: operationtimecapsule
spec:
  serviceName: service-name
  replicas: 1
  selector:
    matchLabels:
      app: service-name
  template:
    metadata:
      labels:
        app: service-name
    spec:
      containers:
      - name: service-name
        image: image:tag
        volumeMounts:
        - name: data
          mountPath: /data
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: ceph-rbd-retain
      resources:
        requests:
          storage: 10Gi
```

## Storage Class Standards

- **Default**: `ceph-rbd-retain` for persistent data
- **Temporary**: `ceph-rbd-delete` for cache/temp data only
- **Shared**: Static PVs for shared media/content

## Migration Checklist

When converting Deployment → StatefulSet:

1. ✅ Change `kind: Deployment` to `kind: StatefulSet`
2. ✅ Add `serviceName: service-name`
3. ✅ Move PVCs to `volumeClaimTemplates`
4. ✅ Use `ceph-rbd-retain` storage class
5. ✅ Remove standalone PVC definitions
6. ✅ Test data persistence across updates

## Current Status

### Converted ✅
- Linkwarden (postgres, meilisearch)
- Plex (config, transcode)

### Needs Conversion ❌
- Mealie + postgres
- Calibre-web

### Stateless (Deployment OK) ✅
- IT-Tools
- SearXNG
- Linkwarden (main app)
