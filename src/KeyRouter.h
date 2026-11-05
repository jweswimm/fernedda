#pragma once

#include <QObject>
#include <QPointer>
#include <QtQml/qqmlregistration.h>

class QQmlEngine;
class QJSEngine;
#include <QQuickWindow>

// Vim-style modal keyboard for the whole window.
//
// Insert mode: a text field has focus; keys go to it as usual, and Escape
// leaves the field. Normal mode: every unmodified key is offered to QML first
// as a token ("j", "G", "Enter", "Escape", …) through key(); a handler that
// uses it calls accept(), and the key goes no further. Keys with Ctrl/Alt/Super
// always pass through, so existing shortcuts keep working.
//
// Editor mode: the Neovim pane has focus and gets every key, except those the app
// always keeps: Alt+Tab or Ctrl+; switches between the pane and the app
// (switchPane()), and Ctrl+T shows or hides the pane (togglePane()), so Neovim
// never sees them.
//
// Exposed to QML as the `Keyboard` singleton; Main.qml calls attach(window).
class KeyRouter : public QObject {
    Q_OBJECT
    QML_NAMED_ELEMENT(Keyboard)
    QML_SINGLETON
    Q_PROPERTY(bool insertMode READ insertMode NOTIFY insertModeChanged)
    Q_PROPERTY(bool editorMode READ editorMode NOTIFY editorModeChanged)

public:
    static KeyRouter *create(QQmlEngine *, QJSEngine *);

    bool insertMode() const { return m_insert; }
    bool editorMode() const { return m_editor; }
    Q_INVOKABLE void attach(QQuickWindow *window);
    Q_INVOKABLE void accept() { m_accepted = true; }
    // Drop focus from any text field (back to normal mode).
    Q_INVOKABLE void release();

signals:
    void key(const QString &token);
    void insertModeChanged();
    void editorModeChanged();
    void switchPane();
    void togglePane();

protected:
    bool eventFilter(QObject *obj, QEvent *event) override;

private:
    explicit KeyRouter(QObject *parent = nullptr);
    bool focusIsText() const;
    bool focusIsEditor() const;
    void updateMode();

    QPointer<QQuickWindow> m_window;
    bool m_accepted = false;
    bool m_insert = false;
    bool m_editor = false;
};
