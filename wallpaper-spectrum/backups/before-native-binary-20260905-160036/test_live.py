"""Isolated PipeWire-to-GPU test; never changes the user's default sink."""
import json, math, os, signal, struct, subprocess as sp, time
from pathlib import Path
from PySide6.QtGui import QImage

def difference_bbox(a, b):
    a = a.convertToFormat(QImage.Format_RGB888)
    b = b.convertToFormat(QImage.Format_RGB888)
    assert a.size() == b.size()
    left, top, right, bottom = a.width(), a.height(), -1, -1
    for y in range(a.height()):
        aa, bb = bytes(a.constScanLine(y)[:a.width()*3]), bytes(b.constScanLine(y)[:b.width()*3])
        if aa == bb: continue
        xs = [i//3 for i, (x,z) in enumerate(zip(aa,bb)) if x != z]
        left, right = min(left,min(xs)), max(right,max(xs))
        top, bottom = min(top,y), y
    return None if right < 0 else (left,top,right+1,bottom+1)

B = Path(__file__).resolve().parent
OUT = B / 'verification'
OUT.mkdir(exist_ok=True)
def run(*args):
    return sp.check_output(args, text=True).strip()
def ipc(method):
    return run('quickshell','ipc','-p',str(B),'call','spectrum',method)
def ipc_json(method, timeout=5):
    deadline=time.monotonic()+timeout
    last=''
    while time.monotonic()<deadline:
        result=sp.run(['quickshell','ipc','-p',str(B),'call','spectrum',method],capture_output=True,text=True)
        last=result.stdout.strip()
        if last:
            try: return json.loads(last)
            except json.JSONDecodeError: pass
        time.sleep(0.1)
    raise AssertionError(('IPC did not return JSON',method,last))
def screenshot(name):
    sp.run(['grim','-o','HDMI-A-1',str(OUT / name)],check=True)
def ticks(pid):
    try:
        fields=Path(f'/proc/{pid}/stat').read_text().split(') ')[1].split()
        return int(fields[11])+int(fields[12])
    except FileNotFoundError: return 0
existing = sp.run(['quickshell','ipc','-p',str(B),'call','spectrum','status'], capture_output=True)
if existing.returncode == 0:
    raise SystemExit('Stop the live spectrum profile before this isolated test; refusing to measure the wrong instance.')
module=run('pactl','load-module','module-null-sink','sink_name=hk47_spectrum_test')
proc=None
try:
    env=dict(os.environ,
             SPECTRUM_SINK='hk47_spectrum_test',
             QML_IMPORT_PATH=str(B / 'qml'),
             DRI_PRIME='pci-0000_03_00_0',
             MESA_VK_DEVICE_SELECT='1002:747e',
             VK_DRIVER_FILES='/usr/share/vulkan/icd.d/radeon_icd.json',
             __EGL_VENDOR_LIBRARY_FILENAMES='/usr/share/glvnd/egl_vendor.d/50_mesa.json',
             CUDA_VISIBLE_DEVICES='')
    with (OUT/'quickshell.log').open('w') as log:
        proc=sp.Popen(['quickshell','--no-color','-p',str(B)],env=env,stdout=log,stderr=sp.STDOUT,start_new_session=True)
        time.sleep(2)
        assert proc.poll() is None, 'Quickshell failed to start'
        before=ipc_json('status')
        assert before['rejected']==0 and before['peak']==0, before
        assert before['bins'] == 640 and before['frameRate'] == 24
        screenshot('silent.png')
        pids=[proc.pid]
        def descendants(pid):
            try: children=Path(f'/proc/{pid}/task/{pid}/children').read_text().split()
            except FileNotFoundError: return
            for child in children:
                pids.append(int(child)); descendants(int(child))
        descendants(proc.pid)
        idle0={p:ticks(p) for p in pids}
        idle_start=time.monotonic()
        time.sleep(4)
        idle_elapsed=time.monotonic()-idle_start
        idle_cpu={str(p):round((ticks(p)-idle0[p])/os.sysconf('SC_CLK_TCK')/idle_elapsed*100,2) for p in pids}
        # Continuously varied level gives every frame distinct geometry.
        data=bytearray()
        for i in range(48000*12):
            t=i/48000
            amp=0.14+0.12*math.sin(2*math.pi*0.7*t)
            v=amp*(math.sin(2*math.pi*220*t)+0.4*math.sin(2*math.pi*440*t))
            data.extend(struct.pack('<ff',v,v))
        audio=OUT/'signal.f32'
        audio.write_bytes(data)
        cpu0={p:ticks(p) for p in pids}
        ipc('measure')
        start=time.monotonic()
        player=sp.Popen(['pw-play','--target','hk47_spectrum_test','--raw','--format','f32','--rate','48000','--channels','2',str(audio)])
        time.sleep(3)
        active=ipc_json('status')
        assert active['peak']>0.05 and active['rejected']==0, active
        frame_delta=active['frames']-before['frames']
        assert active['frameRate'] == 24
        screenshot('active.png')
        time.sleep(6)
        elapsed=time.monotonic()-start
        measured=ipc_json('results')
        cpu={str(p):round((ticks(p)-cpu0[p])/os.sysconf('SC_CLK_TCK')/elapsed*100,2) for p in pids}
        player.wait(timeout=10)
        time.sleep(2)
        end=ipc_json('status')
        assert end['peak']<0.001, end
        screenshot('released.png')
        base=QImage(str(OUT/'silent.png'))
        active_img=QImage(str(OUT/'active.png'))
        released=QImage(str(OUT/'released.png'))
        bbox=difference_bbox(base,active_img)
        assert bbox and bbox[1]>=base.height()//2-2, ('Unexpected shading bounds',bbox)
        assert difference_bbox(base,released) is None, 'Bars did not disappear after silence'
        stats={}
        for monitor, stamps in measured.items():
            # Remove startup; keep eight-second steady state.
            stamps=[x for x in stamps if x>=stamps[0]+1000]
            gaps=sorted(b-a for a,b in zip(stamps,stamps[1:]))
            fps=(len(stamps)-1)*1000/(stamps[-1]-stamps[0])
            stats[monitor]={'fps':round(fps,2),'p95_ms':gaps[int(len(gaps)*.95)],'max_ms':max(gaps),'frames':len(stamps)}
        assert len(stats)==2, stats
        assert all(22 <= v['fps'] <= 26 and v['p95_ms'] <= 60 for v in stats.values()), ('24 FPS target missed', stats)
        result={'before':before,'active':active,'released':end,'analyzer_frame_delta':frame_delta,'presentation':stats,'idle_cpu_percent_one_core':idle_cpu,'cpu_percent_one_core':cpu,'active_difference_bbox':bbox}
        (OUT/'results.json').write_text(json.dumps(result,indent=2))
        print(json.dumps(result,indent=2))
finally:
    if proc is not None:
        os.killpg(proc.pid,signal.SIGTERM)
        try: proc.wait(timeout=5)
        except sp.TimeoutExpired: os.killpg(proc.pid,signal.SIGKILL)
    sp.run(['pactl','unload-module',module],check=True)
