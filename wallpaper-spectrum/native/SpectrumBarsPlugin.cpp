#include <QColor>
#include <QDateTime>
#include <QImageReader>
#include <QPainter>
#include <QPointer>
#include <QProcess>
#include <QProcessEnvironment>
#include <QTimer>

#include <QQuickItem>
#include <QQuickWindow>
#include <QQmlExtensionPlugin>
#include <qqml.h>
#include <QSGGeometryNode>
#include <QSGMaterial>
#include <QSGMaterialShader>
#include <QSGTexture>
#include <QSGVertexColorMaterial>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <limits>

class SpectrumModel : public QObject {
    Q_OBJECT
    Q_PROPERTY(int binCount READ binCount CONSTANT)
    Q_PROPERTY(int frames READ frames NOTIFY stateChanged)
    Q_PROPERTY(int rejected READ rejected NOTIFY stateChanged)
    Q_PROPERTY(qreal peak READ peak NOTIFY stateChanged)
    Q_PROPERTY(qint64 lastFrame READ lastFrame NOTIFY stateChanged)
    Q_PROPERTY(QStringList captureCommand READ captureCommand WRITE setCaptureCommand NOTIFY captureCommandChanged)
    Q_PROPERTY(int frameRate READ frameRate WRITE setFrameRate NOTIFY frameRateChanged)
    Q_PROPERTY(bool running READ running WRITE setRunning NOTIFY runningChanged)
    Q_PROPERTY(bool colorEffectEnabled READ colorEffectEnabled WRITE setColorEffectEnabled NOTIFY colorEffectEnabledChanged)
    Q_PROPERTY(int colorEffectIdleDelay READ colorEffectIdleDelay WRITE setColorEffectIdleDelay NOTIFY colorEffectTimingChanged)
    Q_PROPERTY(int colorEffectFadeDuration READ colorEffectFadeDuration WRITE setColorEffectFadeDuration NOTIFY colorEffectTimingChanged)
    Q_PROPERTY(qreal colorEffectAmount READ colorEffectAmount NOTIFY colorEffectAmountChanged)

public:
    explicit SpectrumModel(QObject *parent = nullptr) : QObject(parent) {
        static_assert(sizeof(float) == 4 && std::numeric_limits<float>::is_iec559,
                      "binary spectrum frames require IEEE-754 float32");
#if Q_BYTE_ORDER != Q_LITTLE_ENDIAN
#error "binary spectrum frames currently require a little-endian host"
#endif
        connect(&m_process, &QProcess::readyReadStandardOutput,
                this, &SpectrumModel::readFrames);
        connect(&m_process, &QProcess::readyReadStandardError, this, [this] {
            const QByteArray text = m_process.readAllStandardError().trimmed();
            if (!text.isEmpty()) qWarning().noquote() << "Audio capture:" << text;
        });
        connect(&m_process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
                this, &SpectrumModel::processFinished);
        connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
            if (error != QProcess::FailedToStart) return;
            m_buffer.clear();
            clear();
            emit runningChanged();
            if (m_shouldRun) m_restart.start();
        });
        m_restart.setSingleShot(true);
        m_restart.setInterval(2000);
        connect(&m_restart, &QTimer::timeout, this, &SpectrumModel::startProcess);
        m_watchdog.setInterval(500);
        connect(&m_watchdog, &QTimer::timeout, this, [this] {
            if (m_peak > 0 && m_lastFrame > 0 &&
                QDateTime::currentMSecsSinceEpoch() - m_lastFrame > 1000)
                clear();
        });
        m_watchdog.start();
        m_colorEffectTimer.setInterval(qRound(1000.0 / m_frameRate));
        connect(&m_colorEffectTimer, &QTimer::timeout,
                this, &SpectrumModel::updateColorEffect);
    }

    ~SpectrumModel() override {
        m_shouldRun = false;
        m_restart.stop();
        if (m_process.state() != QProcess::NotRunning) {
            m_process.terminate();
            if (!m_process.waitForFinished(1500)) {
                m_process.kill();
                m_process.waitForFinished(1000);
            }
        }
    }

    int binCount() const { return 640; }
    int frames() const { return m_frames; }
    int rejected() const { return m_rejected; }
    qreal peak() const { return m_peak; }
    qint64 lastFrame() const { return m_lastFrame; }
    QStringList captureCommand() const { return m_captureCommand; }
    int frameRate() const { return m_frameRate; }
    bool running() const { return m_process.state() != QProcess::NotRunning; }
    bool colorEffectEnabled() const { return m_colorEffectEnabled; }
    int colorEffectIdleDelay() const { return m_colorEffectIdleDelay; }
    int colorEffectFadeDuration() const { return m_colorEffectFadeDuration; }
    qreal colorEffectAmount() const { return m_colorEffectAmount; }
    const std::array<float, 640> &values() const { return m_values; }

    void setCaptureCommand(const QStringList &command) {
        if (m_captureCommand == command) return;
        m_captureCommand = command;
        emit captureCommandChanged();
        if (m_shouldRun && !running()) startProcess();
    }

    void setFrameRate(int value) {
        value = std::clamp(value, 1, 120);
        if (m_frameRate == value) return;
        m_frameRate = value;
        m_colorEffectTimer.setInterval(qRound(1000.0 / m_frameRate));
        emit frameRateChanged();
    }

    void setColorEffectEnabled(bool value) {
        if (m_colorEffectEnabled == value) return;
        m_colorEffectEnabled = value;
        if (!value) {
            m_colorEffectTimer.stop();
            m_lastAudible = 0;
            setColorEffectAmount(0);
        }
        emit colorEffectEnabledChanged();
    }

    void setColorEffectIdleDelay(int value) {
        value = std::max(0, value);
        if (m_colorEffectIdleDelay == value) return;
        m_colorEffectIdleDelay = value;
        emit colorEffectTimingChanged();
    }

    void setColorEffectFadeDuration(int value) {
        value = std::max(1, value);
        if (m_colorEffectFadeDuration == value) return;
        m_colorEffectFadeDuration = value;
        emit colorEffectTimingChanged();
    }

    void setRunning(bool value) {
        m_shouldRun = value;
        if (value) {
            startProcess();
        } else {
            m_restart.stop();
            if (running()) m_process.terminate();
        }
    }

    Q_INVOKABLE void reconnect() {
        m_shouldRun = true;
        m_restart.stop();
        if (running()) m_process.terminate();
        else m_restart.start();
    }

    Q_INVOKABLE bool consumeFrame(const QByteArray &bytes) {
        constexpr qsizetype frameBytes = 640 * qsizetype(sizeof(float));
        if (bytes.size() != frameBytes) {
            rejectFrame();
            return false;
        }
        std::array<float, 640> next{};
        std::memcpy(next.data(), bytes.constData(), frameBytes);
        float nextPeak = 0;
        for (float &value : next) {
            if (!std::isfinite(value)) {
                rejectFrame();
                return false;
            }
            value = std::clamp(value, 0.0f, 1.0f);
            nextPeak = std::max(nextPeak, value);
        }

        const bool changed = next != m_values;
        const float previousPeak = m_peak;
        m_values = next;
        m_peak = nextPeak;
        ++m_frames;
        const qint64 now = QDateTime::currentMSecsSinceEpoch();
        m_lastFrame = now;
        if (m_colorEffectEnabled && nextPeak >= 0.001f) {
            m_lastAudible = now;
            setColorEffectAmount(1);
            if (!m_colorEffectTimer.isActive()) m_colorEffectTimer.start();
        }
        emit stateChanged();
        const bool decaying = nextPeak < 0.02f && nextPeak < previousPeak;
        const bool notify = changed && (!decaying || nextPeak == 0 ||
                                        m_lastNotification == 0 ||
                                        now - m_lastNotification >= 125);
        if (notify) {
            m_lastNotification = now;
            emit frameChanged();
        }
        return true;
    }

    Q_INVOKABLE void clear() {
        const bool changed = std::any_of(m_values.begin(), m_values.end(),
                                        [](float value) { return value != 0; });
        m_values.fill(0);
        m_peak = 0;
        emit stateChanged();
        if (changed) {
            m_lastNotification = QDateTime::currentMSecsSinceEpoch();
            emit frameChanged();
        }
    }

