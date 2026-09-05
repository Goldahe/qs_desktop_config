"""Exercise native QProcess ownership, binary buffering, restart, and stop."""
import json
import os
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
import sys
import tempfile
from pathlib import Path
from PySide6.QtCore import QUrl, QObject
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

base = Path(__file__).resolve().parent
with tempfile.TemporaryDirectory() as directory:
    temp = Path(directory)
    starts = temp / "starts"
    helper = temp / "capture-helper.py"
    helper.write_text('''#!/usr/bin/env python3
import os, struct, sys, time
from pathlib import Path
marker = Path(os.environ["STARTS_FILE"])
with marker.open("a") as stream:
    stream.write(os.environ.get("SPECTRUM_FRAME_RATE", "missing") + " " + str(os.getpid()) + "\\n")
frame = struct.pack("<640f", *([0.25] + [0.0] * 639))
sys.stdout.buffer.write(frame[:777]); sys.stdout.buffer.flush()
time.sleep(0.05)
sys.stdout.buffer.write(frame[777:]); sys.stdout.buffer.flush()
time.sleep(0.5)
''')
    helper.chmod(0o755)
    fixture = temp / "native-process.qml"
    fixture.write_text(f'''import QtQuick
import HkSpectrum.Native 1.0 as Native
Item {{
    Native.SpectrumModel {{
        id: model
        objectName: "model"
        captureCommand: [{json.dumps(str(helper))}]
        frameRate: 37
        running: true
    }}
}}
''')
    os.environ["STARTS_FILE"] = str(starts)
    app = QGuiApplication(sys.argv)
    view = QQuickView()
    view.engine().addImportPath(str(base / "qml"))
    view.setSource(QUrl.fromLocalFile(str(fixture)))
    QTest.qWait(200)
    assert view.status() == QQuickView.Ready
    model = view.rootObject().findChild(QObject, "model")
    assert model is not None
    assert model.property("frames") == 1
    assert abs(model.property("peak") - 0.25) < 1e-6
    first = starts.read_text().splitlines()
    assert len(first) == 1 and first[0].split()[0] == "37", first
    first_pid = int(first[0].split()[1])
    QTest.qWait(500)
    assert not Path('/proc', str(first_pid)).exists(), 'exited capture helper was not reaped'

    QTest.qWait(2200)
    second = starts.read_text().splitlines()
    assert len(second) >= 2, second
    assert model.property("frames") >= 2
    assert model.setProperty("running", False)
    stopped_count = len(second)
    QTest.qWait(2300)
    assert len(starts.read_text().splitlines()) == stopped_count, 'disabled model restarted capture'
    assert model.property("running") is False
    view.close()
print("PASS native QProcess binary buffering, environment, restart, reaping, and stop")
