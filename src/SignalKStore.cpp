#include "SignalKStore.h"

#include <QJSEngine>
#include <QQmlEngine>
#include <algorithm>

Channel::Channel(const QString &path, QObject *parent) : QObject(parent), m_path(path) {}

void Channel::update(const QVariant &value, qint64 timestampMs, const QString &source)
{
    m_value = value;
    m_timestamp = timestampMs;
    m_source = source;

    bool ok = false;
    const double v = value.toDouble(&ok);
    if (ok && value.metaType().id() != QMetaType::QVariantMap) {
        if (!m_history.isEmpty() && timestampMs - m_history.last().t < kMinSampleSpacingMs) {
            // Within the same bucket: keep the latest value.
            if (timestampMs >= m_history.last().t)
                m_history.last().v = v;
        } else if (m_history.isEmpty() || timestampMs >= m_history.last().t) {
            m_history.append({timestampMs, v});
            if (m_history.size() > kMaxSamples)
                m_history.remove(0, m_history.size() - kMaxSamples);
        }
    }
    emit changed();
}

void Channel::reset()
{
    m_value = QVariant();
    m_timestamp = 0;
    m_source.clear();
    m_history.clear();
    emit changed();
}

SignalKStore *SignalKStore::instance()
{
    static SignalKStore *s = new SignalKStore;
    return s;
}

SignalKStore *SignalKStore::create(QQmlEngine *, QJSEngine *)
{
    auto *s = instance();
    QJSEngine::setObjectOwnership(s, QJSEngine::CppOwnership);
    return s;
}

SignalKStore::SignalKStore(QObject *parent) : QObject(parent)
{
    m_tick.setInterval(1000);
    connect(&m_tick, &QTimer::timeout, this, [this] {
        m_rate = m_count;
        m_count = 0;
        if (m_pathsDirty) {
            m_pathsDirty = false;
            emit pathsChanged();
        }
        emit tick();
    });
    m_tick.start();
}

Channel *SignalKStore::channel(const QString &path)
{
    auto it = m_channels.find(path);
    if (it != m_channels.end())
        return it.value();
    auto *c = new Channel(path, this);
    m_channels.insert(path, c);
    return c;
}

void SignalKStore::update(const QString &path, const QVariant &value, qint64 timestampMs,
                          const QString &source)
{
    Channel *c = channel(path);
    if (c->timestamp() == 0)
        m_pathsDirty = true; // first real value for this path
    c->update(value, timestampMs, source);
    ++m_count;
}

void SignalKStore::clear()
{
    // Keep the Channel objects (QML holds pointers to them) but drop their data.
    for (Channel *c : std::as_const(m_channels))
        c->reset();
    m_pathsDirty = true;
}

QStringList SignalKStore::paths() const
{
    QStringList out;
    for (auto it = m_channels.cbegin(); it != m_channels.cend(); ++it)
        if (it.value()->timestamp() != 0)
            out << it.key();
    std::sort(out.begin(), out.end());
    return out;
}

QVariant SignalKStore::value(const QString &path) const
{
    auto *c = m_channels.value(path);
    return c ? c->value() : QVariant();
}

bool SignalKStore::has(const QString &path) const
{
    auto *c = m_channels.value(path);
    return c && c->timestamp() != 0;
}