signals:
    void stateChanged();
    void frameChanged();
    void captureCommandChanged();
    void frameRateChanged();
    void runningChanged();
    void colorEffectEnabledChanged();
    void colorEffectTimingChanged();
    void colorEffectAmountChanged();

private:
    void rejectFrame() {
        ++m_rejected;
        emit stateChanged();
    }

    void setColorEffectAmount(qreal value) {
        value = std::clamp<qreal>(value, 0, 1);
        if (qFuzzyCompare(m_colorEffectAmount, value)) return;
        m_colorEffectAmount = value;
        emit colorEffectAmountChanged();
    }

    void updateColorEffect() {
        if (!m_colorEffectEnabled || m_lastAudible <= 0) {
            m_colorEffectTimer.stop();
            setColorEffectAmount(0);
            return;
        }
        const qint64 elapsed = QDateTime::currentMSecsSinceEpoch() - m_lastAudible;
        if (elapsed <= m_colorEffectIdleDelay) {
            setColorEffectAmount(1);
            return;
        }
        const qreal progress = qreal(elapsed - m_colorEffectIdleDelay) /
                               m_colorEffectFadeDuration;
        setColorEffectAmount(1 - progress);
        if (progress >= 1) m_colorEffectTimer.stop();
    }

    void startProcess() {
        if (!m_shouldRun || running() || m_captureCommand.isEmpty()) return;
        m_buffer.clear();
        QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
        environment.insert("SPECTRUM_FRAME_RATE", QString::number(m_frameRate));
        m_process.setProcessEnvironment(environment);
        m_process.setProgram(m_captureCommand.first());
        m_process.setArguments(m_captureCommand.sliced(1));
        m_process.start();
        emit runningChanged();
    }

    void readFrames() {
        constexpr qsizetype frameBytes = 640 * qsizetype(sizeof(float));
        m_buffer += m_process.readAllStandardOutput();
        while (m_buffer.size() >= frameBytes) {
            consumeFrame(m_buffer.first(frameBytes));
            m_buffer.remove(0, frameBytes);
        }
    }

    void processFinished() {
        readFrames();
        if (!m_buffer.isEmpty()) rejectFrame();
        m_buffer.clear();
        clear();
        emit runningChanged();
        if (m_shouldRun) m_restart.start();
    }

    std::array<float, 640> m_values{};
    int m_frames = 0;
    int m_rejected = 0;
    qreal m_peak = 0;
    qint64 m_lastFrame = 0;
    qint64 m_lastNotification = 0;
    QStringList m_captureCommand;
    int m_frameRate = 24;
    bool m_shouldRun = false;
    bool m_colorEffectEnabled = false;
    int m_colorEffectIdleDelay = 15000;
    int m_colorEffectFadeDuration = 2000;
    qreal m_colorEffectAmount = 0;
    qint64 m_lastAudible = 0;
    QByteArray m_buffer;
    QProcess m_process{this};
    QTimer m_restart{this};
    QTimer m_watchdog{this};
    QTimer m_colorEffectTimer{this};
};

