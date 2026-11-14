#include "BoatFolder.h"

#include <QDir>
#include <QFileInfo>
#include <QJSEngine>
#include <QQmlEngine>
#include <algorithm>

#ifndef FERNEDDA_SOURCE_DIR
#define FERNEDDA_SOURCE_DIR "."
#endif

BoatFolder *BoatFolder::create(QQmlEngine *, QJSEngine *)
{
    static BoatFolder *s = new BoatFolder;
    QJSEngine::setObjectOwnership(s, QJSEngine::CppOwnership);
    return s;
}

BoatFolder::BoatFolder(QObject *parent) : QObject(parent)
{
    const QByteArray env = qgetenv("FERNEDDA_BOAT_DIR");
    m_root = QDir::cleanPath(env.isEmpty() ? QStringLiteral(FERNEDDA_SOURCE_DIR "/boat") : QString::fromLocal8Bit(env));
    QDir().mkpath(m_root);

    m_rescan.setSingleShot(true);
    m_rescan.setInterval(120);
    connect(&m_rescan, &QTimer::timeout, this, &BoatFolder::scan);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, &m_rescan, qOverload<>(&QTimer::start));

    scan();
}

void BoatFolder::scanDir(const QString &rel, int depth, QStringList &dirs)
{
    const QDir dir(absPath(rel));
    dirs << dir.absolutePath();
    for (const QFileInfo &fi : dir.entryInfoList(QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot)) {
        const QString child = rel.isEmpty() ? fi.fileName() : rel + "/" + fi.fileName();
        if (!fi.isDir()) {
            m_files << child;
        } else if (depth < 8) {
            m_dirs << child;
            scanDir(child, depth + 1, dirs);
        }
    }
}

void BoatFolder::scan()
{
    m_files.clear();
    m_dirs.clear();
    QStringList dirs;
    scanDir({}, 0, dirs);

    // Watch exactly what's there now.
    if (const QStringList watched = m_watcher.directories(); !watched.isEmpty())
        m_watcher.removePaths(watched);
    m_watcher.addPaths(dirs);

    ++m_revision;
    emit changed();
}

void BoatFolder::setZones(const QStringList &zones)
{
    for (const QString &zone : zones)
        QDir().mkpath(absPath(zone));
    scan();
}

bool BoatFolder::makeFolder(const QString &rel)
{
    if (!QDir().mkpath(absPath(rel))) {
        qWarning("fernedda: couldn't make %s", qPrintable(absPath(rel)));
        return false;
    }
    scan();
    return true;
}

int BoatFolder::fileCount(const QString &rel) const
{
    const QString prefix = rel + "/";
    return int(std::count_if(m_files.begin(), m_files.end(), [&](const QString &f) { return f.startsWith(prefix); }));
}

QVariantList BoatFolder::entries(const QString &rel) const
{
    const QString prefix = rel + "/";
    QList<QPair<QString, bool>> found;
    for (const QString &d : m_dirs)
        if (d.startsWith(prefix))
            found.append({d, true});
    for (const QString &f : m_files)
        if (f.startsWith(prefix))
            found.append({f, false});
    // Folders first among siblings, then by name; a parent sorts before its children.
    std::sort(found.begin(), found.end(), [](const auto &a, const auto &b) {
        const QStringList pa = a.first.split('/'), pb = b.first.split('/');
        for (qsizetype i = 0; i < std::min(pa.size(), pb.size()); ++i) {
            if (pa[i] == pb[i])
                continue;
            const bool da = i < pa.size() - 1 || a.second, db = i < pb.size() - 1 || b.second;
            if (da != db)
                return da;
            return pa[i].compare(pb[i], Qt::CaseInsensitive) < 0;
        }
        return pa.size() < pb.size();
    });

    const int base = int(rel.count('/'));
    QVariantList out;
    for (const auto &[path, dir] : found)
        out << QVariantMap{{"path", path}, {"name", path.section('/', -1)}, {"dir", dir},
                           {"depth", int(path.count('/')) - base}};
    return out;
}

QString BoatFolder::absPath(const QString &rel) const
{
    return rel.isEmpty() ? m_root : m_root + "/" + rel;
}

QString BoatFolder::relPath(const QString &abs) const
{
    const QString p = QDir::cleanPath(abs);
    if (p == m_root)
        return QStringLiteral(".");
    if (!p.startsWith(m_root + "/"))
        return {};
    return p.mid(m_root.size() + 1);
}

bool BoatFolder::isFolder(const QString &rel) const
{
    return QFileInfo(absPath(rel)).isDir();
}
