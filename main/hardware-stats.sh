#!/usr/bin/env bash

sampling_mode="${1:-full}"
fast_mode=0
[ "$sampling_mode" = "fast" ] && fast_mode=1

# Emit one machine-readable GPU record for every DRM card.
# Fields: GPU|index|PCI address|name|load|temperature|used|total|percent|power
printf 'CPU_LOAD '
top -bn1 2>/dev/null | awk -F',' '/Cpu\(s\)/ {for (i=1; i<=NF; i++) if ($i ~ / id/) {gsub(/[^0-9.]/, "", $i); print 100 - $i; exit}}'
printf 'CPU_CORES '; getconf _NPROCESSORS_ONLN 2>/dev/null
printf 'CPU_NAME '; awk -F: '/model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo

# Emit the busiest processes with enough context for the CPU details table.
# Fields: PROC|pid|name|cpu|mem|state|elapsed|user|rss|vsz|nice|ni|tty|state|command
ps -eo pid=,comm=,%cpu=,%mem=,stat=,etime=,user=,rss=,vsz=,nice=,ni=,tty=,state=,args= --sort=-%cpu 2>/dev/null |
    awk 'NR <= 21 {
        pid=$1; name=$2; cpu=$3; mem=$4; stat=$5; elapsed=$6; user=$7;
        rss=$8; vsz=$9; nice=$10; ni=$11; tty=$12; state=$13;
        command=""; for (i=14; i<=NF; i++) command=command (i == 14 ? "" : " ") $i;
        gsub(/\|/, "/", command);
        printf "PROC|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n", pid, name, cpu, mem, stat, elapsed, user, rss, vsz, nice, ni, tty, state, command;
    }'

# Emit a separate memory-ranked snapshot for the RAM details table.
# Fields: RAM_PROC|pid|name|mem|rss|vsz|cpu|user|stat|elapsed|command
ps -eo pid=,comm=,%mem=,rss=,vsz=,%cpu=,user=,stat=,etime=,args= --sort=-%mem 2>/dev/null |
    awk 'NR <= 21 {
        pid=$1; name=$2; mem=$3; rss=$4; vsz=$5; cpu=$6; user=$7;
        stat=$8; elapsed=$9; command="";
        for (i=10; i<=NF; i++) command=command (i == 10 ? "" : " ") $i;
        gsub(/\|/, "/", command);
        printf "RAM_PROC|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n", pid, name, mem, rss, vsz, cpu, user, stat, elapsed, command;
    }'

# Query lm-sensors once and reuse the snapshot for all temperature fields.
sensor_data=$(sensors 2>/dev/null)
printf 'CPU_TEMP '; printf '%s\n' "$sensor_data" | awk '/Package id 0:/ {print $4; exit}'

# Intel RAPL exposes package energy, so derive CPU package watts between samples.
rapl_energy_file=''
rapl_name_file=''
for candidate in /sys/class/powercap/intel-rapl:*/energy_uj; do
    name_file="${candidate%/energy_uj}/name"
    if [ -r "$name_file" ] && [ "$(cat "$name_file")" = "package-0" ]; then
        rapl_energy_file="$candidate"
        rapl_name_file="$name_file"
        break
    fi
done
cpu_power='N/A'
power_state_file="${XDG_RUNTIME_DIR:-/run/user/$UID}/quickshell-cpu-power.state"
if [ -r "$rapl_energy_file" ]; then
    now_ns=$(date +%s%N)
    energy_uj=$(cat "$rapl_energy_file")
    if [ -r "$power_state_file" ]; then
        IFS='|' read -r old_energy old_time < "$power_state_file"
        cpu_power=$(awk -v e="$energy_uj" -v oe="$old_energy" -v now="$now_ns" -v old="$old_time" \
            'BEGIN {if (e ~ /^[0-9]+$/ && oe ~ /^[0-9]+$/ && now > old && e >= oe) printf "%.1f W", ((e-oe)/1000000)/((now-old)/1000000000); else print "N/A"}')
    fi
    printf '%s|%s\n' "$energy_uj" "$now_ns" > "${power_state_file}.tmp.$$"
    mv -f "${power_state_file}.tmp.$$" "$power_state_file"
fi
printf 'CPU_POWER %s\n' "$cpu_power"

