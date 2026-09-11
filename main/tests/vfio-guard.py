import json, os, pathlib, subprocess, time, tempfile, shutil
root = pathlib.Path(__file__).resolve().parent
temporary = tempfile.TemporaryDirectory(prefix='qs-vfio-guard-')
folder = pathlib.Path(temporary.name)
shutil.copy2(root / 'vfio-guard.qml', folder / 'shell.qml')
for name in ['LifecycleSlot.qml', 'LifecyclePopup.qml', 'VfioPopup.qml', 'poll-session.py']:
    shutil.copy2(root.parent / name, folder / name)
config = str(folder / 'shell.qml')
env = dict(os.environ, DRI_PRIME='pci-0000_03_00_0', __EGL_VENDOR_LIBRARY_FILENAMES='/usr/share/glvnd/egl_vendor.d/50_mesa.json', VK_DRIVER_FILES='/usr/share/vulkan/icd.d/radeon_icd.json', LIBVA_DRIVER_NAME='radeonsi')
p = subprocess.Popen(['quickshell','--no-color','-p',config],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
def call(name):
    return subprocess.check_output(['quickshell','ipc','--pid',str(p.pid),'call','guard',name],text=True).strip()
try:
    for _ in range(100):
        if p.poll() is not None: raise AssertionError(p.stdout.read())
        try:
            s = json.loads(call('state'))
            break
        except (ValueError, subprocess.CalledProcessError): time.sleep(.05)
    call('fast')
    time.sleep(.3)
    assert not json.loads(call('state'))['busyGap'], 'Action became available before output finalization'
    call('close')
    time.sleep(.3)
    call('start')
    assert json.loads(call('state'))['busy']
    assert call('close') == 'false'
    call('nativeHide')
    s = json.loads(call('state'))
    assert s['live'] and s['visible'] and s['busy'], s
    time.sleep(1.5)
    s = json.loads(call('state'))
    assert not s['live'] and s['created'] == s['destroyed'] == 2, s
    print('VFIO benign sleep: close deferred, native hide restored, action exited, object destroyed',s)
    call('missing')
    time.sleep(.4)
    assert not json.loads(call('state'))['busy'], 'Failed-to-start action must not strand its owner'
    call('close')
    time.sleep(.3)
    s = json.loads(call('state'))
    assert not s['live'] and s['created'] == s['destroyed'] == 3, s
    print('Missing command recovered and owner destroyed', s)
finally:
    # Do not terminate a live action: this fixture's only action takes one second.
    time.sleep(1.2)
    p.terminate()
    p.wait(timeout=4)
    print(p.stdout.read())
