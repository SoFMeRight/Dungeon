#!/bin/sh
# The home PVC is capacity-bound, so the recomp's built game, extracted files, saves, settings
# and shader caches go to the writable CephFS-HDD volume via XDG (the AppImage honours these).
# Game assets are read in place from the extracted title you select on first run — nothing copied.
export XDG_DATA_HOME="/mnt/recomp-hdd/data"
export XDG_CONFIG_HOME="/mnt/recomp-hdd/config"
mkdir -p "${XDG_DATA_HOME}" "${XDG_CONFIG_HOME}"
exec "${HOME}/Applications/WindWakerHD.AppImage"