# Cache NVIDIA telemetry by PCI address when the proprietary utility is available.
declare -A NVIDIA_LOAD NVIDIA_TEMP NVIDIA_USED NVIDIA_TOTAL NVIDIA_POWER NVIDIA_PROC_MEMORY
has_nvidia=0
for card in /sys/class/drm/card[0-9]; do
    [ -e "$card/device/driver" ] || continue
    driver=$(basename "$(readlink -f "$card/device/driver")")
    [ "$driver" = "nvidia" ] && has_nvidia=1
done
if [ "$has_nvidia" -eq 1 ]; then
    while IFS=',' read -r bus load used total temp power; do
        bus=${bus// /}
        bus=${bus#00000000:}
        NVIDIA_LOAD["$bus"]=${load// /}
        NVIDIA_USED["$bus"]=${used// /}
        NVIDIA_TOTAL["$bus"]=${total// /}
        NVIDIA_TEMP["$bus"]=${temp// /}
        NVIDIA_POWER["$bus"]=${power// /}
    done < <(nvidia-smi --query-gpu=pci.bus_id,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw --format=csv,noheader,nounits 2>/dev/null)
    # Compute clients may not open a DRM node; collect their actual allocated VRAM.
    while IFS=',' read -r pid used; do
        pid=${pid// /}
        used=${used// /}
        [ -n "$pid" ] && [ -n "$used" ] && NVIDIA_PROC_MEMORY["$pid"]="$used MiB"
    done < <(nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader,nounits 2>/dev/null)
fi

idx=0
gpu_power_total=0
gpu_power_valid=0
for card in /sys/class/drm/card[0-9]; do
    [ -e "$card/device" ] || continue
    dev=$(readlink -f "$card/device")
    pci=$(basename "$dev")
    pci_short=${pci#0000:}
    name=$(lspci -s "$pci" 2>/dev/null | sed 's/^[^ ]* //' | sed 's/ \[[^]]*\]$//')
    [ -n "$name" ] || name="GPU $idx"
    load="N/A"; temp="N/A"; used="N/A"; total="N/A"; percent="N/A"; power="N/A"

    if [ -n "${NVIDIA_LOAD[$pci_short]:-}" ]; then
        load="${NVIDIA_LOAD[$pci_short]}%"
        temp="${NVIDIA_TEMP[$pci_short]}°C"
        used="${NVIDIA_USED[$pci_short]} MiB"
        total="${NVIDIA_TOTAL[$pci_short]} MiB"
        [ -n "${NVIDIA_POWER[$pci_short]:-}" ] && power="${NVIDIA_POWER[$pci_short]} W"
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
            power=$(awk -v microwatts="$(cat "$card/device/hwmon"/hwmon*/power1_average 2>/dev/null | head -n1)" 'BEGIN {if (microwatts ~ /^[0-9]+$/) printf "%.1f W", microwatts / 1000000; else print "N/A"}')
        fi
        # Match the amdgpu sensor block for the AMD card when available.
        temp=$(printf '%s\n' "$sensor_data" | awk '/amdgpu-pci/{found=1} found && /^edge:/{print $2; exit}')
        [ -n "$temp" ] || temp="N/A"
    fi
    if [[ "$power" =~ ^[0-9]+([.][0-9]+)?[[:space:]]W$ ]]; then
        power_number=${power% W}
        gpu_power_total=$(awk -v total="$gpu_power_total" -v value="$power_number" 'BEGIN {printf "%.6f", total + value}')
        gpu_power_valid=$((gpu_power_valid + 1))
    fi
    printf 'GPU|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' "$idx" "$pci" "$name" "$load" "$temp" "$used" "$total" "$percent" "$power"
    idx=$((idx + 1))
done

# Emit all discoverable processes for each GPU. NVIDIA's process monitor covers
# CUDA/graphics clients that do not hold a /dev/dri handle; fuser covers DRM.
# Fields: GPU_PROC|gpu-index|pid|name|gpu-load|cpu|mem|user|rss|vsz|stat|elapsed|command|gpu-memory
gpu_idx=0
if [ "$fast_mode" -eq 1 ]; then
    # The overview has no process table. Skipping this fdinfo/fuser walk keeps
    # the one-shot sampler below the requested one-second refresh cadence.
    gpu_idx="$idx"
else
declare -a nvidia_card_indices=()
card_idx=0
for card in /sys/class/drm/card[0-9]; do
    [ -e "$card/device/driver" ] || continue
    driver=$(basename "$(readlink -f "$card/device/driver")")
    [ "$driver" = "nvidia" ] && nvidia_card_indices+=("$card_idx")
    card_idx=$((card_idx + 1))
done

# amdgpu exposes per-process engine counters through DRM fdinfo. Keep the
# previous counter snapshot across the one-second helper invocations.
state_file="${XDG_RUNTIME_DIR:-/run/user/$UID}/quickshell-gpu-fdinfo.state"
declare -A previous_engine previous_time
if [ -r "$state_file" ]; then
    while IFS='|' read -r state_gpu state_pid total timestamp; do
        key="$state_gpu|$state_pid"
        [ -n "$state_gpu" ] && previous_engine["$key"]="$total" && previous_time["$key"]="$timestamp"
    done < "$state_file"
fi
state_tmp="${state_file}.tmp.$$"
: > "$state_tmp"

amd_process_load() {
    local pid="$1" dev="$2" gpu_idx="$3" now total=0 client engine value key old old_time delta_ns delta_ms percent
    declare -A clients
    for fdinfo in /proc/"$pid"/fdinfo/*; do
        [ -r "$fdinfo" ] || continue
        [ "$(awk -F'\t' '/^drm-pdev:/{print $2; exit}' "$fdinfo" 2>/dev/null)" = "$(basename "$dev")" ] || continue
        client=$(awk -F'\t' '/^drm-client-id:/{print $2; exit}' "$fdinfo" 2>/dev/null)
        [ -n "$client" ] || continue
        while read -r engine value; do
            [ -n "$engine" ] || continue
            key="$gpu_idx|$pid|$client|$engine"
            [ -n "${clients[$key]:-}" ] && continue
            clients["$key"]=1
            total=$((total + value))
        done < <(awk -F'[: ]+' '/^drm-engine-/{gsub(/[[:space:]]+/, " "); print $1, $2}' "$fdinfo" 2>/dev/null)
    done
    now=$(date +%s%N)
    key="$gpu_idx|$pid"
    old="${previous_engine[$key]:-}"
    old_time="${previous_time[$key]:-}"
    printf '%s|%s|%s\n' "$key" "$total" "$now" >> "$state_tmp"
    if [ -n "$old" ] && [ -n "$old_time" ] && [ "$total" -ge "$old" ] 2>/dev/null; then
        delta_ns=$((total - old))
        delta_ms=$(( (now - old_time) / 1000000 ))
        if [ "$delta_ms" -gt 0 ]; then
            percent=$(awk -v d="$delta_ns" -v t="$delta_ms" 'BEGIN {p=(d/(t*1000000))*100; if (p > 100) p=100; printf "%.1f", p}')
            amd_process_load_result="$percent"
            return
        fi
    fi
    amd_process_load_result="N/A"
}

# NVIDIA pmon reports active graphics and compute processes, including CUDA.
nvidia_pmon=''
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia_pmon=$(nvidia-smi pmon -c 1 -s um 2>/dev/null | awk '/^[[:space:]]*[0-9]+[[:space:]]+[0-9]+/ {print}')
fi
while read -r nvidia_index pid type gpu_load gpu_mem enc dec jpg ofa command; do
    [ -n "${pid:-}" ] || continue
    target_gpu="${nvidia_card_indices[$nvidia_index]:-}"
    [ -n "$target_gpu" ] || continue
    [ "$gpu_load" = "-" ] || [ -z "$gpu_load" ] && gpu_load="N/A"
    [ "$gpu_mem" = "-" ] || [ -z "$gpu_mem" ] && gpu_mem="N/A"
    read -r name cpu mem stat elapsed user rss vsz nice ni tty state full_command < <(
        ps -p "$pid" -o comm=,%cpu=,%mem=,stat=,etime=,user=,rss=,vsz=,nice=,ni=,tty=,state=,args= 2>/dev/null
    )
    [ -n "$name" ] || continue
    full_command=${full_command//|//}
    printf 'GPU_PROC|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
        "$target_gpu" "$pid" "$name" "${gpu_load:-N/A}" "${cpu:-N/A}" "${mem:-N/A}" "${user:-N/A}" \
        "${rss:-N/A}" "${vsz:-N/A}" "${stat:-N/A}" "${elapsed:-N/A}" "${full_command:-N/A}" "${NVIDIA_PROC_MEMORY[$pid]:-N/A}"
done <<< "$nvidia_pmon"

for card in /sys/class/drm/card[0-9]; do
    [ -e "$card/device" ] || continue
    dev=$(readlink -f "$card/device")
    driver=$(basename "$(readlink -f "$card/device/driver")")
    declare -A seen_gpu_pids=()
    nodes=("/dev/dri/$(basename "$card")")
    for render in /sys/class/drm/renderD*; do
        [ -e "$render/device" ] || continue
        [ "$(readlink -f "$render/device")" = "$dev" ] || continue
        nodes+=("/dev/dri/$(basename "$render")")
    done
    for node in "${nodes[@]}"; do
        [ -e "$node" ] || continue
        for pid in $(fuser -a "$node" 2>/dev/null | tr ' ' '\n' | awk '/^[0-9]+$/'); do
            [ -n "${seen_gpu_pids[$pid]:-}" ] && continue
            seen_gpu_pids[$pid]=1
            read -r name cpu mem stat elapsed user rss vsz nice ni tty state command < <(
                ps -p "$pid" -o comm=,%cpu=,%mem=,stat=,etime=,user=,rss=,vsz=,nice=,ni=,tty=,state=,args= 2>/dev/null
            )
            [ -n "$name" ] || continue
            command=${command//$'\n'/ }
            command=${command//|//}
            amd_process_load "$pid" "$dev" "$gpu_idx"
            process_vram="N/A"
            [ "$driver" = "nvidia" ] && process_vram="${NVIDIA_PROC_MEMORY[$pid]:-N/A}"
            printf 'GPU_PROC|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
                "$gpu_idx" "$pid" "$name" "${amd_process_load_result:-N/A}" "${cpu:-N/A}" "${mem:-N/A}" "${user:-N/A}" \
                "${rss:-N/A}" "${vsz:-N/A}" "${stat:-N/A}" "${elapsed:-N/A}" "${command:-N/A}" "$process_vram"
        done
    done
    unset seen_gpu_pids
    gpu_idx=$((gpu_idx + 1))
done

mv -f "$state_tmp" "$state_file"
fi

total_power='N/A'
total_power_value=0
total_power_valid=0
if [[ "$cpu_power" =~ ^[0-9]+([.][0-9]+)?[[:space:]]W$ ]]; then
    cpu_power_number=${cpu_power% W}
    total_power_value=$(awk -v total="$total_power_value" -v value="$cpu_power_number" 'BEGIN {printf "%.6f", total + value}')
    total_power_valid=$((total_power_valid + 1))
fi
if [ "$gpu_power_valid" -gt 0 ]; then
    total_power_value=$(awk -v total="$total_power_value" -v gpu="$gpu_power_total" 'BEGIN {printf "%.6f", total + gpu}')
    total_power_valid=$((total_power_valid + gpu_power_valid))
fi
if [ "$total_power_valid" -gt 0 ]; then
    total_power=$(awk -v total="$total_power_value" 'BEGIN {printf "%.1f W", total}')
fi
printf 'TOTAL_POWER %s\n' "$total_power"
printf 'GPU_COUNT %s\n' "$idx"
printf 'RAM '; free -b 2>/dev/null | awk '/^Mem:/ {printf "%d %d %.1f\n", $3, $2, ($3 / $2) * 100}'
printf 'STORAGE '; df -B1 --output=used,size,pcent / 2>/dev/null | awk 'NR==2 {gsub(/%/, "", $3); printf "%d %d %.1f\n", $1, $2, $3}'
printf 'STORAGE_TEMP '; printf '%s\n' "$sensor_data" | awk '/^nvme-pci-/{found=1} found && /^Composite:/{print $2; exit}'
printf 'NVME_SYSTEM '; df -B1 --output=used,size,pcent / 2>/dev/null | awk 'NR==2 {gsub(/%/, "", $3); printf "%d %d %.1f\n", $1, $2, $3}'
printf 'NVME_GAMES '; df -B1 --output=used,size,pcent /games 2>/dev/null | awk 'NR==2 {gsub(/%/, "", $3); printf "%d %d %.1f\n", $1, $2, $3}'
printf 'NVME_TOTAL '; df -B1 --output=used,size / /games 2>/dev/null | awk 'NR>1 {used += $1; size += $2} END {if (size > 0) printf "%d %d %.1f\n", used, size, (used/size)*100}'
printf 'NVME_TEMP2 '; printf '%s\n' "$sensor_data" | awk '/^nvme-pci-/{n++; found=(n==2)} found && /^Composite:/{print $2; exit}'
printf 'HDD '; lsblk -bndo SIZE,TYPE 2>/dev/null | awk '$2 == "disk" {sum += $1} END {if (sum > 0) print sum}'

# Emit discovered block devices and active per-device I/O processes.
if [ "$fast_mode" -eq 0 ]; then
    script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    python3 "$script_dir/storage-stats.py"
fi
