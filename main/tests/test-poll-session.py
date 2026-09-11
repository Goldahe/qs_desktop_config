import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

runner = Path(__file__).resolve().parents[1] / 'poll-session.py'
with tempfile.TemporaryDirectory() as d:
    folder = Path(d)
    pidfile = folder / 'pid'
    prefixes = ('quickshell-gpu-fdinfo.state', 'quickshell-storage.state')
    for prefix in prefixes:
        (folder / prefix).write_text('retained baseline')
        (folder / (prefix + f'.tmp.{os.getpid()}')).write_text('live writer')
    (folder / 'unrelated.tmp.123').write_text('preserve')
    code = 'import os,pathlib,time; p=pathlib.Path(os.environ["XDG_RUNTIME_DIR"]); [(p/(n+".tmp."+str(os.getpid()))).write_text("partial") for n in ("quickshell-gpu-fdinfo.state","quickshell-storage.state")]; (p/"pid").write_text(str(os.getpid())); time.sleep(60)'
    p = subprocess.Popen([sys.executable, str(runner), sys.executable, '-c', code], env=dict(os.environ, XDG_RUNTIME_DIR=d))
    try:
        for _ in range(100):
            if pidfile.exists(): break
            time.sleep(.02)
        assert pidfile.exists(), 'poll supervisor did not start child'
        child = int(pidfile.read_text())
        p.terminate()
        p.wait(timeout=4)
        assert not Path(f'/proc/{child}').exists(), f'orphan child {child}'
        for prefix in prefixes:
            assert not (folder / (prefix + f'.tmp.{child}')).exists(), 'abandoned sampler temporary file remains'
            assert (folder / prefix).read_text() == 'retained baseline'
            assert (folder / (prefix + f'.tmp.{os.getpid()}')).read_text() == 'live writer'
        assert (folder / 'unrelated.tmp.123').read_text() == 'preserve'
        print('supervisor SIGTERM: child reaped; abandoned temporary files removed; baselines/live writers/unrelated files preserved')
    finally:
        if p.poll() is None:
            p.terminate()
            p.wait(timeout=4)
