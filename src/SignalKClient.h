#pragma once

#include <QObject>
#include <QTimer>
#include <QUrl>
#include <QWebSocket>
#include <QtQml/qqmlregistration.h>

class Simulator;
class QQmlEngine;
class QJSEngine;

// Where boat data comes from: the built-in simulator, or a Signal K server's
// WebSocket stream (ws://<host>:3000/signalk/v1/stream). Exposed to QML as
// the `Connection` singleton. Settings persist across runs.
class SignalKClient : public QObject {
    Q_OBJECT
    QML_NAMED_ELEMENT(Connection)
    QML_SINGLETON
    Q_PROPERTY(Mode mode READ mode WRITE setMode NOTIFY modeChanged)
    Q_PROPERTY(QString server READ server WRITE setServer NOTIFY serverChanged)
    Q_PROPERTY(State state READ state NOTIFY stateChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY stateChanged)
    Q_PROPERTY(QString streamUrl READ streamUrl NOTIFY serverChanged)
    Q_PROPERTY(QString selfId READ selfId NOTIFY stateChanged)
    Q_PROPERTY(QString serverVersion READ serverVersion NOTIFY stateChanged)

public:
    enum Mode { Simulated, Live };
    Q_ENUM(Mode)
    enum State { Idle, Connecting, Connected, Error };
    Q_ENUM(State)

    static SignalKClient *instance();
    static SignalKClient *create(QQmlEngine *, QJSEngine *);

    Mode mode() const { return m_mode; }
    void setMode(Mode m);
    QString server() const { return m_server; }
    void setServer(const QString &s);
    State state() const { return m_state; }
    QString statusText() const { return m_statusText; }
    QString streamUrl() const { return streamUrlFor(m_server).toString(); }
    QString selfId() const { return m_self; }
    QString serverVersion() const { return m_version; }

    Q_INVOKABLE void reconnect();

    static QUrl streamUrlFor(const QString &server);

signals:
    void modeChanged();
    void serverChanged();
    void stateChanged();

private:
    explicit SignalKClient(QObject *parent = nullptr);
    void apply();
    void openSocket();
    void setState(State s, const QString &text);
    void handleMessage(const QString &message);

    Mode m_mode = Simulated;
    QString m_server;
    State m_state = Idle;
    QString m_statusText;
    QString m_self;
    QString m_version;
    QWebSocket m_socket;
    QTimer m_retry;
    int m_retryDelay = 1000;
    Simulator *m_sim = nullptr;
};