class WallpaperMaterial;

class WallpaperShader final : public QSGMaterialShader {
public:
    WallpaperShader() {
        setShaderFileName(VertexStage, QStringLiteral(":/hkspectrum/wallpaper.vert.qsb"));
        setShaderFileName(FragmentStage, QStringLiteral(":/hkspectrum/wallpaper.frag.qsb"));
    }

    bool updateUniformData(RenderState &state, QSGMaterial *newMaterial,
                           QSGMaterial *oldMaterial) override;
    void updateSampledImage(RenderState &state, int binding, QSGTexture **texture,
                            QSGMaterial *newMaterial, QSGMaterial *oldMaterial) override;
};

class WallpaperMaterial final : public QSGMaterial {
public:
    WallpaperMaterial() {
        setFlag(QSGMaterial::Blending, true);
        setFlag(QSGMaterial::NoBatching, true);
    }
    ~WallpaperMaterial() override {
        delete wallpaperTexture;
        delete spectrumTexture;
    }
    QSGMaterialType *type() const override {
        static QSGMaterialType materialType;
        return &materialType;
    }
    QSGMaterialShader *createShader(QSGRendererInterface::RenderMode) const override {
        return new WallpaperShader;
    }
    int compare(const QSGMaterial *other) const override {
        return this == other ? 0 : (this < other ? -1 : 1);
    }

