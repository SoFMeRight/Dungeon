#!/bin/sh
# node-converge: run the host playbooks against the cluster's nodes from the revision
# Flux applied, never touching the node this pod runs on.
#
#   CONVERGE_PHASE=control-plane  (the CronJob) converges every control-plane host but
#     its own, then fires the hand-off Job pinned to the hosts it just converged and
#     succeeds once that Job's pod is running. A failed first half fires nothing.
#   CONVERGE_PHASE=handoff  (the Job it fires) converges the host the first half stood
#     on, then every worker, and passes or fails on its own.
#
# kubelet-provision orders kubeadm from the cluster's kubeadm-config version, not a
# fixed host, so excluding any one control-plane node keeps the upgrade order correct.
set -eu

: "${CONVERGE_PHASE:?}" "${NODE_NAME:?}" "${HOST_IP:?}" "${REPO_URL:?}" "${CRONJOB_NAME:?}" "${BAO_ADDR:?}"
work=/tmp/dungeon
inventory=ansible/inventory

# The revision Flux applied, so hosts converge from the same commit the cluster runs.
rev=$(kubectl -n flux-system get gitrepository flux-system -o jsonpath='{.status.artifact.revision}')
sha=${rev##*:}
git init -q "$work"
git -C "$work" fetch -q --depth 1 "$REPO_URL" "$sha"
git -C "$work" checkout -q FETCH_HEAD
cd "$work"
echo "converging from ${rev}"

# A throwaway key, signed for this run by optcp's SSH CA (OpenBao optcp-ssh) after
# logging in as this pod's service account. Nodes trust the CA; nothing is stored.
# The nodes trust the committed CA public key; a certificate from any other CA is refused.
committed=$(ssh-keygen -lf ansible/files/optcp-ssh-ca.pub | awk '{print $2}')
serving=$(curl -fsS "${BAO_ADDR}/v1/optcp-ssh/public_key" | ssh-keygen -lf - | awk '{print $2}')
[ "$committed" = "$serving" ] || { echo "OpenBao's optcp-ssh CA is ${serving}; the nodes trust ${committed} (ansible/files/optcp-ssh-ca.pub)"; exit 1; }

mkdir -p /tmp/ssh
ssh-keygen -q -t ed25519 -N "" -C "node-converge ${CONVERGE_PHASE}" -f /tmp/ssh/id
jwt=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
token=$(curl -fsS -X POST "${BAO_ADDR}/v1/auth/kubernetes/login" \
  -d "$(JWT="$jwt" yq -n -o json -I0 '{"role": "node-converge", "jwt": strenv(JWT)}')" \
  | yq -p json -r '.auth.client_token')
curl -fsS -X POST -H "X-Vault-Token: ${token}" "${BAO_ADDR}/v1/optcp-ssh/sign/node-converge" \
  -d "$(KEY="$(cat /tmp/ssh/id.pub)" yq -n -o json -I0 '{"public_key": strenv(KEY), "valid_principals": "kai"}')" \
  | yq -p json -r '.data.signed_key' > /tmp/ssh/id-cert.pub
unset jwt token
ssh-keygen -Lf /tmp/ssh/id-cert.pub | grep -E "Valid|Principals" -A1 | tr -s ' '
export ANSIBLE_PRIVATE_KEY_FILE=/tmp/ssh/id
export ANSIBLE_REMOTE_USER=kai
export ANSIBLE_HOST_KEY_CHECKING=True
# The certificates carry no permit-pty; Ansible needs no tty.
export ANSIBLE_SSH_USETTY=False
export ANSIBLE_SSH_ARGS="-o UserKnownHostsFile=$work/ansible/known_hosts -o StrictHostKeyChecking=yes"

# The inventory host whose ansible_host is this pod's node.
self=$(ansible-inventory -i "$inventory" --list \
  | IP="$HOST_IP" yq -p json -r '._meta.hostvars | to_entries | .[] | select(.value.ansible_host == strenv(IP)) | .key')
[ -n "$self" ] || { echo "no inventory host has ansible_host ${HOST_IP} (node ${NODE_NAME})"; exit 1; }

# The same playbooks, in the same order, that CI's converge set ran. Every one runs;
# the phase fails if any did.
converge() {
  failed=""
  for pb in ansible/k8s/kubelet-provision.yml ansible/k8s/provision-hosts.yml ansible/services/wazuh-agent.yaml; do
    echo "== ${pb} --limit $1"
    ansible-playbook -i "$inventory" "$pb" --limit "$1" || failed="${failed} ${pb}"
  done
  [ -z "$failed" ] || { echo "failed:${failed}"; return 1; }
}

case "$CONVERGE_PHASE" in
  control-plane)
    converge "k8s_master:!${self}"

    # Hand off to a node this run just converged (every control-plane node but this
    # one); the Job is the CronJob's own template with the phase and pinning changed.
    handoff="${CRONJOB_NAME}-handoff-$(date -u +%Y%m%d%H%M%S)"
    kubectl create job "$handoff" --from="cronjob/${CRONJOB_NAME}" --dry-run=client -o yaml \
      | SELF="$self" NODES="$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[*].metadata.name}')" EXCLUDE="$NODE_NAME" yq '
          (.spec.template.spec.containers[0].env[] | select(.name == "CONVERGE_PHASE") | .value) = "handoff"
          | .spec.template.spec.containers[0].env += [{"name": "HANDOFF_HOST", "value": strenv(SELF)}]
          | .spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms = [{
              "matchExpressions": [{"key": "kubernetes.io/hostname", "operator": "In",
                "values": (strenv(NODES) | split(" ") | map(select(. != strenv(EXCLUDE))))}]}]' \
      | kubectl apply -f -
    echo "fired ${handoff} for ${self} and the workers"

    # Succeed only once the hand-off is actually running.
    i=0
    until [ "$(kubectl get pods -l "job-name=${handoff}" -o jsonpath='{.items[0].status.phase}' 2>/dev/null)" = Running ]; do
      i=$((i + 1))
      [ "$i" -le 120 ] || { echo "${handoff} did not start within 10 minutes"; exit 1; }
      sleep 5
    done
    echo "${handoff} is running"
    ;;
  handoff)
    : "${HANDOFF_HOST:?}"
    converge "${HANDOFF_HOST},k8s_worker"
    ;;
  *)
    echo "unknown CONVERGE_PHASE ${CONVERGE_PHASE}"; exit 1
    ;;
esac
