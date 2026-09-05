"""Validate native parsing, shared model, and 640-bin stripe mapping."""
import os
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
import sys
from pathlib import Path
from PySide6.QtCore import QUrl, QObject
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

base = Path(__file__).resolve().parent
fixture = base / "_render_test.qml"
fixture.write_text('''import QtQuick
import HkSpectrum.Native 1.0 as Native
Item {
    width: 2560; height: 100
    Native.SpectrumModel { id: model; objectName: "model" }
    Native.SpectrumBars {
        objectName: "bars"
        anchors.fill: parent
        model: model
        gain: 1
        effectOpacity: 1
        hueOffset: 0
    }
}
''')
app = QGuiApplication(sys.argv)
view = QQuickView()
view.engine().addImportPath(str(base / "qml"))
view.setSource(QUrl.fromLocalFile(str(fixture)))
QTest.qWait(100)
assert view.status() == QQuickView.Ready
root = view.rootObject()
model = root.findChild(QObject, "model")
bars = root.findChild(QObject, "bars")
assert model is not None and bars is not None

values = [0.0] * 640
values[0], values[1], values[639] = 0.25, 0.75, 0.5
line = ",".join(map(str, values))
assert model.consume(line) is True
assert model.property("binCount") == 640
assert model.property("frames") == 1
assert model.property("rejected") == 0
assert abs(model.property("peak") - 0.75) < 1e-6
assert model.property("lastFrame") > 0
assert bars.property("hasModel") is True

assert model.consume("1,2,3") is False
assert model.property("frames") == 1
assert model.property("rejected") == 1
assert model.consume(",".join(["nan"] + ["0"] * 639)) is False
assert model.property("rejected") == 2
model.clear()
assert model.property("peak") == 0
assert model.property("frames") == 1

assert [bars.binForStripe(i) for i in (0, 1, 638, 639, 640, 641, 1278, 1279)] == [0, 1, 638, 639, 639, 638, 1, 0]
assert [bars.physicalXForStripe(i, 2560) for i in (0, 1, 639, 640, 1279)] == [0, 2, 1278, 1280, 2558]
assert bars.physicalXForStripe(0, 1920) == 0
assert bars.physicalXForStripe(1, 1920) == 2
assert bars.physicalXForStripe(2, 1920) == 3
assert bars.physicalXForStripe(1279, 1920) == 1919
assert bars.binForStripe(-1) == -1 and bars.binForStripe(1280) == -1
print("PASS native parser/shared model and 640-bin renderer contract")
view.close()
fixture.unlink(missing_ok=True)
