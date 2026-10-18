#!/bin/bash
# Converges the seat's user Flatpak apps from the mounted spec (/library/flatpaks.txt). Runs on
# the seat image, which carries flatpak but not Ansible, so it holds Ansible's contract itself:
# converge to the declared state, touch only declared apps (anything installed by hand from
# the desktop is left alone), report one result per app, and never fail the pod.
#   "<app-id>"            installed and kept at Flathub stable's latest signed commit
#   "<app-id> <commit>"   installed and held at that exact signed commit (masked against updates)
# Result per app: installed | updated | pinned | unchanged | failed.
set -uo pipefail
spec=/library/flatpaks.txt
fp() {
    local cmd="$1"
    shift
    case "${cmd}" in
    install | update | uninstall) flatpak "${cmd}" --user --noninteractive "$@" ;;
    *) flatpak "${cmd}" --user "$@" ;;
    esac
}
commit_of() { fp info --show-commit "$1" 2>/dev/null; }
# Network operations get four attempts, 5s apart, so a transient DNS or mirror failure does not
# skip an app until the next boot.
retry() {
    local n
    for n in 1 2 3 4; do
        "$@" && return 0
        [[ $n -lt 4 ]] && sleep 5
    done
    return 1
}
declare -A tally=()
result() {
    tally[$2]=$((${tally[$2]:-0} + 1))
    echo "flatpak: $1 $2${3:+ ($3)}"
}

if ! retry fp remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo; then
    echo "flatpak: flathub remote unavailable; keeping installed apps"
    exit 0
fi

while read -r app want; do
    case "${app}" in '' | '#'*) continue ;; esac
    before="$(commit_of "${app}")"
    if [[ -z "${before}" ]]; then
        retry fp install flathub "${app}" >/dev/null || { result "${app}" failed "install"; continue; }
    fi
    if [[ -n "${want:-}" ]]; then
        if [[ "$(commit_of "${app}")" != "${want}" ]]; then
            fp mask --remove "${app}" >/dev/null 2>&1
            retry fp update --commit="${want}" "${app}" >/dev/null || { result "${app}" failed "pin ${want:0:12}"; continue; }
        fi
        fp mask "${app}" >/dev/null 2>&1
    else
        retry fp update "${app}" >/dev/null || { result "${app}" failed "update; kept ${before:0:12}"; continue; }
    fi
    after="$(commit_of "${app}")"
    if [[ -z "${before}" ]]; then
        result "${app}" installed "${after:0:12}"
    elif [[ "${before}" == "${after}" ]]; then
        result "${app}" unchanged "${after:0:12}"
    elif [[ -n "${want:-}" ]]; then
        result "${app}" pinned "${after:0:12}"
    else
        result "${app}" updated "${before:0:12} -> ${after:0:12}"
    fi
done <"${spec}"

fp uninstall --unused >/dev/null 2>&1
summary=""
for k in installed updated pinned unchanged failed; do summary+=" ${k}=${tally[$k]:-0}"; done
echo "flatpak:${summary}"
exit 0
