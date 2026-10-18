#!/bin/sh
# Converges the seat's ES-DE library onto the home volume from the mounted spec (/library):
#   systems.txt          "<es-de system> <folder under ROMS_SRC>" per line; ~/ROMs/<system> -> ROMS_SRC/<folder>
#   port-<Title>.sh      installed as ~/ROMs/ports/<Title>.sh with "_" shown as a space (ES-DE
#                        "ports" system; ConfigMap keys cannot hold spaces)
#   es_find_rules.xml    installed as ~/ES-DE/custom_systems/es_find_rules.xml
# System links and launchers no longer declared are removed; ROMS_SRC itself is never written.
set -eu
spec=/library
roms="${HOME}/ROMs"
mkdir -p "${roms}/ports" "${HOME}/ES-DE/custom_systems"

declared=" ports "
while read -r system folder; do
    case "${system}" in '' | '#'*) continue ;; esac
    declared="${declared}${system} "
    ln -sfn "${ROMS_SRC}/${folder}" "${roms}/${system}"
done <"${spec}/systems.txt"
for link in "${roms}"/*; do
    name="$(basename "${link}")"
    if [ -L "${link}" ] && [ "${declared#* "${name}" }" = "${declared}" ]; then
        rm -f "${link}"
    fi
done

for port in "${roms}"/ports/*.sh; do
    [ -e "${port}" ] || continue
    key="port-$(basename "${port}" | tr ' ' '_')"
    [ -e "${spec}/${key}" ] || rm -f "${port}"
done
for port in "${spec}"/port-*.sh; do
    [ -e "${port}" ] || continue
    title="$(basename "${port}" | sed 's/^port-//' | tr '_' ' ')"
    install -m 0755 "${port}" "${roms}/ports/${title}"
done

if [ -e "${spec}/es_find_rules.xml" ]; then
    install -m 0644 "${spec}/es_find_rules.xml" "${HOME}/ES-DE/custom_systems/es_find_rules.xml"
fi
echo "library: $(ls "${roms}" | tr '\n' ' ')"
