#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QTimer>
#include <QKeyEvent>
#include <QKeySequence>
#include <QSurfaceFormat>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setOrganizationName("fernedda");
    app.setApplicationName("fernedda");
    app.setApplicationDisplayName("fernedda");
    app.setDesktopFileName("fernedda");

    // Multisampling keeps the gauge arcs and shapes smooth.
    QSurfaceFormat fmt = QSurfaceFormat::defaultFormat();
    fmt.setSamples(4);
    QSurfaceFormat::setDefaultFormat(fmt);

    // Our own look on top of the plain, fully customizable Basic style.
    QQuickStyle::setStyle("Basic");

    QQmlApplicationEngine engine;
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app,
                     [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("Fernedda", "Main");

    // FERNEDDA_SCREENSHOT=out.png [FERNEDDA_SCREENSHOT_DELAY=ms]: render, save a
    // screenshot and quit. Handy for checking layouts without a display.
    if (const QByteArray shot = qgetenv("FERNEDDA_SCREENSHOT"); !shot.isEmpty()) {
        const int delay = qEnvironmentVariableIntValue("FERNEDDA_SCREENSHOT_DELAY");
        QTimer::singleShot(delay > 0 ? delay : 2500, &app, [&engine, shot] {
            if (auto *w = qobject_cast<QQuickWindow *>(engine.rootObjects().value(0)))
                w->grabWindow().save(QString::fromLocal8Bit(shot));
            QCoreApplication::quit();
        });
    }
    // FERNEDDA_KEYS="J J f a": type these keys (space-separated; names like
    // Escape or Return work too) from 1.5 s on, for testing the keyboard
    // without a display. Pairs well with FERNEDDA_SCREENSHOT.
    if (const QString keys = qEnvironmentVariable("FERNEDDA_KEYS"); !keys.isEmpty()) {
        int at = 1500;
        for (const QString &tok : keys.split(' ', Qt::SkipEmptyParts)) {
            QTimer::singleShot(at, &app, [&engine, tok] {
                auto *w = qobject_cast<QQuickWindow *>(engine.rootObjects().value(0));
                if (!w) return;
                const bool single = tok.size() == 1;
                const int code = single ? QKeySequence::fromString(tok.toUpper())[0].key()
                                        : QKeySequence::fromString(tok)[0].key();
                const auto mods = single && tok.at(0).isUpper() ? Qt::ShiftModifier : Qt::NoModifier;
                QKeyEvent press(QEvent::KeyPress, code, mods, single ? tok : QString());
                QKeyEvent release(QEvent::KeyRelease, code, mods, single ? tok : QString());
                QCoreApplication::sendEvent(w, &press);
                QCoreApplication::sendEvent(w, &release);
            });
            at += 300;
        }
    }
    return app.exec();
}