    QSGTexture *wallpaperTexture = nullptr;
    QSGTexture *spectrumTexture = nullptr;
    float effectAmount = 0;
    float binCount = 640;
    float hueOffset = 0;
};

bool WallpaperShader::updateUniformData(RenderState &state, QSGMaterial *newMaterial,
                                        QSGMaterial *) {
    auto *material = static_cast<WallpaperMaterial *>(newMaterial);
    QByteArray *data = state.uniformData();
    if (data->size() < 80) return false;
    if (state.isMatrixDirty())
        std::memcpy(data->data(), state.combinedMatrix().constData(), 64);
    const float opacity = state.opacity();
    std::memcpy(data->data() + 64, &opacity, 4);
    std::memcpy(data->data() + 68, &material->effectAmount, 4);
    std::memcpy(data->data() + 72, &material->binCount, 4);
    std::memcpy(data->data() + 76, &material->hueOffset, 4);
    return true;
}

void WallpaperShader::updateSampledImage(RenderState &state, int binding, QSGTexture **texture,
                                         QSGMaterial *newMaterial, QSGMaterial *) {
    auto *material = static_cast<WallpaperMaterial *>(newMaterial);
    QSGTexture *selected = nullptr;
    if (binding == 1) selected = material->wallpaperTexture;
    else if (binding == 2) selected = material->spectrumTexture;
    if (selected) {
        selected->commitTextureOperations(state.rhi(), state.resourceUpdateBatch());
        *texture = selected;
    }
}

