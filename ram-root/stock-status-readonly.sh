#!/bin/sh
# Prepared for a future explicitly reviewed on-device session. Not run here.
# Reads only fixed /proc files. No recordings, mounts, flash tools or settings.
set -f
show_file() {
    while IFS= read -r line || [ -n "$line" ]; do printf '%s\n' "$line"; done < "$1"
}
printf 'JARVIS_STOCK_PROBE_READONLY\n'
printf 'architecture='; /bin/busybox uname -m
printf 'kernel='; /bin/busybox uname -r
printf '\n[memory]\n'
while read -r key value unit; do
    case "$key" in
        MemTotal:|MemFree:|MemAvailable:|Buffers:|Cached:|SwapTotal:|SwapFree:)
            printf '%s %s %s\n' "$key" "$value" "$unit" ;;
    esac
done < /proc/meminfo
printf '\n[mtd]\n'
if [ -r /proc/mtd ]; then show_file /proc/mtd; fi
printf '\n[alsa_cards]\n'
if [ -r /proc/asound/cards ]; then show_file /proc/asound/cards; fi
printf '\n[alsa_pcm]\n'
if [ -r /proc/asound/pcm ]; then show_file /proc/asound/pcm; fi
printf '\n[sdio_identity_only]\n'
sdio_count=0
set +f
for device in /sys/bus/sdio/devices/*; do
    [ -d "$device" ] || continue
    sdio_count=$((sdio_count + 1))
    [ "$sdio_count" -le 16 ] || break
    printf 'sdio_device=%s\n' "${device##*/}"
    for field in vendor device class; do
        [ -r "$device/$field" ] || continue
        IFS= read -r value < "$device/$field"
        case "$value" in
            ''|*[!0-9a-fA-FxX]*) printf '%s=invalid\n' "$field" ;;
            *) printf '%s=%s\n' "$field" "$value" ;;
        esac
    done
done
set -f
printf 'sdio_functions=%s\n' "$sdio_count"
printf '\n[slot_and_root_arguments]\n'
if [ -r /proc/cmdline ]; then
    read -r cmdline < /proc/cmdline
    for argument in $cmdline; do
        case "$argument" in slot_suffix=*|root=*|rootfstype=*|ubi.mtd=*) printf '%s\n' "$argument" ;; esac
    done
fi
printf '\n[end]\n'
