#!/usr/bin/env bash
set -u

GPU="0000:05:00.0"
DEVICE="/sys/bus/pci/devices/$GPU"
DRIVER="unknown"

if [[ -L "$DEVICE/driver" ]]; then
    DRIVER="$(basename "$(readlink "$DEVICE/driver")")"
fi

case "$DRIVER" in
    vfio-pci) MODE="VFIO / VM" ;;
    nvidia) MODE="Arch / NVIDIA compute" ;;
    *) MODE="Unknown" ;;
esac

VM_STATE="$(virsh -c qemu:///system domstate win11-VFIO 2>/dev/null | tr -d '\r' || true)"
[[ -n "$VM_STATE" ]] || VM_STATE="unavailable"

if [[ "$DRIVER" == "nvidia" ]]; then
    NVIDIA_STATUS="RTX 2080 SUPER · host compute ready"
elif [[ "$DRIVER" == "vfio-pci" ]]; then
    NVIDIA_STATUS="Detached from Arch"
else
    NVIDIA_STATUS="Unavailable"
fi

NODES=()
for node in /dev/nvidia0 /dev/nvidiactl /dev/nvidia-uvm /dev/dri/card0 /dev/dri/renderD129; do
    [[ -e "$node" ]] && NODES+=("$node")
done

HOLDER_COUNT=0
if ((${#NODES[@]})); then
    HOLDER_COUNT="$(fuser "${NODES[@]}" 2>/dev/null | tr ' ' '\n' | sed '/^$/d' | sort -u | wc -l)"
fi

printf 'MODE|%s\n' "$MODE"
printf 'DRIVER|%s\n' "$DRIVER"
printf 'VM|%s\n' "$VM_STATE"
printf 'NVIDIA|%s\n' "$NVIDIA_STATUS"
printf 'HOLDERS|%s user process%s\n' "$HOLDER_COUNT" "$([[ "$HOLDER_COUNT" == "1" ]] && printf '' || printf 'es')"
