#!/bin/sh
# BM64Recomp fatally exits if SDL cannot open an audio device, and its default (raw ALSA) fails
# on this PipeWire seat ("Host is down"). Route SDL through the PipeWire-pulse bridge instead.
export SDL_AUDIODRIVER=pulseaudio
cd "${HOME}/Applications/bm64recomp" && exec ./BM64Recompiled
