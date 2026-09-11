#!/usr/bin/env python3
import json
import os
import subprocess
import time

STATE = os.path.join(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"), "quickshell-storage.state")

def clean(value):
    return str(value or "").replace("|", "/").replace("\n", " ").strip()

def size_text(value):
    try:
        n = int(value)
    except (TypeError, ValueError):
        return "N/A"
    units = ("B", "KB", "MB", "GB", "TB")
    i = 0
    f = float(n)
    while f >= 1000 and i < len(units) - 1:
        f /= 1000
        i += 1
    return f"{f:.0f}" if i == 0 else f"{f:.1f} {units[i]}"

def flatten(devices, parent=None):
    result = []
    for dev in devices:
        kind = dev.get("type", "")
        if kind in ("disk", "part", "rom"):
            item = dict(dev)
            item["parent_model"] = parent.get("model", "") if parent else ""
            item["parent_name"] = parent.get("name", "") if parent else ""
            result.append(item)
        result.extend(flatten(dev.get("children", []) or [], dev if kind == "disk" else parent))
    return result

def mount_map():
    mounts = {}
    try:
        with open("/proc/self/mountinfo", encoding="utf-8", errors="replace") as stream:
            for line in stream:
                left, _, right = line.partition(" - ")
                fields = left.split()
                if len(fields) < 6:
                    continue
                major_minor = fields[2]
                mountpoint = fields[4].replace("\\040", " ").replace("\\011", "\t")
                right_fields = right.split()
                filesystem = right_fields[0] if right_fields else ""
                source = right_fields[1] if len(right_fields) > 1 else ""
                entry = (mountpoint, filesystem)
                mounts.setdefault(major_minor, []).append(entry)
                # Btrfs and similar filesystems expose 0:major in mountinfo
                # while naming the real block device after the separator.
                if source.startswith("/dev/"):
                    mounts.setdefault(source, []).append(entry)
    except OSError:
        pass
    return mounts

def process_io():
    result = {}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        path = os.path.join("/proc", entry, "io")
        try:
            values = {}
            with open(path, encoding="ascii", errors="replace") as stream:
                for line in stream:
                    key, _, value = line.partition(":")
                    if key in ("read_bytes", "write_bytes", "syscr", "syscw"):
                        values[key] = int(value.strip())
            if values:
                result[int(entry)] = values
        except (OSError, ValueError, PermissionError):
            continue
    return result

def process_info(pid):
    try:
        with open(f"/proc/{pid}/stat", encoding="utf-8", errors="replace") as stream:
            stat = stream.read()
        close = stat.rfind(")")
        name = stat[stat.find("(") + 1:close]
        fields = stat[close + 2:].split()
        state = fields[0]
        with open(f"/proc/{pid}/cmdline", "rb") as stream:
            command = stream.read().replace(b"\0", b" ").decode(errors="replace").strip()
        return name, state, command or name
    except (OSError, ValueError):
        return None

def open_targets(pid):
    targets = []
    try:
        for fd in os.listdir(f"/proc/{pid}/fd"):
            try:
                targets.append(os.readlink(f"/proc/{pid}/fd/{fd}"))
            except OSError:
                pass
    except OSError:
        pass
    return targets

def main():
    try:
        raw = subprocess.check_output(
            ["lsblk", "-J", "-b", "-o", "NAME,PATH,TYPE,SIZE,MODEL,TRAN,ROTA,RM,MOUNTPOINT,FSTYPE"],
            stderr=subprocess.DEVNULL,
            text=True,
        )
        devices = flatten(json.loads(raw).get("blockdevices", []))
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError):
        devices = []

    mounts = mount_map()
    for index, device in enumerate(devices):
        path = device.get("path") or ("/dev/" + device.get("name", ""))
        try:
            stat = os.stat(path)
            major_minor = f"{os.major(stat.st_rdev)}:{os.minor(stat.st_rdev)}"
        except (OSError, ValueError):
            major_minor = ""
        mount_entries = mounts.get(major_minor, []) + mounts.get(path, [])
        mount_entries = list(dict.fromkeys(mount_entries))
        if not mount_entries:
            continue
        device["mount_entries"] = mount_entries
        device["index"] = index
        device["path"] = path
        model = device.get("model") or device.get("parent_model") or ""
        device["display"] = clean(model) or clean(device.get("name")) or path
        print("STORAGE|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}".format(
            index, clean(device["display"]), clean(device.get("name")), clean(path),
            clean(device.get("type")), size_text(device.get("size")), clean(device.get("tran")) or "N/A",
            bool(device.get("rota")) and "HDD" or "SSD/Flash",
            ", ".join(clean(m[0]) for m in mount_entries) or "Unmounted",
            clean(device.get("fstype")) or "N/A",
        ))

    now = time.time_ns()
    previous = {}
    try:
        with open(STATE, encoding="ascii") as stream:
            for line in stream:
                pid, read_b, write_b, syscr, syscw, timestamp = line.rstrip().split("|")
                previous[int(pid)] = (int(read_b), int(write_b), int(syscr), int(syscw), int(timestamp))
    except (OSError, ValueError):
        pass

    current = process_io()
    state_tmp = STATE + f".tmp.{os.getpid()}"
    output_state = []
    device_processes = {}
    for pid, values in current.items():
        old = previous.get(pid)
        if old:
            elapsed = (now - old[4]) / 1_000_000_000
            read_rate = max(0, values.get("read_bytes", 0) - old[0]) / elapsed if elapsed > 0 else 0
            write_rate = max(0, values.get("write_bytes", 0) - old[1]) / elapsed if elapsed > 0 else 0
        else:
            read_rate = write_rate = 0
        output_state.append(f"{pid}|{values.get('read_bytes', 0)}|{values.get('write_bytes', 0)}|{values.get('syscr', 0)}|{values.get('syscw', 0)}|{now}\n")
        old_syscalls = (old[2], old[3]) if old else (values.get("syscr", 0), values.get("syscw", 0))
        syscr_delta = max(0, values.get("syscr", 0) - old_syscalls[0])
        syscw_delta = max(0, values.get("syscw", 0) - old_syscalls[1])
        if read_rate <= 0 and write_rate <= 0 and syscr_delta <= 0 and syscw_delta <= 0:
            continue
        info = process_info(pid)
        if not info:
            continue
        name, state, command = info
        targets = open_targets(pid)
        for device in devices:
            mountpoints = [m[0] for m in device.get("mount_entries", [])]
            path = device["path"]
            matched = any(target == path or target.startswith(path + " ") for target in targets)
            if not matched:
                for mountpoint in mountpoints:
                    if mountpoint == "/" or any(target.startswith(mountpoint.rstrip("/") + "/") for target in targets):
                        matched = True
                        break
            if matched:
                device_processes.setdefault(device["index"], []).append((read_rate, write_rate, pid, name, state, command))

    for index, rows in device_processes.items():
        rows.sort(key=lambda row: row[0] + row[1], reverse=True)
        for read_rate, write_rate, pid, name, state, command in rows[:20]:
            print("STORAGE_PROC|{}|{}|{}|{}|{}|{}|{}|{}|{}".format(
                index, pid, clean(name), f"{read_rate:.1f}", f"{write_rate:.1f}", clean(state), clean(command),
                size_text(read_rate) + "/s", size_text(write_rate) + "/s",
            ))

    try:
        with open(state_tmp, "w", encoding="ascii") as stream:
            stream.writelines(output_state)
        os.replace(state_tmp, STATE)
    except OSError:
        try:
            os.unlink(state_tmp)
        except OSError:
            pass

if __name__ == "__main__":
    main()
