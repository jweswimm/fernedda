#pragma once

#include <QDateTime>
#include <QObject>
#include <QPointer>
#include <QVariant>
#include <QtQml/qqmlregistration.h>

class Channel;

// QML handle on one Signal K path:
//   SignalKValue { id: sog; path: "navigation.speedOverGround" }
//   Text { text: sog.number * 1.94384 }
// `number` is NaN when there is no numeric value. `stale` turns true when no
// update has arrived for `staleAfter` seconds.
class SignalKValue : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString path READ path WRITE setPath NOTIFY pathChanged)
    Q_PROPERTY(QVariant value READ value NOTIFY changed)
    Q_PROPERTY(double number READ number NOTIFY changed)
    Q_PROPERTY(bool valid READ valid NOTIFY changed)
    Q_PROPERTY(QDateTime timestamp READ timestamp NOTIFY changed)
    Q_PROPERTY(QString source READ source NOTIFY changed)
    Q_PROPERTY(int staleAfter READ staleAfter WRITE setStaleAfter NOTIFY staleAfterChanged)
    Q_PROPERTY(bool stale READ stale NOTIFY staleChanged)

public:
    explicit SignalKValue(QObject *parent = nullptr);

    QString path() const { return m_path; }
    void setPath(const QString &path);
    QVariant value() const;
    double number() const;
    bool valid() const;
    QDateTime timestamp() const;
    QString source() const;
    int staleAfter() const { return m_staleAfter; }
    void setStaleAfter(int s);
    bool stale() const { return m_stale; }

signals:
    void pathChanged();
    void changed();
    void staleAfterChanged();
    void staleChanged();

private:
    void checkStale();
    QString m_path;
    QPointer<Channel> m_channel;
    QMetaObject::Connection m_conn;
    int m_staleAfter = 10;
    bool m_stale = true;
};
