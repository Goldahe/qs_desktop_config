"""Validate native binary parsing, process ownership, shared model, and stripe mapping."""
import os
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
import struct
import sys
from pathlib import Path
from PySide6.QtCore import QByteArray, QFile, QUrl, QObject
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
    Native.WallpaperSpectrum {
        objectName: "wallpaperEffect"
        width: 2560; height: 1440
        model: model
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
wallpaper_effect = root.findChild(QObject, "wallpaperEffect")
assert model is not None and bars is not None and wallpaper_effect is not None
assert QFile.exists(":/hkspectrum/wallpaper.vert.qsb")
assert QFile.exists(":/hkspectrum/wallpaper.frag.qsb")
frame_signals = []
model.frameChanged.connect(lambda: frame_signals.append(True))

pack = lambda values: QByteArray(struct.pack('<640f', *values))
values = [0.0] * 640
values[0], values[1], values[639] = 0.25, 0.75, 0.5
frame = pack(values)
assert model.consumeFrame(frame) is True
assert model.property("binCount") == 640
assert model.property("frames") == 1
assert model.property("rejected") == 0
assert abs(model.property("peak") - 0.75) < 1e-6
assert model.property("lastFrame") > 0
assert bars.property("hasModel") is True
assert len(frame_signals) == 1
assert abs(bars.gradientOpacityAt(0.0) - 0.0) < 1e-6
assert abs(bars.gradientOpacityAt(0.5) - 0.4) < 1e-6
assert abs(bars.gradientOpacityAt(1.0) - 0.8) < 1e-6
assert abs(bars.barTopOpacity(1.0) - 0.0) < 1e-6
assert abs(bars.barTopOpacity(0.5) - 0.4) < 1e-6
assert abs(bars.barTopOpacity(0.25) - 0.6) < 1e-6
assert model.consumeFrame(frame) is True
assert len(frame_signals) == 1, "unchanged frame caused a renderer notification"
values[0] = 0.9
assert model.consumeFrame(pack(values)) is True
assert len(frame_signals) == 2
values = [0.0] * 640
values[0] = 0.01
assert model.consumeFrame(pack(values)) is True
assert len(frame_signals) == 2, "decay frame was not throttled"
QTest.qWait(130)
values[0] = 0.005
assert model.consumeFrame(pack(values)) is True
assert len(frame_signals) == 3, "decay notification was not released at idle cadence"
values[0] = 0.0
assert model.consumeFrame(pack(values)) is True
assert len(frame_signals) == 4, "zero frame was not delivered"

assert model.consumeFrame(QByteArray(b"short")) is False
assert model.property("frames") == 6
assert model.property("rejected") == 1
invalid = [0.0] * 640
invalid[0] = float('nan')
assert model.consumeFrame(pack(invalid)) is False
assert model.property("rejected") == 2
assert model.setProperty("frameRate", 24)
assert model.property("frameRate") == 24
assert model.property("running") is False
model.clear()
assert model.property("peak") == 0
assert model.property("frames") == 6

# Wallpaper color effect: activate on sound, hold through idle delay, fade to
# normal, reactivate immediately, and become inert when disabled.
assert model.setProperty("colorEffectIdleDelay", 80)
assert model.setProperty("colorEffectFadeDuration", 160)
assert model.setProperty("colorEffectEnabled", True)
audible = [0.0] * 640
audible[0] = 0.5
assert model.consumeFrame(pack(audible)) is True
assert abs(model.property("colorEffectAmount") - 1.0) < 1e-6
assert model.consumeFrame(pack([0.0] * 640)) is True
QTest.qWait(60)
assert model.property("colorEffectAmount") == 1.0
QTest.qWait(100)
assert 0.0 < model.property("colorEffectAmount") < 1.0
QTest.qWait(180)
assert model.property("colorEffectAmount") == 0.0
assert model.consumeFrame(pack(audible)) is True
assert model.property("colorEffectAmount") == 1.0
assert model.setProperty("colorEffectEnabled", False)
assert model.property("colorEffectAmount") == 0.0

assert bars.binCountForPhysicalWidth(2560) == 640
assert bars.binCountForPhysicalWidth(1920) == 480
assert [bars.binForStripe(i, 2560) for i in (0, 1, 638, 639, 640, 641, 1278, 1279)] == [0, 1, 638, 639, 639, 638, 1, 0]
assert [bars.binForStripe(i, 1920) for i in (0, 1, 478, 479, 480, 481, 958, 959)] == [0, 1, 478, 479, 479, 478, 1, 0]
assert [bars.physicalXForStripe(i, 2560) for i in (0, 1, 639, 640, 1279)] == [0, 2, 1278, 1280, 2558]
assert [bars.physicalXForStripe(i, 1920) for i in (0, 1, 479, 480, 959)] == [0, 2, 958, 960, 1918]
assert bars.binForStripe(-1, 2560) == -1 and bars.binForStripe(1280, 2560) == -1
assert [wallpaper_effect.binForHue(h, 2560) for h in (0.0, 0.25, 0.5, 0.75, 1.0)] == [0, 320, 639, 320, 0]
assert [wallpaper_effect.binForHue(h, 1920) for h in (0.0, 0.5, 1.0)] == [0, 479, 0]
assert wallpaper_effect.property("ready") is False
assert wallpaper_effect.setProperty("source", QUrl.fromLocalFile(
    "/home/hawk/Downloads/frieren-beyond-journeys-end-5k-x6-2560x1440.jpg"))
assert wallpaper_effect.property("ready") is True
reader = (base / "SpectrumReader.qml").read_text()
assert "Process {" not in reader and "SplitParser" not in reader
theme = (base / "Theme.js").read_text()
surface = (base / "WallpaperSurface.qml").read_text()
assert "wallpaperColorEffectEnabled = true" in theme
assert "active: surface.colorEffectActive" in surface
assert "visible: !surface.colorEffectActive" in surface
assert "Theme.wallpaperColorEffectEnabled && !isVideo" in surface
print("PASS native binary model/process ownership and width-dependent 640/480-bin renderer contract")
view.close()
fixture.unlink(missing_ok=True)
