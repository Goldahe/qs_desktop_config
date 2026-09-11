#!/usr/bin/env python3
"""Supervise a read-only one-shot sampler; TERM kills/reaps its whole group.
Never wrap VFIO actions: those must finish, not be cancelled.
"""
import ctypes
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

# Adopt grandchildren so a killed shell cannot leave zombies behind.
ctypes.CDLL(None).prctl(36, 1, 0, 0, 0)  # PR_SET_CHILD_SUBREAPER
stopping = False

def stop(signum, frame):
    global stopping
    stopping = True

signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)
child = subprocess.Popen(sys.argv[1:], start_new_session=True)
while child.poll() is None and not stopping:
    time.sleep(.02)
# Reap remaining descendants even on natural completion.
try:
    os.killpg(child.pid, signal.SIGTERM)
except ProcessLookupError:
    pass
try:
    child.wait(timeout=.5)
except subprocess.TimeoutExpired:
    pass
try:
    os.killpg(child.pid, signal.SIGKILL)
except ProcessLookupError:
    pass
child.wait()
while True:
    try:
        os.waitpid(-1, 0)
    except ChildProcessError:
        break
# Atomic-write fragments are disposable only after their writer has exited.
# Retain complete baselines for continuity; never touch a live writer's file.
runtime = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}'))
for prefix in ('quickshell-gpu-fdinfo.state.tmp.', 'quickshell-storage.state.tmp.'):
    for fragment in runtime.glob(prefix + '*'):
        pid = fragment.name[len(prefix):]
        try:
            if pid.isdecimal() and not Path('/proc', pid).exists() and fragment.lstat().st_uid == os.getuid():
                fragment.unlink()
        except FileNotFoundError:
            pass
sys.exit(0 if stopping else child.returncode)