class WallpaperSpectrum : public QQuickItem {
    Q_OBJECT
    Q_PROPERTY(SpectrumModel *model READ model WRITE setModel NOTIFY modelChanged)
    Q_PROPERTY(QUrl source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(QString fitMode READ fitMode WRITE setFitMode NOTIFY appearanceChanged)
    Q_PROPERTY(bool mirror READ mirror WRITE setMirror NOTIFY appearanceChanged)
    Q_PROPERTY(qreal imageOpacity READ imageOpacity WRITE setImageOpacity NOTIFY appearanceChanged)
    Q_PROPERTY(QColor backgroundColor READ backgroundColor WRITE setBackgroundColor NOTIFY appearanceChanged)
    Q_PROPERTY(qreal dimOpacity READ dimOpacity WRITE setDimOpacity NOTIFY appearanceChanged)
    Q_PROPERTY(QColor dimColor READ dimColor WRITE setDimColor NOTIFY appearanceChanged)
    Q_PROPERTY(qreal hueOffset READ hueOffset WRITE setHueOffset NOTIFY appearanceChanged)
    Q_PROPERTY(int hueBinCount READ hueBinCount WRITE setHueBinCount NOTIFY appearanceChanged)
    Q_PROPERTY(bool ready READ ready NOTIFY sourceChanged)

public:
    WallpaperSpectrum() { setFlag(ItemHasContents, true); }

    SpectrumModel *model() const { return m_model; }
    QUrl source() const { return m_sourceUrl; }
    QString fitMode() const { return m_fitMode; }
    bool mirror() const { return m_mirror; }
    qreal imageOpacity() const { return m_imageOpacity; }
    QColor backgroundColor() const { return m_backgroundColor; }
    qreal dimOpacity() const { return m_dimOpacity; }
    QColor dimColor() const { return m_dimColor; }
    qreal hueOffset() const { return m_hueOffset; }
    int hueBinCount() const { return m_hueBinCount; }
    bool ready() const { return !m_sourceImage.isNull(); }

    Q_INVOKABLE int binForHue(qreal hue, int physicalWidth) const {
        const int bins = std::clamp(std::min(m_hueBinCount, physicalWidth / 4), 1, 640);
        hue = std::fmod(hue - m_hueOffset, 1.0);
        if (hue < 0) hue += 1;
        const qreal phase = hue * 2;
        const qreal mapped = phase <= 1 ? phase * (bins - 1)
                                        : (2 - phase) * (bins - 1);
        return std::clamp(qRound(mapped), 0, bins - 1);
    }

    void setModel(SpectrumModel *value) {
        if (m_model == value) return;
        if (m_model) disconnect(m_model, nullptr, this, nullptr);
        m_model = value;
        if (m_model) {
            connect(m_model, &SpectrumModel::frameChanged, this, [this] {
                m_spectrumDirty = true;
                update();
            });
            connect(m_model, &SpectrumModel::colorEffectAmountChanged,
                    this, [this] { update(); });
        }
        m_spectrumDirty = true;
        update();
        emit modelChanged();
    }

    void setSource(const QUrl &value) {
        if (m_sourceUrl == value) return;
        m_sourceUrl = value;
        QImageReader reader(value.isLocalFile() ? value.toLocalFile() : value.toString());
        reader.setAutoTransform(true);
        m_sourceImage = reader.read();
        if (m_sourceImage.isNull() && !value.isEmpty())
            qWarning().noquote() << "Wallpaper effect: failed to load" << value
                                 << reader.errorString();
        markImageDirty();
        emit sourceChanged();
    }
    void setFitMode(const QString &value) {
        const QString mode = value == "fit" || value == "stretch" ? value : "crop";
        if (m_fitMode == mode) return;
        m_fitMode = mode; markImageDirty(); emit appearanceChanged();
    }
    void setMirror(bool value) {
        if (m_mirror == value) return;
        m_mirror = value; markImageDirty(); emit appearanceChanged();
    }
    void setImageOpacity(qreal value) {
        value = std::clamp<qreal>(value, 0, 1);
        if (qFuzzyCompare(m_imageOpacity, value)) return;
        m_imageOpacity = value; markImageDirty(); emit appearanceChanged();
    }
    void setBackgroundColor(const QColor &value) {
        if (m_backgroundColor == value) return;
        m_backgroundColor = value; markImageDirty(); emit appearanceChanged();
    }
    void setDimOpacity(qreal value) {
        value = std::clamp<qreal>(value, 0, 1);
        if (qFuzzyCompare(m_dimOpacity, value)) return;
        m_dimOpacity = value; markImageDirty(); emit appearanceChanged();
    }
    void setDimColor(const QColor &value) {
        if (m_dimColor == value) return;
        m_dimColor = value; markImageDirty(); emit appearanceChanged();
    }
    void setHueOffset(qreal value) {
        if (qFuzzyCompare(m_hueOffset, value)) return;
        m_hueOffset = value; update(); emit appearanceChanged();
    }
    void setHueBinCount(int value) {
        value = std::clamp(value, 1, 640);
        if (m_hueBinCount == value) return;
        m_hueBinCount = value; update(); emit appearanceChanged();
    }

signals:
    void modelChanged();
    void sourceChanged();
    void appearanceChanged();

protected:
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override {
        QQuickItem::geometryChange(newGeometry, oldGeometry);
        if (newGeometry.size() != oldGeometry.size()) markImageDirty();
    }

    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) override {
        if (m_sourceImage.isNull() || !window() || width() <= 0 || height() <= 0) {
            delete oldNode;
            return nullptr;
        }
        auto *node = static_cast<QSGGeometryNode *>(oldNode);
        WallpaperMaterial *material = nullptr;
        if (!node) {
            auto *geometry = new QSGGeometry(QSGGeometry::defaultAttributes_TexturedPoint2D(), 4, 6);
            geometry->setDrawingMode(QSGGeometry::DrawTriangles);
            auto *indices = geometry->indexDataAsUShort();
            indices[0] = 0; indices[1] = 1; indices[2] = 2;
            indices[3] = 2; indices[4] = 1; indices[5] = 3;
            node = new QSGGeometryNode;
            node->setGeometry(geometry);
            node->setFlag(QSGNode::OwnsGeometry);
            material = new WallpaperMaterial;
            node->setMaterial(material);
            node->setFlag(QSGNode::OwnsMaterial);
            m_imageDirty = true;
            m_spectrumDirty = true;

        } else {
            material = static_cast<WallpaperMaterial *>(node->material());
        }

        QSGGeometry::updateTexturedRectGeometry(node->geometry(),
            QRectF(0, 0, width(), height()), QRectF(0, 0, 1, 1));
        const qreal dpr = window()->devicePixelRatio();
        const QSize physicalSize(std::max(1, qRound(width() * dpr)),
                                 std::max(1, qRound(height() * dpr)));
        if (m_imageDirty || physicalSize != m_textureSize) {
            delete material->wallpaperTexture;
            material->wallpaperTexture = window()->createTextureFromImage(
                renderedImage(physicalSize), QQuickWindow::TextureIsOpaque);
            material->wallpaperTexture->setFiltering(QSGTexture::Linear);
            material->wallpaperTexture->setHorizontalWrapMode(QSGTexture::ClampToEdge);
            material->wallpaperTexture->setVerticalWrapMode(QSGTexture::ClampToEdge);
            m_textureSize = physicalSize;
            m_imageDirty = false;
        }
        if (m_spectrumDirty || !material->spectrumTexture) {
            QImage spectrum(640, 1, QImage::Format_RGBA8888);
            uchar *pixels = spectrum.scanLine(0);
            const auto *values = m_model ? &m_model->values() : nullptr;
            for (int i = 0; i < 640; ++i) {
                const uchar amplitude = static_cast<uchar>(qRound(
                    std::clamp(values ? (*values)[i] : 0.0f, 0.0f, 1.0f) * 255));
                pixels[i * 4] = amplitude;
                pixels[i * 4 + 1] = 0;
                pixels[i * 4 + 2] = 0;
                pixels[i * 4 + 3] = 255;
            }
            delete material->spectrumTexture;
            material->spectrumTexture = window()->createTextureFromImage(spectrum);
            material->spectrumTexture->setFiltering(QSGTexture::Linear);
            material->spectrumTexture->setHorizontalWrapMode(QSGTexture::ClampToEdge);
            material->spectrumTexture->setVerticalWrapMode(QSGTexture::ClampToEdge);
            m_spectrumDirty = false;
        }
        material->effectAmount = m_model ? float(m_model->colorEffectAmount()) : 0;
        material->binCount = float(std::clamp(
            std::min(m_hueBinCount, physicalSize.width() / 4), 1, 640));
        material->hueOffset = float(m_hueOffset);
        node->markDirty(QSGNode::DirtyGeometry | QSGNode::DirtyMaterial);
        return node;
    }

private:
    void markImageDirty() { m_imageDirty = true; update(); }

