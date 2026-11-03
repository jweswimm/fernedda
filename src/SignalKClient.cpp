#include "SignalKClient.h"
#include "SignalKStore.h"
#include "Simulator.h"

#include <QDateTime>
#include <QJSEngine>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQmlEngine>
#include <QSettings>
#include <QUrlQuery>

SignalKClient *SignalKClient::instance()
{
    static SignalKClient *s = new SignalKClient;
    return s;
}

SignalKClient *SignalKClient::create(QQmlEngine *, QJSEngine *)
{
    auto *s = instance();
    QJSEngine::setObjectOwnership(s, QJSEngine::CppOwnership);
    return s;
}

SignalKClient::SignalKClient(QObject *parent) : QObject(parent)
{
    QSettings settings;
    m_server = settings.value("signalk/server", "localhost:3000").toString();
    m_mode = settings.value("signalk/mode", "simulated").toString() == "live" ? Live : Simulated;

    m_sim = new ::Simulator(this);

    m_retry.setSingleShot(true);
    connect(&m_retry, &QTimer::timeout, this, &SignalKClient::openSocket);

    connect(&m_socket, &QWebSocket::connected, this, [this] {
        m_retryDelay = 1000;
        setState(Connected, tr("Connected to %1").arg(m_server));
    });
    connect(&m_socket, &QWebSocket::disconnected, this, [this] {
        if (m_mode != Live)
            return;
        const QString why = m_socket.errorString();
        setState(Error, tr("Disconnected%1 — retrying in %2 s")
                            .arg(why.isEmpty() ? QString() : ": " + why)
                            .arg(m_retryDelay / 1000));
        m_retry.start(m_retryDelay);
        m_retryDelay = qMin(m_retryDelay * 2, 30000);
    });
    connect(&m_socket, &QWebSocket::textMessageReceived, this, &SignalKClient::handleMessage);

    QTimer::singleShot(0, this, &SignalKClient::apply);
}

void SignalKClient::setMode(Mode m)
{
    if (m == m_mode)
        return;
    m_mode = m;
    QSettings().setValue("signalk/mode", m == Live ? "live" : "simulated");
    emit modeChanged();
    apply();
}

void SignalKClient::setServer(const QString &s)
{
    const QString trimmed = s.trimmed();
    if (trimmed == m_server)
        return;
    m_server = trimmed;
    QSettings().setValue("signalk/server", m_server);
    emit serverChanged();
    if (m_mode == Live)
        reconnect();
}

void SignalKClient::reconnect()
{
    m_retryDelay = 1000;
    apply();
}

QUrl SignalKClient::streamUrlFor(const QString &server)
{
    // Accept "host", "host:port", "http(s)://host:port" or a full ws:// URL.
    QString s = server.trimmed();
    if (!s.contains("://"))
        s.prepend("ws://");
    QUrl url(s);
    if (url.scheme() == "http")
        url.setScheme("ws");
    else if (url.scheme() == "https")
        url.setScheme("wss");
    if (url.port() == -1 && url.scheme() == "ws")
        url.setPort(3000);
    if (url.path().isEmpty() || url.path() == "/")
        url.setPath("/signalk/v1/stream");
    if (!url.hasQuery()) {
        QUrlQuery q;
        q.addQueryItem("subscribe", "self");
        url.setQuery(q);
    }
    return url;
}

void SignalKClient::apply()
{
    m_retry.stop();
    // Closing on purpose shouldn't trigger the auto-retry path.
    m_socket.blockSignals(true);
    m_socket.abort();
    m_socket.blockSignals(false);
    SignalKStore::instance()->clear();
    m_self.clear();
    m_version.clear();

    if (m_mode == Simulated) {
        m_sim->start();
        setState(Connected, tr("Simulated boat"));
    } else {
        m_sim->stop();
        openSocket();
    }
}

void SignalKClient::openSocket()
{
    if (m_mode != Live)
        return;
    const QUrl url = streamUrlFor(m_server);
    if (!url.isValid() || url.host().isEmpty()) {
        setState(Error, tr("Invalid server address"));
        return;
    }
    setState(Connecting, tr("Connecting to %1…").arg(url.toString()));
    m_socket.blockSignals(true);
    m_socket.abort();
    m_socket.blockSignals(false);
    m_socket.open(url);
}

void SignalKClient::setState(State s, const QString &text)
{
    if (s == m_state && text == m_statusText)
        return;
    m_state = s;
    m_statusText = text;
    emit stateChanged();
}

static void storeValue(SignalKStore *store, const QString &path, const QJsonValue &v,
                       qint64 now, const QString &source)
{
    // An empty path carries top-level vessel properties ({name, mmsi, ...}).
    if (path.isEmpty()) {
        if (!v.isObject())
            return;
        const QJsonObject o = v.toObject();
        for (auto it = o.begin(); it != o.end(); ++it)
            store->update(it.key(), it.value().toVariant(), now, source);
        return;
    }
    store->update(path, v.toVariant(), now, source);
}

void SignalKClient::handleMessage(const QString &message)
{
    const QJsonObject msg = QJsonDocument::fromJson(message.toUtf8()).object();
    if (msg.isEmpty())
        return;

    if (msg.contains("self") && !msg.contains("updates")) { // hello
        m_self = msg.value("self").toString();
        m_version = msg.value("version").toString();
        m_state = Idle; // force the notify so selfId/serverVersion refresh
        setState(Connected, tr("Connected to %1 (Signal K %2)").arg(m_server, m_version));
        return;
    }

    const QString context = msg.value("context").toString();
    if (!context.isEmpty() && !m_self.isEmpty() && context != m_self && context != "vessels.self")
        return; // other vessels (AIS) are ignored for now

    // We stamp with local receive time: a boat's server clock is often off,
    // and staleness/plots should reflect when we heard about it.
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    SignalKStore *store = SignalKStore::instance();
    for (const QJsonValue &u : msg.value("updates").toArray()) {
        const QJsonObject update = u.toObject();
        const QString source = update.value("$source").toString();
        for (const QJsonValue &pv : update.value("values").toArray()) {
            const QJsonObject o = pv.toObject();
            storeValue(store, o.value("path").toString(), o.value("value"), now, source);
        }
    }
}
