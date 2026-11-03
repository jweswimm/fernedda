#pragma once

#include <QLocalServer>
#include <QObject>
#include <QtQml/qqmlregistration.h>

class QQmlEngine;
class QJSEngine;

// Two-way link with a Neovim running in a terminal beside the app.
//
//   nvim → app  nvim/lua/fernedda.lua reports the path under the cursor in oil
//               (or the file being edited) over $XDG_RUNTIME_DIR/fernedda.sock,
//               one line per move: "focus\t/abs/path". → focused(path)
//   app → nvim  `nvim --server <sock> --remote-expr` calls into the same Lua
//               module (goto / edit / insert). Arguments travel base64-encoded.
//
// launch() opens the terminal (alacritty by default, or $FERNEDDA_TERMINAL)
// running nvim on the boat folder with the module loaded; sway tiles it
// beside the app.
//
// Exposed to QML as the `Nvim` singleton.
class NvimLink : public QObject {
    Q_OBJECT
    QML_NAMED_ELEMENT(Nvim)
    QML_SINGLETON
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)

public:
    static NvimLink *create(QQmlEngine *, QJSEngine *);

    bool running() const { return m_running; }

    // Open the terminal, or focus it if it's already up.
    Q_INVOKABLE void launch(const QString &root);
    Q_INVOKABLE void focusTerminal();
    // Show a folder in oil with the cursor on it (or open a file) — keeps focus here.
    Q_INVOKABLE void reveal(const QString &absPath);
    // Open a file for editing and move keyboard focus to the terminal.
    Q_INVOKABLE void edit(const QString &absPath);
    // Put Markdown lines below the cursor in the note being edited.
    Q_INVOKABLE void insert(const QString &text);

signals:
    void focused(const QString &absPath);
    void runningChanged();

private:
    explicit NvimLink(QObject *parent = nullptr);
    void onConnection();
    void call(const QString &fn, const QString &arg);
    void check();

    QLocalServer m_server;
    QString m_pendingEdit;   // opened once a just-launched nvim is listening
    int m_waits = 0;
    QString m_appSock, m_nvimSock;
    bool m_running = false;
};