    QImage renderedImage(const QSize &target) const {
        QImage canvas(target, QImage::Format_RGBA8888_Premultiplied);
        canvas.fill(m_backgroundColor.rgba());
        QImage sourceImage = m_mirror ? m_sourceImage.flipped(Qt::Horizontal) : m_sourceImage;
        QPainter painter(&canvas);
        painter.setRenderHint(QPainter::SmoothPixmapTransform, true);
        painter.setOpacity(m_imageOpacity);
        if (m_fitMode == "stretch") {
            painter.drawImage(QRect(QPoint(0, 0), target), sourceImage);
        } else {
            const Qt::AspectRatioMode aspect = m_fitMode == "fit"
                ? Qt::KeepAspectRatio : Qt::KeepAspectRatioByExpanding;
            const QImage scaled = sourceImage.scaled(target, aspect, Qt::SmoothTransformation);
            const QPoint origin((target.width() - scaled.width()) / 2,
                                (target.height() - scaled.height()) / 2);
            painter.drawImage(origin, scaled);
        }
        if (m_dimOpacity > 0) {
            painter.setOpacity(m_dimOpacity);
            painter.fillRect(QRect(QPoint(0, 0), target), m_dimColor);
        }
        painter.end();
        return canvas;
    }

    QPointer<SpectrumModel> m_model;
    QUrl m_sourceUrl;
    QImage m_sourceImage;
    QString m_fitMode = "crop";
    bool m_mirror = false;
    qreal m_imageOpacity = 1;
    QColor m_backgroundColor = Qt::black;
    qreal m_dimOpacity = 0;
    QColor m_dimColor = Qt::black;
    qreal m_hueOffset = 0;
    int m_hueBinCount = 180;
    bool m_imageDirty = true;
    bool m_spectrumDirty = true;
    QSize m_textureSize;
};

