#include <QColor>
#include <QDateTime>
#include <QPointer>

#include <QQuickItem>
#include <QQuickWindow>
#include <QQmlExtensionPlugin>
#include <qqml.h>
#include <QSGGeometryNode>
#include <QSGVertexColorMaterial>
#include <algorithm>
#include <array>
#include <charconv>
#include <cmath>

class SpectrumModel : public QObject {
    Q_OBJECT
    Q_PROPERTY(int binCount READ binCount CONSTANT)
    Q_PROPERTY(int frames READ frames NOTIFY stateChanged)
    Q_PROPERTY(int rejected READ rejected NOTIFY stateChanged)
    Q_PROPERTY(qreal peak READ peak NOTIFY stateChanged)
    Q_PROPERTY(qint64 lastFrame READ lastFrame NOTIFY stateChanged)

public:
    explicit SpectrumModel(QObject *parent = nullptr) : QObject(parent) {}

    int binCount() const { return 640; }
    int frames() const { return m_frames; }
    int rejected() const { return m_rejected; }
    qreal peak() const { return m_peak; }
    qint64 lastFrame() const { return m_lastFrame; }
    const std::array<float, 640> &values() const { return m_values; }

    Q_INVOKABLE bool consume(const QString &line) {
        const QByteArray bytes = line.toLatin1();
        const char *cursor = bytes.constData();
        const char *end = cursor + bytes.size();
        std::array<float, 640> next{};
        float nextPeak = 0;

        for (int i = 0; i < 640; ++i) {
            const char *fieldEnd = cursor;
            while (fieldEnd < end && *fieldEnd != ',') ++fieldEnd;
            float value = 0;
            const auto result = std::from_chars(cursor, fieldEnd, value);
            if (cursor == fieldEnd || result.ec != std::errc{} || result.ptr != fieldEnd ||
                !std::isfinite(value) || (i < 639 && fieldEnd == end) ||
                (i == 639 && fieldEnd != end)) {
                ++m_rejected;
                emit stateChanged();
                return false;
            }
            value = std::clamp(value, 0.0f, 1.0f);
            next[i] = value;
            nextPeak = std::max(nextPeak, value);
            cursor = fieldEnd < end ? fieldEnd + 1 : fieldEnd;
        }

        const bool changed = next != m_values;
        const float previousPeak = m_peak;
        m_values = next;
        m_peak = nextPeak;
        ++m_frames;
        const qint64 now = QDateTime::currentMSecsSinceEpoch();
        m_lastFrame = now;
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

private:
    std::array<float, 640> m_values{};
    int m_frames = 0;
    int m_rejected = 0;
    qreal m_peak = 0;
    qint64 m_lastFrame = 0;
    qint64 m_lastNotification = 0;
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
        const qreal opacity = std::clamp<qreal>(m_opacity, 0, 1);
        const int alpha = qRound(opacity * 255);

        if (m_colorsDirty) {
            for (int stripe = 0; stripe < stripes; ++stripe) {
                qreal hue = std::fmod(m_hueOffset + qreal(stripe) / (stripes - 1), 1.0);
                if (hue < 0) hue += 1;
                const QColor color = QColor::fromHsvF(hue, 0.82, 1.0, opacity);
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

            const auto &color = m_colors[stripe];
            auto set = [&](int offset, qreal x, qreal y) {
                vertices[stripe * verticesPerStripe + offset].set(
                    float(x), float(y), color[0], color[1], color[2], color[3]);
            };
            set(0, x0, y0); set(1, x1, y0); set(2, x1, y1); set(3, x0, y1);
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
        qmlRegisterType<SpectrumBars>(uri, 1, 0, "SpectrumBars");
    }
};

#include "SpectrumBarsPlugin.moc"
