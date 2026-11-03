#pragma once

#include <QHash>
#include <QObject>
#include <QStringList>
#include <QTimer>
#include <QVariant>
#include <QVector>
#include <QtQml/qqmlregistration.h>

class QQmlEngine;
class QJSEngine;

// One numeric sample in a channel's history. Time is ms since epoch.
struct Sample {
    qint64 t;
    double v;
};

// The live value of one Signal K path (e.g. "navigation.speedOverGround"),
// plus a bounded history of its numeric values for plotting.
class Channel : public QObject {
    Q_OBJECT
public:
    explicit Channel(const QString &path, QObject *parent = nullptr);

    QString path() const { return m_path; }
    QVariant value() const { return m_value; }
    qint64 timestamp() const { return m_timestamp; }
    QString source() const { return m_source; }
    const QVector<Sample> &history() const { return m_history; }

    void update(const QVariant &value, qint64 timestampMs, const QString &source);
    void reset();

    // Samples closer together than this are merged so history stays bounded.
    static constexpr qint64 kMinSampleSpacingMs = 1000;
    static constexpr int kMaxSamples = 6 * 3600; // ~6 hours at 1 Hz

signals:
    void changed();

private:
    QString m_path;
    QVariant m_value;
    qint64 m_timestamp = 0;
    QString m_source;
    QVector<Sample> m_history;
};

// Everything known about our own vessel, keyed by Signal K path.
// Fed by SignalKClient (live server) or Simulator; read by QML through
// SignalKValue, HistoryPlot and the `paths` list.
class SignalKStore : public QObject {
    Q_OBJECT
    QML_NAMED_ELEMENT(Boat)
    QML_SINGLETON
    Q_PROPERTY(QStringList paths READ paths NOTIFY pathsChanged)
    Q_PROPERTY(int updatesPerSecond READ updatesPerSecond NOTIFY tick)

public:
    static SignalKStore *instance();
    static SignalKStore *create(QQmlEngine *, QJSEngine *);

    Channel *channel(const QString &path); // created on demand
    void update(const QString &path, const QVariant &value, qint64 timestampMs,
                const QString &source = {});
    void clear();

    QStringList paths() const;
    int updatesPerSecond() const { return m_rate; }

    Q_INVOKABLE QVariant value(const QString &path) const;
    Q_INVOKABLE bool has(const QString &path) const;

signals:
    void pathsChanged();
    void tick(); // 1 Hz, used for staleness and scrolling plots

private:
    explicit SignalKStore(QObject *parent = nullptr);
    QHash<QString, Channel *> m_channels;
    QTimer m_tick;
    int m_count = 0;
    int m_rate = 0;
    bool m_pathsDirty = false;
};
