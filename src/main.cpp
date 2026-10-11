#include "MainWindow.h"

#include <QApplication>
#include <QFileInfo>
#include <QProxyStyle>
#include <QStyleFactory>
#include <QStyleHints>

namespace {

// Fusion, but sidebar items open on a single click.
class Style : public QProxyStyle {
public:
    Style() : QProxyStyle(QStyleFactory::create("Fusion")) {}
    int styleHint(StyleHint hint, const QStyleOption *opt, const QWidget *w, QStyleHintReturn *ret) const override
    {
        if (hint == SH_ItemView_ActivateItemOnSingleClick)
            return 1;
        return QProxyStyle::styleHint(hint, opt, w, ret);
    }
};

struct Theme {
    QColor bg, panel, fg, muted, line, accent, hover, hs;
};

bool wantDark()
{
    const QString env = qEnvironmentVariable("FERNEDDA_THEME");
    if (env == "light")
        return false;
    if (env == "dark")
        return true;
    // Window managers like sway often don't report a scheme; default to dark there.
    return QGuiApplication::styleHints()->colorScheme() != Qt::ColorScheme::Light;
}

void applyTheme(QApplication &app)
{
    const Theme t = wantDark()
        ? Theme{"#121212", "#1a1a1a", "#ececec", "#8a8a8e", "#2a2a2a", "#6b9bff", "#232323", "#2a3550"}
        : Theme{"#f5f5f3", "#ffffff", "#1d1d1f", "#86868b", "#e5e5e2", "#2f6fed", "#f0f0ed", "#dfe8fc"};

    QPalette p;
    p.setColor(QPalette::Window, t.bg);
    p.setColor(QPalette::WindowText, t.fg);
    p.setColor(QPalette::Base, t.panel);
    p.setColor(QPalette::AlternateBase, t.hover);
    p.setColor(QPalette::Text, t.fg);
    p.setColor(QPalette::Button, t.panel);
    p.setColor(QPalette::ButtonText, t.fg);
    p.setColor(QPalette::Highlight, t.accent);
    p.setColor(QPalette::HighlightedText, Qt::white);
    p.setColor(QPalette::PlaceholderText, t.muted);
    p.setColor(QPalette::Mid, t.line);
    p.setColor(QPalette::ToolTipBase, t.panel);
    p.setColor(QPalette::ToolTipText, t.fg);
    app.setPalette(p);

    app.setStyleSheet(QString(R"(
        #header { background: %2; border-bottom: 1px solid %5; }
        QPushButton { background: %2; color: %3; border: 1px solid %5; border-radius: 8px; padding: 5px 12px; }
        QPushButton:hover { background: %7; }
        QPushButton[on="true"] { background: %6; border-color: %6; color: white; }
        QToolButton { color: %4; border: none; border-radius: 6px; padding: 4px 6px; }
        QToolButton:hover { background: %7; color: %3; }
        QToolButton[crumb="last"] { color: %3; font-weight: 600; }
        QLabel#sep { color: %5; }
        #side { background: %2; border-left: 1px solid %5; }
        QListWidget { background: %2; outline: none; padding: 6px; }
        QListWidget::item { padding: 5px 6px; border-radius: 7px; color: %3; }
        QListWidget::item:hover { background: %7; }
        QListWidget::item:selected { background: %8; color: %3; }
        QLabel#hint { padding: 10px 14px; color: %6; background: %8; border-bottom: 1px solid %5; }
        QLabel#hint[ask="true"] { font-weight: 600; }
        QLabel#toast { background: %3; color: %1; padding: 8px 14px; border-radius: 8px; }
        QSplitter::handle { background: %5; }
        #landing, QDialog { background: %1; }
        QLabel#title { font-size: 26pt; font-weight: 700; color: %3; }
        QLabel#subtitle { color: %4; }
        QLabel#section { color: %4; font-size: 9pt; font-weight: 600; }
        QLabel#empty { color: %4; padding: 24px; border: 1px dashed %5; border-radius: 10px; }
        QLabel#error { color: #d9534f; }
        QPushButton#primary, QPushButton#big { padding: 10px 18px; border-radius: 10px; font-weight: 600; }
        QPushButton#primary { background: %6; border-color: %6; color: white; }
        QPushButton#primary:hover { background: %6; border-color: %3; }
        QPushButton#primary:disabled { background: %5; border-color: %5; color: %4; }
        QListWidget#recent { background: transparent; padding: 0; }
        QLineEdit { background: %2; color: %3; border: 1px solid %5; border-radius: 7px; padding: 6px 8px;
                    selection-background-color: %6; }
        QLineEdit:focus { border-color: %6; }
        QMenu { background: %2; color: %3; border: 1px solid %5; padding: 4px; }
        QMenu::item { padding: 6px 14px; border-radius: 5px; }
        QMenu::item:selected { background: %7; }
    )")
                          .arg(t.bg.name(), t.panel.name(), t.fg.name(), t.muted.name(), t.line.name(),
                               t.accent.name(), t.hover.name(), t.hs.name()));
}

}

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);
    QApplication::setApplicationName("fernedda");
    QApplication::setDesktopFileName("fernedda");
    app.setStyle(new Style);
    applyTheme(app);

    // `fernedda some.fernedda` opens that project straight away.
    const QStringList args = app.arguments();
    MainWindow w(args.size() > 1 ? QFileInfo(args[1]).absoluteFilePath() : QString());
    w.show();
    return app.exec();
}
