#pragma once

#include <QObject>
#include <QProcess>
#include <QStringList>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

class QQmlEngine;
class QJSEngine;

// The app's Neovim: a child process (`nvim --embed`) spoken to with msgpack-RPC
// over its stdin/stdout. NvimView draws what it sends and feeds it keys.
//
//   nvim → app  nvim/lua/fernedda.lua reports the path under the cursor in oil
//               (or the file being edited) with rpcnotify. → focused(path)
//   app → nvim  reveal / openFolder / insert call into the same Lua module.
//
// Exposed to QML as the `Nvim` singleton.
class NvimLink : public QObject {
    Q_OBJECT
    QML_NAMED_ELEMENT(Nvim)
    QML_SINGLETON
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)

public:
    static NvimLink *instance();
    static NvimLink *create(QQmlEngine *, QJSEngine *);

    bool running() const { return m_running; }

    // Start nvim on the boat folder, unless it's already up.
    Q_INVOKABLE void launch(const QString &root);
    // Show a folder in oil with the cursor on it (or open a file).
    Q_INVOKABLE void reveal(const QString &absPath);
    // Open a folder in oil, even from a note being edited (which stays open).
    Q_INVOKABLE void openFolder(const QString &absPath);
    // Put Markdown lines below the cursor in the note being edited.
    Q_INVOKABLE void insert(const QString &text);
    // A touch box was tapped: an oil entry's name, ".." for up, or anything
    // while editing a file to go back to its folder.
    Q_INVOKABLE void tap(const QString &name);
    // The window wants to close. True: go ahead. False: nvim is quitting first
    // (it asks about unsaved notes) and the app quits when it has. A second
    // close while that's pending stops nvim, leaving its swap files to recover.
    Q_INVOKABLE bool requestQuit();

    // For NvimView.
    void resizeUi(int cols, int rows);
    void input(const QString &keys);
    void inputMouse(const QString &button, const QString &action, const QString &mods, int row, int col);
    void setUiFocus(bool focused);

signals:
    void focused(const QString &absPath);
    void runningChanged();
    void attention();                       // nvim is asking something: show it
    void redraw(const QVariantList &events);
    void tiles(const QString &json);        // where the touch boxes go (see fernedda.lua)
    void transparentChanged(bool transparent);  // the colorscheme sets no background

private:
    explicit NvimLink(QObject *parent = nullptr);
    void onOutput();
    void onFinished();
    void onMessage(const QVariantList &message);
    void notify(const QString &method, const QVariantList &params);
    void call(const QString &fn, const QString &arg);

    QProcess m_process;
    QByteArray m_buffer;       // output not yet decoded
    QStringList m_queue;       // Lua calls waiting for the module to load
    int m_cols = 80, m_rows = 24;
    bool m_running = false;
    bool m_attached = false;
    bool m_ready = false;      // the Lua module has loaded
    bool m_quitting = false;
};
