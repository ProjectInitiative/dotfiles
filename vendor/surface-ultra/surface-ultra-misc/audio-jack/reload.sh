#!/bin/bash
# Rebuild the sound card so the rt721-sdca module modprobe would pick now is the one in use.
# Stops the calling user's PipeWire while the card is down.
set -u
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
U=${SUDO_USER:-}; drv=/sys/bus/platform/drivers/mtk_sdw_mc
usr() { [ -n "$U" ] && runuser -u "$U" -- env XDG_RUNTIME_DIR=/run/user/$(id -u "$U") systemctl --user "$@"; }
usr stop pipewire.socket pipewire-pulse.socket pipewire pipewire-pulse wireplumber
[ -e $drv/mtk_sdw_mc ] && echo mtk_sdw_mc > $drv/unbind
sleep 1
rmmod snd_soc_rt721_sdca 2>/dev/null
modprobe snd_soc_rt721_sdca
sleep 2
echo mtk_sdw_mc > $drv/bind
sleep 2
usr start pipewire.socket pipewire-pulse.socket wireplumber pipewire pipewire-pulse
echo "rt721-sdca in use: $(modinfo -F filename snd_soc_rt721_sdca)"
grep -q mt8901 /proc/asound/cards && echo "OK: sound card is back" || { echo "!! sound card missing; see journalctl -k"; exit 1; }
