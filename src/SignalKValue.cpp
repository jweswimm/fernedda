#include "SignalKValue.h"
#include "SignalKStore.h"

#include <QDateTime>
#include <cmath>
#include <limits>

SignalKValue::SignalKValue(QObject *parent) : QObject(parent)
{
    connect(SignalKStore::instance(), &SignalKStore::tick, this, &SignalKValue::checkStale);
}

void SignalKValue::setPath(const QString &path)
{
    if (path == m_path)
        return;
    m_path = path;
    disconnect(m_conn);
    m_channel = path.isEmpty() ? nullptr : SignalKStore::instance()->channel(path);
    if (m_channel)
        m_conn = connect(m_channel, &Channel::changed, this, [this] {
            emit changed();
            checkStale();
        });
    emit pathChanged();
    emit changed();
    checkStale();
}

QVariant SignalKValue::value() const
{
    return m_channel ? m_channel->value() : QVariant();
}

double SignalKValue::number() const
{
    if (!m_channel)
        return std::numeric_limits<double>::quiet_NaN();
    const QVariant v = m_channel->value();
    bool ok = false;
    const double d = v.toDouble(&ok);
    return ok ? d : std::numeric_limits<double>::quiet_NaN();
}

bool SignalKValue::valid() const
{
    return m_channel && m_channel->timestamp() != 0;
}

QDateTime SignalKValue::timestamp() const
{
    if (!m_channel || m_channel->timestamp() == 0)
        return {};
    return QDateTime::fromMSecsSinceEpoch(m_channel->timestamp());
}

QString SignalKValue::source() const
{
    return m_channel ? m_channel->source() : QString();
}

void SignalKValue::setStaleAfter(int s)
{
    if (s == m_staleAfter)
        return;
    m_staleAfter = s;
    emit staleAfterChanged();
    checkStale();
}

void SignalKValue::checkStale()
{
    bool stale = true;
    if (m_channel && m_channel->timestamp() != 0) {
        const qint64 age = QDateTime::currentMSecsSinceEpoch() - m_channel->timestamp();
        stale = age > qint64(m_staleAfter) * 1000;
    }
    if (stale != m_stale) {
        m_stale = stale;
        emit staleChanged();
    }
}
