# training-dummy — DB disaster lab

A disposable ground for standing up scratch database clusters, wedging them on purpose, and
proving HASteward's recovery **deterministically** before it ever touches production.
Everything in the `training-dummy` namespace is expendable.

The namespace is flux-managed (`fluxcd/infrastructure/namespaces/training-dummy.yaml`).
The cluster + fault injectors here are **not** in any kustomization — applied on demand.

## Stand up a scratch CNPG cluster

```sh
kubectl apply -f cluster.yaml
kubectl -n training-dummy get cluster training-dummy-postgres -w   # wait for 3/3, healthy
```

## Inject a disaster

| Fault | Script | Reproduces |
|-------|--------|------------|
| Stuck failover | `./wedge-failover.sh -c training-dummy-postgres -n training-dummy` | The exact wedge deadlock-recover leaves on a disk-full primary: currentPrimary's pod gone while a failover is open — operator loops "Failing over", won't recreate the primary. |

Disk-full deadlock (fill the primary's 1Gi PVC until postgres can't checkpoint) is the
natural upstream of the wedge; add an injector for it when testing the full deadlock-recover
flow end to end. The wedge injector short-circuits to the interesting state in seconds.

## Run the recovery under test

```sh
../jobs/run.sh deadlock-recover -c training-dummy-postgres -n training-dummy -i <ordinal>
kubectl -n fairy-bottle logs -f job/<printed-name>
```

Iterate the fix, re-inject, re-run — no production risk. When a mechanism heals the wedge
deterministically here, codify it into `settlePrimary` and only then apply to the real DB.

## Tear down

```sh
kubectl delete -f cluster.yaml
kubectl -n training-dummy delete pvc -l cnpg.io/cluster=training-dummy-postgres
```