class SpectrumBars : public QQuickItem {
    Q_OBJECT
    Q_PROPERTY(SpectrumModel *model READ model WRITE setModel NOTIFY modelChanged)
    Q_PROPERTY(bool hasModel READ hasModel NOTIFY modelChanged)
    Q_PROPERTY(qreal gain READ gain WRITE setGain NOTIFY gainChanged)
    Q_PROPERTY(qreal effectOpacity READ effectOpacity WRITE setEffectOpacity NOTIFY effectOpacityChanged)
    Q_PROPERTY(qreal hueOffset READ hueOffset WRITE setHueOffset NOTIFY hueOffsetChanged)

public:
    SpectrumBars() { setFlag(ItemHasContents, true); }

    SpectrumModel *model() const { return m_model; }
    bool hasModel() const { return !m_model.isNull(); }
    qreal gain() const { return m_gain; }
    qreal effectOpacity() const { return m_opacity; }
    qreal hueOffset() const { return m_hueOffset; }
    Q_INVOKABLE int binCountForPhysicalWidth(int physicalWidth) const {
        return std::clamp(physicalWidth / 4, 1, 640);
    }
    Q_INVOKABLE int binForStripe(int stripe, int physicalWidth) const {
        const int bins = binCountForPhysicalWidth(physicalWidth);
        const int stripes = bins * 2;
        if (stripe < 0 || stripe >= stripes) return -1;
        return stripe < bins ? stripe : stripes - 1 - stripe;
    }
    Q_INVOKABLE int physicalXForStripe(int stripe, int physicalWidth) const {
        const int bins = binCountForPhysicalWidth(physicalWidth);
        const int stripes = bins * 2;
        if (stripe < 0 || stripe >= stripes || physicalWidth < 1) return -1;
        return (stripe * physicalWidth + stripes - 1) / stripes;
    }
    Q_INVOKABLE qreal gradientOpacityAt(qreal normalizedHeight) const {
        return std::clamp<qreal>(normalizedHeight, 0, 1) * 0.8 *
               std::clamp<qreal>(m_opacity, 0, 1);
    }
    Q_INVOKABLE qreal barTopOpacity(qreal amplitude) const {
        return gradientOpacityAt(1 - std::clamp<qreal>(amplitude, 0, 1));
    }

