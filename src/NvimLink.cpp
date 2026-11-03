#include "NvimLink.h"

#include <QDir>
#include <QFileInfo>
#include <QJSEngine>
#include <QLocalSocket>
#include <QProcess>
#include <QQmlEngine>
#include <QStandardPaths>
#include <QTimer>

#ifndef FERNEDDA_SOURCE_DIR
#define FERNEDDA_SOURCE_DIR "."
#endif

namespace {
const char *kAppId = "fernedda-nvim";
}

NvimLink *NvimLink::create(QQmlEngine *, QJSEngine *)
{
    static NvimLink *s = new NvimLink;
    QJSEngine::setObjectOwnership(s, QJSEngine::CppOwnership);
    return s;
}

NvimLink::NvimLink(QObject *parent) : QObject(parent)
{
    QString dir = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    if (dir.isEmpty()) dir = QDir::tempPath();
    m_appSock = dir + "/fernedda.sock";
    m_nvimSock = dir + "/fernedda-nvim.sock";

    QLocalServer::removeServer(m_appSock);
    connect(&m_server, &QLocalServer::newConnection, this, &NvimLink::onConnection);
    m_server.listen(m_appSock);

    // Notice nvim coming and going (it may outlive or predate the app).
    auto *poll = new QTimer(this);
    poll->setInterval(2000);
    connect(poll, &QTimer::timeout, this, &NvimLink::check);
    poll->start();
    check();
}

void NvimLink::check()
{
    bool alive = false;
    if (QFileInfo::exists(m_nvimSock)) {
        QLocalSocket probe;
        probe.connectToServer(m_nvimSock);
        alive = probe.waitForConnected(150);
        probe.abort();
    }
    if (alive != m_running) {
        m_running = alive;
        emit runningChanged();
    }
}

void NvimLink::onConnection()
{
    while (QLocalSocket *sock = m_server.nextPendingConnection()) {
        connect(sock, &QLocalSocket::disconnected, sock, &QObject::deleteLater);
        connect(sock, &QLocalSocket::readyRead, this, [this, sock] {
            while (sock->canReadLine()) {
                const QString line = QString::fromUtf8(sock->readLine()).trimmed();
                const int tab = line.indexOf('\t');
                const QString cmd = tab < 0 ? line : line.left(tab);
                const QString arg = tab < 0 ? QString() : line.mid(tab + 1);
                if (cmd == "focus" && !arg.isEmpty())
                    emit focused(QDir::cleanPath(arg));
            }
        });
        if (!m_running) { m_running = true; emit runningChanged(); }
    }
}

void NvimLink::launch(const QString &root)
{
    check();
    if (m_running) {
        focusTerminal();
        return;
    }
    QFile::remove(m_nvimSock); // stale socket from a crashed nvim
    // Load the module by path: plugin managers (lazy.nvim) reset 'runtimepath'.
    const QString setup = QStringLiteral("lua package.path = [[%1/nvim/lua/?.lua;]] .. package.path; "
                                         "require('fernedda').setup({ socket = [[%2]], root = [[%3]] })")
                              .arg(FERNEDDA_SOURCE_DIR, m_appSock, root);
    QStringList nvim = {"nvim", "--listen", m_nvimSock, "-c", setup, root};

    QStringList cmd;
    const QString custom = qEnvironmentVariable("FERNEDDA_TERMINAL");
    if (!custom.isEmpty())
        cmd = QProcess::splitCommand(custom);   // e.g. "foot -a fernedda-nvim -e"
    else
        cmd = {"alacritty", "--class", kAppId, "--working-directory", root, "-e"};
    const QString program = cmd.takeFirst();
    QProcess::startDetached(program, cmd + nvim, root);
    QTimer::singleShot(1200, this, &NvimLink::check);
}

void NvimLink::focusTerminal()
{
    QProcess::startDetached("swaymsg", {QStringLiteral("[app_id=\"%1\"] focus").arg(kAppId)});
}

void NvimLink::call(const QString &fn, const QString &arg)
{
    if (!QFileInfo::exists(m_nvimSock))
        return;
    const QString b64 = QString::fromLatin1(arg.toUtf8().toBase64());
    const QString expr = QStringLiteral("luaeval(\"require('fernedda').%1(_A)\", '%2')").arg(fn, b64);
    QProcess::startDetached("nvim", {"--server", m_nvimSock, "--remote-expr", expr});
}

void NvimLink::reveal(const QString &absPath) { call("reveal", absPath); }

void NvimLink::edit(const QString &absPath)
{
    if (QFileInfo::exists(m_nvimSock)) {
        call("edit", absPath);
        focusTerminal();
        return;
    }
    // nvim is starting (or about to): try again until it listens, up to ~6 s.
    const bool waiting = !m_pendingEdit.isEmpty();
    m_pendingEdit = absPath;
    m_waits = 0;
    if (waiting)
        return;
    auto *retry = new QTimer(this);
    retry->setInterval(200);
    connect(retry, &QTimer::timeout, this, [this, retry] {
        if (QFileInfo::exists(m_nvimSock) || ++m_waits > 30) {
            const QString path = m_pendingEdit;
            m_pendingEdit.clear();
            retry->deleteLater();
            if (QFileInfo::exists(m_nvimSock)) {
                // Give the module a moment to load after the socket appears.
                QTimer::singleShot(300, this, [this, path] { call("edit", path); focusTerminal(); });
            }
        }
    });
    retry->start();
}

void NvimLink::insert(const QString &text) { call("insert", text); }
