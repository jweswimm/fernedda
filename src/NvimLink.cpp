#include "NvimLink.h"

#include "Msgpack.h"

#include <QCoreApplication>
#include <QDir>
#include <QJSEngine>
#include <QQmlEngine>

#ifndef FERNEDDA_SOURCE_DIR
#define FERNEDDA_SOURCE_DIR "."
#endif

NvimLink *NvimLink::instance()
{
    static NvimLink *s = new NvimLink;
    return s;
}

NvimLink *NvimLink::create(QQmlEngine *, QJSEngine *)
{
    NvimLink *s = instance();
    QJSEngine::setObjectOwnership(s, QJSEngine::CppOwnership);
    return s;
}

NvimLink::NvimLink(QObject *parent) : QObject(parent)
{
    m_process.setProcessChannelMode(QProcess::ForwardedErrorChannel);
    connect(&m_process, &QProcess::readyReadStandardOutput, this, &NvimLink::onOutput);
    connect(&m_process, &QProcess::started, this, [this] {
        notify("nvim_ui_attach", {m_cols, m_rows, QVariantMap{{"ext_linegrid", true}, {"rgb", true}}});
        m_attached = true;
    });
    connect(&m_process, &QProcess::finished, this, &NvimLink::onFinished);
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        qWarning("fernedda: couldn't start nvim: %s", qPrintable(m_process.errorString()));
        onFinished();
    });
}

void NvimLink::launch(const QString &root)
{
    if (m_running)
        return;
    // Load the module by path: plugin managers (lazy.nvim) reset 'runtimepath'.
    const QString setup = QStringLiteral("lua package.path = [[%1/nvim/lua/?.lua;]] .. package.path; "
                                         "require('fernedda').setup({ root = [[%2]] })")
                              .arg(FERNEDDA_SOURCE_DIR, root);
    m_running = true;
    emit runningChanged();
    m_process.setWorkingDirectory(root);
    m_process.start("nvim", {"--embed", "-c", setup, root});
}

bool NvimLink::requestQuit()
{
    if (!m_running)
        return true;
    if (m_quitting) {
        m_process.terminate();
        return true;
    }
    m_quitting = true;
    call("quit", QString());
    return false;
}

void NvimLink::onFinished()
{
    const bool quit = m_quitting;
    m_running = m_attached = m_ready = m_quitting = false;
    m_buffer.clear();
    m_queue.clear();
    emit runningChanged();
    if (quit)
        QCoreApplication::quit();
}

void NvimLink::onOutput()
{
    m_buffer += m_process.readAllStandardOutput();
    qsizetype pos = 0;
    QVariant message;
    while (Msgpack::decode(m_buffer, pos, message))
        onMessage(message.toList());
    m_buffer.remove(0, pos);
}

void NvimLink::onMessage(const QVariantList &message)
{
    const int type = message.value(0).toInt();
    if (type == 0) {
        // Something asked us for an answer we don't have; don't leave it hanging.
        const QString method = message.value(2).toString();
        QByteArray out;
        Msgpack::encode(out, QVariantList{1, message.value(1), QVariantList{0, "fernedda has no " + method}, QVariant()});
        m_process.write(out);
        return;
    }
    if (type != 2)
        return;

    const QString method = message.value(1).toString();
    const QVariantList params = message.value(2).toList();
    if (method == "redraw") {
        emit redraw(params);
    } else if (method == "fernedda") {
        const QString cmd = params.value(0).toString();
        const QString arg = params.value(1).toString();
        if (cmd == "focus" && !arg.isEmpty()) {
            emit focused(QDir::cleanPath(arg));
        } else if (cmd == "ready") {
            m_ready = true;
            const QStringList queued = std::exchange(m_queue, {});
            for (const QString &code : queued)
                notify("nvim_exec_lua", {code, QVariantList{}});
        } else if (cmd == "moved") {
            emit moved(arg);
        } else if (cmd == "tiles") {
            emit tiles(arg);
        } else if (cmd == "transparent") {
            emit transparentChanged(arg == "1");
        } else if (cmd == "attention") {
            emit attention();
        } else if (cmd == "quit_cancelled") {
            m_quitting = false;
        }
    } else if (method == "nvim_error_event") {
        qWarning("fernedda: nvim: %s", qPrintable(params.value(1).toString()));
    }
}

void NvimLink::notify(const QString &method, const QVariantList &params)
{
    QByteArray out;
    Msgpack::encode(out, QVariantList{2, method, params});
    m_process.write(out);
}

void NvimLink::call(const QString &fn, const QString &arg)
{
    if (!m_running)
        return;
    // Base64 keeps any path or text from being read as Lua.
    const QString code = QStringLiteral("require('fernedda').%1(vim.base64.decode('%2'))")
                             .arg(fn, QString::fromLatin1(arg.toUtf8().toBase64()));
    if (m_ready)
        notify("nvim_exec_lua", {code, QVariantList{}});
    else
        m_queue.append(code);
}

void NvimLink::reveal(const QString &absPath) { call("reveal", absPath); }
void NvimLink::openFolder(const QString &absPath) { call("open_folder", absPath); }
void NvimLink::insert(const QString &text) { call("insert", text); }
void NvimLink::tap(const QString &name) { call("tap", name); }

void NvimLink::resizeUi(int cols, int rows)
{
    m_cols = cols;
    m_rows = rows;
    if (m_attached)
        notify("nvim_ui_try_resize", {cols, rows});
}

void NvimLink::input(const QString &keys)
{
    if (m_attached)
        notify("nvim_input", {keys});
}

void NvimLink::inputMouse(const QString &button, const QString &action, const QString &mods, int row, int col)
{
    if (m_attached)
        notify("nvim_input_mouse", {button, action, mods, 0, row, col});
}

void NvimLink::setUiFocus(bool focused)
{
    if (m_attached)
        notify("nvim_ui_set_focus", {focused});
}