    void setModel(SpectrumModel *value) {
        if (m_model == value) return;
        if (m_model) disconnect(m_model, nullptr, this, nullptr);
        m_model = value;
        if (m_model)
            connect(m_model, &SpectrumModel::frameChanged, this, [this] { update(); });
        update();
        emit modelChanged();
    }
    void setGain(qreal value) {
        value = std::max<qreal>(0, value);
        if (qFuzzyCompare(m_gain, value)) return;
        m_gain = value; update(); emit gainChanged();
    }
    void setEffectOpacity(qreal value) {
        value = std::clamp<qreal>(value, 0, 1);
        if (qFuzzyCompare(m_opacity, value)) return;
        m_opacity = value; m_colorsDirty = true; update(); emit effectOpacityChanged();
    }
    void setHueOffset(qreal value) {
        if (qFuzzyCompare(m_hueOffset, value)) return;
        m_hueOffset = value; m_colorsDirty = true; update(); emit hueOffsetChanged();
    }

signals:
    void modelChanged();
    void gainChanged();
    void effectOpacityChanged();
    void hueOffsetChanged();

protected:
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override {
        QQuickItem::geometryChange(newGeometry, oldGeometry);
        update();
    }

    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) override {
        constexpr int maxStripes = 1280;
        constexpr int verticesPerStripe = 4;
        constexpr int indicesPerStripe = 6;

        auto *node = static_cast<QSGGeometryNode *>(oldNode);
        if (!node) {
            auto *geometry = new QSGGeometry(
                QSGGeometry::defaultAttributes_ColoredPoint2D(),
                maxStripes * verticesPerStripe,
                maxStripes * indicesPerStripe,
                QSGGeometry::UnsignedShortType);
            geometry->setDrawingMode(QSGGeometry::DrawTriangles);
            geometry->setVertexDataPattern(QSGGeometry::DynamicPattern);
            auto *indices = geometry->indexDataAsUShort();
            for (int i = 0; i < maxStripes; ++i) {
                const quint16 v = static_cast<quint16>(i * verticesPerStripe);
                const int j = i * indicesPerStripe;
                indices[j] = v; indices[j + 1] = v + 1; indices[j + 2] = v + 2;
                indices[j + 3] = v; indices[j + 4] = v + 2; indices[j + 5] = v + 3;
            }
            node = new QSGGeometryNode;
            node->setGeometry(geometry);
            node->setFlag(QSGNode::OwnsGeometry);
            auto *material = new QSGVertexColorMaterial;
            material->setFlag(QSGMaterial::Blending, true);
            node->setMaterial(material);
            node->setFlag(QSGNode::OwnsMaterial);
        }

        auto *vertices = node->geometry()->vertexDataAsColoredPoint2D();
        const qreal dpr = window() ? window()->devicePixelRatio() : 1;
        const int physicalWidth = std::max(1, qRound(width() * dpr));
        const int bins = binCountForPhysicalWidth(physicalWidth);
        const int stripes = bins * 2;
        node->geometry()->setVertexCount(stripes * verticesPerStripe);
        node->geometry()->setIndexCount(stripes * indicesPerStripe);
        const qreal logicalBarWidth = 1.0 / dpr;
        const qreal bottomOpacity = gradientOpacityAt(1);
        const int alpha = qRound(bottomOpacity * 255);

        if (m_colorsDirty) {
            for (int stripe = 0; stripe < stripes; ++stripe) {
                qreal hue = std::fmod(m_hueOffset + qreal(stripe) / (stripes - 1), 1.0);
                if (hue < 0) hue += 1;
                const QColor color = QColor::fromHsvF(hue, 0.82, 1.0, bottomOpacity);
                m_colors[stripe] = {
                    static_cast<uchar>(color.red() * alpha / 255),
                    static_cast<uchar>(color.green() * alpha / 255),
                    static_cast<uchar>(color.blue() * alpha / 255),
                    static_cast<uchar>(alpha)};
            }
            m_colorsDirty = false;
        }

        for (int stripe = 0; stripe < stripes; ++stripe) {
            // ceil(stripe * width / 1280): exactly one physical pixel per bar.
            const int physicalX = physicalXForStripe(stripe, physicalWidth);
            const qreal x0 = physicalX / dpr;
            const qreal x1 = x0 + logicalBarWidth;
            const int bin = binForStripe(stripe, physicalWidth);
            const float amplitude = m_model ? m_model->values()[bin] : 0;
            const qreal value = std::clamp<qreal>(amplitude * m_gain, 0, 1);
            const qreal y0 = height() * (1 - value);
            const qreal y1 = height();
            const qreal topScale = 1 - value;

            const auto &color = m_colors[stripe];
            auto set = [&](int offset, qreal x, qreal y, qreal colorScale) {
                vertices[stripe * verticesPerStripe + offset].set(
                    float(x), float(y),
                    static_cast<uchar>(qRound(color[0] * colorScale)),
                    static_cast<uchar>(qRound(color[1] * colorScale)),
                    static_cast<uchar>(qRound(color[2] * colorScale)),
                    static_cast<uchar>(qRound(color[3] * colorScale)));
            };
            set(0, x0, y0, topScale); set(1, x1, y0, topScale);
            set(2, x1, y1, 1); set(3, x0, y1, 1);
        }
        node->markDirty(QSGNode::DirtyGeometry | QSGNode::DirtyMaterial);
        return node;
    }

private:
    QPointer<SpectrumModel> m_model;
    std::array<std::array<uchar, 4>, 1280> m_colors{};
    bool m_colorsDirty = true;
    qreal m_gain = 1;
    qreal m_opacity = 0.85;
    qreal m_hueOffset = 0;
};

class HkSpectrumPlugin final : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "org.qt-project.Qt.QQmlExtensionInterface/1.0")
public:
    void registerTypes(const char *uri) override {
        qmlRegisterType<SpectrumModel>(uri, 1, 0, "SpectrumModel");
        qmlRegisterType<WallpaperSpectrum>(uri, 1, 0, "WallpaperSpectrum");
        qmlRegisterType<SpectrumBars>(uri, 1, 0, "SpectrumBars");
    }
};

#include "SpectrumBarsPlugin.moc"
