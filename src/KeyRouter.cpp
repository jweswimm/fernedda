#include "KeyRouter.h"

#include <QJSEngine>
#include <QKeyEvent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTimer>

KeyRouter *KeyRouter::create(QQmlEngine *, QJSEngine *)
{
    static KeyRouter *s = new KeyRouter;
    QJSEngine::setObjectOwnership(s, QJSEngine::CppOwnership);
    return s;
}

KeyRouter::KeyRouter(QObject *parent) : QObject(parent) {}

void KeyRouter::attach(QQuickWindow *window)
{
    if (m_window)
        m_window->removeEventFilter(this);
    m_window = window;
    if (!window)
        return;
    window->installEventFilter(this);
    connect(window, &QQuickWindow::activeFocusItemChanged, this, &KeyRouter::updateMode);
    updateMode();
}

bool KeyRouter::focusIsText() const
{
    const QQuickItem *item = m_window ? m_window->activeFocusItem() : nullptr;
    return item && (item->inherits("QQuickTextInput") || item->inherits("QQuickTextEdit"))
        && !item->property("readOnly").toBool();
}

bool KeyRouter::focusIsEditor() const
{
    const QQuickItem *item = m_window ? m_window->activeFocusItem() : nullptr;
    return item && item->inherits("NvimView");
}

void KeyRouter::updateMode()
{
    const bool insert = focusIsText();
    if (insert != m_insert) {
        m_insert = insert;
        emit insertModeChanged();
    }
    const bool editor = focusIsEditor();
    if (editor != m_editor) {
        m_editor = editor;
        emit editorModeChanged();
    }
}

void KeyRouter::release()
{
    if (!m_window || !m_window->contentItem())
        return;
    // Focusing the root alone hands focus back to whichever item last had it.
    if (QQuickItem *item = m_window->activeFocusItem())
        item->setFocus(false);
    m_window->contentItem()->forceActiveFocus();
}

bool KeyRouter::eventFilter(QObject *obj, QEvent *event)
{
    if (event->type() != QEvent::KeyPress || obj != m_window)
        return QObject::eventFilter(obj, event);
    auto *ke = static_cast<QKeyEvent *>(event);

    const bool ctrl = ke->modifiers() == Qt::ControlModifier;
    const bool toggle = ctrl && ke->key() == Qt::Key_T;
    const bool swap = (ctrl && ke->key() == Qt::Key_Semicolon)
        || (ke->modifiers() == Qt::AltModifier && ke->key() == Qt::Key_Tab);
    if (toggle || swap) {
        if (!focusIsText()) {     // not while typing in a field or a prompt
            if (toggle)
                emit togglePane();
            else
                emit switchPane();
        }
        return true;
    }
    if (focusIsEditor())
        return false;

    if (focusIsText()) {
        // Let the field (or its popup) see Escape first, then leave the field.
        if (ke->key() == Qt::Key_Escape)
            QTimer::singleShot(0, this, [this] { if (focusIsText()) release(); });
        return false;
    }

    const Qt::KeyboardModifiers mods = ke->modifiers() & ~(Qt::ShiftModifier | Qt::KeypadModifier);
    if (mods != Qt::NoModifier)
        return false;

    QString token;
    switch (ke->key()) {
    case Qt::Key_Return: case Qt::Key_Enter: token = "Enter"; break;
    case Qt::Key_Escape: token = "Escape"; break;
    case Qt::Key_Backspace: token = "Backspace"; break;
    case Qt::Key_Tab: token = "Tab"; break;
    case Qt::Key_Up: token = "Up"; break;
    case Qt::Key_Down: token = "Down"; break;
    case Qt::Key_Left: token = "Left"; break;
    case Qt::Key_Right: token = "Right"; break;
    case Qt::Key_Space: token = "Space"; break;
    default:
        token = ke->text();
        if (token.size() != 1 || !token.at(0).isPrint())
            return false;
    }
    m_accepted = false;
    emit key(token);
    return m_accepted;
}
