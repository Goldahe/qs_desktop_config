#!/usr/bin/env bash

# Emit one machine-readable GPU record for every DRM card.
# Fields: GPU|index|PCI address|name|load|temperature|used|total|percent
printf 'CPU_LOAD '
top -bn1 2>/dev/null | awk -F',' '/Cpu\(s\)/ {for (i=1; i<=NF; i++) if ($i ~ / id/) {gsub(/[^0-9.]/, "", $i); print 100 - $i; exit}}'
printf 'CPU_CORES '; getconf _NPROCESSORS_ONLN 2>/dev/null

# Query lm-sensors once and reuse the snapshot for all temperature fields.
sensor_data=$(sensors 2>/dev/null)
printf 'CPU_TEMP '; printf '%s\n' "$sensor_data" | awk '/Package id 0:/ {print $4; exit}'

# Cache NVIDIA telemetry by PCI address when the proprietary utility is available.
declare -A NVIDIA_LOAD NVIDIA_TEMP NVIDIA_USED NVIDIA_TOTAL
has_nvidia=0
for card in /sys/class/drm/card[0-9]; do
    [ -e "$card/device/driver" ] || continue
    driver=$(basename "$(readlink -f "$card/device/driver")")
    [ "$driver" = "nvidia" ] && has_nvidia=1
done
if [ "$has_nvidia" -eq 1 ]; then
    while IFS=',' read -r bus load used total temp; do
        bus=${bus// /}
        bus=${bus#00000000:}
        NVIDIA_LOAD["$bus"]=${load// /}
        NVIDIA_USED["$bus"]=${used// /}
        NVIDIA_TOTAL["$bus"]=${total// /}
        NVIDIA_TEMP["$bus"]=${temp// /}
    done < <(nvidia-smi --query-gpu=pci.bus_id,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>/dev/null)
fi

idx=0
for card in /sys/class/drm/card[0-9]; do
    [ -e "$card/device" ] || continue
    dev=$(readlink -f "$card/device")
    pci=$(basename "$dev")
    pci_short=${pci#0000:}
    name=$(lspci -s "$pci" 2>/dev/null | sed 's/^[^ ]* //' | sed 's/ \[[^]]*\]$//')
    [ -n "$name" ] || name="GPU $idx"
    load="N/A"; temp="N/A"; used="N/A"; total="N/A"; percent="N/A"

    if [ -n "${NVIDIA_LOAD[$pci_short]:-}" ]; then
        load="${NVIDIA_LOAD[$pci_short]}%"
        temp="${NVIDIA_TEMP[$pci_short]}°C"
        used="${NVIDIA_USED[$pci_short]} MiB"
        total="${NVIDIA_TOTAL[$pci_short]} MiB"
        if [ "${NVIDIA_TOTAL[$pci_short]}" -gt 0 ] 2>/dev/null; then
            percent=$(awk -v u="${NVIDIA_USED[$pci_short]}" -v t="${NVIDIA_TOTAL[$pci_short]}" 'BEGIN {printf "%.1f%%", (u/t)*100}')
        fi
    elif [ -r "$card/device/gpu_busy_percent" ]; then
        load="$(cat "$card/device/gpu_busy_percent")%"
        if [ -r "$card/device/mem_info_vram_used" ] && [ -r "$card/device/mem_info_vram_total" ]; then
            u=$(cat "$card/device/mem_info_vram_used")
            t=$(cat "$card/device/mem_info_vram_total")
            used=$(awk -v b="$u" 'BEGIN {printf "%.1f GiB", b/1024/1024/1024}')
            total=$(awk -v b="$t" 'BEGIN {printf "%.1f GiB", b/1024/1024/1024}')
            percent=$(awk -v u="$u" -v t="$t" 'BEGIN {if (t > 0) printf "%.1f%%", (u/t)*100; else print "N/A"}')
        fi
        # Match the amdgpu sensor block for the AMD card when available.
        temp=$(printf '%s\n' "$sensor_data" | awk '/amdgpu-pci/{found=1} found && /^edge:/{print $2; exit}')
        [ -n "$temp" ] || temp="N/A"
    fi
    printf 'GPU|%s|%s|%s|%s|%s|%s|%s|%s\n' "$idx" "$pci" "$name" "$load" "$temp" "$used" "$total" "$percent"
    idx=$((idx + 1))
done

printf 'GPU_COUNT %s\n' "$idx"
printf 'RAM '; free -b 2>/dev/null | awk '/^Mem:/ {printf "%d %d %.1f\n", $3, $2, ($3 / $2) * 100}'
printf 'STORAGE '; df -B1 --output=used,size,pcent / 2>/dev/null | awk 'NR==2 {gsub(/%/, "", $3); printf "%d %d %.1f\n", $1, $2, $3}'
printf 'STORAGE_TEMP '; printf '%s\n' "$sensor_data" | awk '/^nvme-pci-/{found=1} found && /^Composite:/{print $2; exit}'
printf 'NVME_SYSTEM '; df -B1 --output=used,size,pcent / 2>/dev/null | awk 'NR==2 {gsub(/%/, "", $3); printf "%d %d %.1f\n", $1, $2, $3}'
printf 'NVME_GAMES '; df -B1 --output=used,size,pcent /games 2>/dev/null | awk 'NR==2 {gsub(/%/, "", $3); printf "%d %d %.1f\n", $1, $2, $3}'
printf 'NVME_TOTAL '; df -B1 --output=used,size / /games 2>/dev/null | awk 'NR>1 {used += $1; size += $2} END {if (size > 0) printf "%d %d %.1f\n", used, size, (used/size)*100}'
printf 'NVME_TEMP2 '; printf '%s\n' "$sensor_data" | awk '/^nvme-pci-/{n++; found=(n==2)} found && /^Composite:/{print $2; exit}'
printf 'HDD '; lsblk -bndo SIZE,TYPE 2>/dev/null | awk '$2 == "disk" {sum += $1} END {if (sum > 0) print sum}'
