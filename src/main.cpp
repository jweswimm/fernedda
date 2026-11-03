#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QTimer>
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
    return app.exec();
}
