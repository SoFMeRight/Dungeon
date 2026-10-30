#!/bin/sh
# rac-rs generates the game from the disc and builds it in place (toolchain, build, saves: ~7 GB),
# so it runs from the CephFS-HDD volume, not the capacity-bound home PVC. A new release (or the
# first run) is copied over that folder and rebuilt in a window, 10-30 min; saves in player/ stay.
# The disc image goes in /mnt/recomp-hdd/rac-rs/rom/: PAL SCES-50916 or USA SCUS-97199, v1.00.
src="${HOME}/Applications/rac-rs"
dir="/mnt/recomp-hdd/rac-rs"
if [ "$(cat "${dir}/.built-version" 2>/dev/null)" != "$(cat "${src}/VERSION")" ]; then
  mkdir -p "${dir}" && cp -a "${src}/." "${dir}/" || exit 1
  konsole --workdir "${dir}" -e sh -c 'sh ./setup.sh && cp VERSION .built-version'
  [ "$(cat "${dir}/.built-version" 2>/dev/null)" = "$(cat "${src}/VERSION")" ] || exit 1
fi
exec "${dir}/play.sh"
