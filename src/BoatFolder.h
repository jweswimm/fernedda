#pragma once

#include <QFileSystemWatcher>
#include <QObject>
#include <QStringList>
#include <QTimer>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

class QQmlEngine;
class QJSEngine;

// The boat as a plain folder tree, one folder per part of the boat with its
// category folders inside, browsed and edited in Neovim:
//
//   boat/<view>/<zone>/Documentation/     e.g. boat/below/engine/Plans/
//
// The tree is watched, so anything made in oil (or anywhere) shows up live.
// Exposed to QML as the `BoatFolder` singleton.
class BoatFolder : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    // Bumps on every change, so bindings that call isFolder() and fileCount() refresh.
    Q_PROPERTY(int revision READ revision NOTIFY changed)
    Q_PROPERTY(QString root READ root CONSTANT)

public:
    static BoatFolder *create(QQmlEngine *, QJSEngine *);

    int revision() const { return m_revision; }
    QString root() const { return m_root; }

    // Called once from QML with the boat drawing's zones ("below/engine", ...).
    Q_INVOKABLE void setZones(const QStringList &zones);
    // Make a folder (relative to the root) if it's missing. False if that failed.
    Q_INVOKABLE bool makeFolder(const QString &rel);
    // Files anywhere under a folder.
    Q_INVOKABLE int fileCount(const QString &rel) const;
    // Every folder and file under a folder, parents before children:
    // [{ path, name, dir, depth }] with depth 1 for direct children.
    Q_INVOKABLE QVariantList entries(const QString &rel) const;

    // Paths: relative ↔ absolute ("" when outside the boat folder).
    Q_INVOKABLE QString absPath(const QString &rel) const;
    Q_INVOKABLE QString relPath(const QString &abs) const;
    Q_INVOKABLE bool isFolder(const QString &rel) const;

signals:
    void changed();

private:
    explicit BoatFolder(QObject *parent = nullptr);
    void scan();
    void scanDir(const QString &rel, int depth, QStringList &dirs);

    QString m_root;
    QStringList m_files;       // relative to the root
    QStringList m_dirs;        // relative to the root
    int m_revision = 0;
    QFileSystemWatcher m_watcher;
    QTimer m_rescan;
};
