#include "NotesModel.h"

#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJSEngine>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQmlEngine>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <algorithm>

#ifndef FERNEDDA_SOURCE_DIR
#define FERNEDDA_SOURCE_DIR "."
#endif

namespace {
const QStringList kDefaultSystems = {
    "Engine", "Electrical", "Rigging", "Sails", "Hull & Deck",
    "Plumbing", "Navigation", "Safety", "Interior", "General",
};

QString stripMarkdown(const QString &body)
{
    QString s = body;
    static const QRegularExpression heading(QStringLiteral("^#+\\s*"), QRegularExpression::MultilineOption);
    static const QRegularExpression marks(QStringLiteral("[*_`>|]|\\[ \\]|\\[x\\]"));
    static const QRegularExpression link(QStringLiteral("\\[([^\\]]*)\\]\\([^)]*\\)"));
    static const QRegularExpression rule(QStringLiteral("-{3,}"));
    static const QRegularExpression ws(QStringLiteral("\\s+"));
    s.replace(link, QStringLiteral("\\1"));
    s.remove(heading);
    s.remove(rule);
    s.remove(marks);
    s.replace(ws, QStringLiteral(" "));
    return s.trimmed().left(160);
}

// "raw-water_strainer" → "raw water strainer"
QString pretty(QString s)
{
    s.replace('-', ' ').replace('_', ' ');
    return s.trimmed();
}

// Split optional front-matter off a note. Returns the body; fills `meta`.
QString splitFrontMatter(const QString &text, QMap<QString, QString> &meta)
{
    if (!(text.startsWith("---\n") || text.startsWith("---\r\n")))
        return text;
    const int start = text.indexOf('\n') + 1;
    static const QRegularExpression fence(QStringLiteral("^---\\s*$"), QRegularExpression::MultilineOption);
    const int end = text.indexOf(fence, start);
    if (end < 0)
        return text;
    for (const QString &line : text.mid(start, end - start).split('\n')) {
        const int colon = line.indexOf(':');
        if (colon > 0)
            meta.insert(line.left(colon).trimmed().toLower(), line.mid(colon + 1).trimmed());
    }
    const int bodyStart = text.indexOf('\n', end);
    return bodyStart < 0 ? QString() : text.mid(bodyStart + 1);
}
} // namespace

// The body without a leading "# Title" line that just repeats the title.
QString NotesModel::withoutTitle(const Note &n)
{
    const QString head = "# " + n.title;
    if (!n.body.startsWith(head))
        return n.body;
    const int nl = n.body.indexOf('\n');
    if (nl < 0)
        return {};
    if (n.body.left(nl).trimmed() != head)
        return n.body;
    QString rest = n.body.mid(nl + 1);
    while (rest.startsWith('\n')) rest.remove(0, 1);
    return rest;
}

NotesModel *NotesModel::create(QQmlEngine *, QJSEngine *)
{
    static NotesModel *s = new NotesModel;
    QJSEngine::setObjectOwnership(s, QJSEngine::CppOwnership);
    return s;
}

NotesModel::NotesModel(QObject *parent) : QAbstractListModel(parent)
{
    const QByteArray env = qgetenv("FERNEDDA_BOAT_DIR");
    m_root = QDir::cleanPath(env.isEmpty() ? QStringLiteral(FERNEDDA_SOURCE_DIR "/boat") : QString::fromLocal8Bit(env));
    QDir().mkpath(m_root);

    m_rescan.setSingleShot(true);
    m_rescan.setInterval(120);
    connect(&m_rescan, &QTimer::timeout, this, &NotesModel::scan);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, &m_rescan, qOverload<>(&QTimer::start));
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, &m_rescan, qOverload<>(&QTimer::start));

    scan();
}

// ---- scanning ------------------------------------------------------------

void NotesModel::scanDir(const QString &rel, int depth, QStringList &dirs, QStringList &files)
{
    const QDir dir(m_root + (rel.isEmpty() ? QString() : "/" + rel));
    dirs << dir.absolutePath();
    for (const QFileInfo &fi : dir.entryInfoList(QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot, QDir::Name)) {
        if (fi.fileName().startsWith('.'))
            continue; // .trash, .place.json, editor swap files
        const QString childRel = rel.isEmpty() ? fi.fileName() : rel + "/" + fi.fileName();
        if (fi.isDir()) {
            if (depth == 2) { // view/zone/<spot>
                Spot sp;
                sp.id = childRel;
                sp.name = pretty(fi.fileName());
                sp.view = rel.section('/', 0, 0);
                sp.zone = rel;
                QFile place(fi.absoluteFilePath() + "/.place.json");
                if (place.open(QIODevice::ReadOnly)) {
                    const QJsonObject o = QJsonDocument::fromJson(place.readAll()).object();
                    if (o.contains("x") && o.contains("y")) {
                        sp.x = o.value("x").toDouble();
                        sp.y = o.value("y").toDouble();
                        sp.placed = true;
                    }
                }
                m_spots.append(sp);
            }
            if (depth < 8)
                scanDir(childRel, depth + 1, dirs, files);
        } else if (fi.suffix().compare("md", Qt::CaseInsensitive) == 0) {
            files << fi.absoluteFilePath();
            Note n;
            if (readNote(childRel, n))
                m_all.append(n);
        }
    }
}

bool NotesModel::readNote(const QString &rel, Note &n) const
{
    const QFileInfo fi(m_root + "/" + rel);
    QFile f(fi.absoluteFilePath());
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return false;
    QMap<QString, QString> meta;
    n.id = rel;
    n.location = rel.contains('/') ? rel.section('/', 0, -2) : QString();
    n.body = splitFrontMatter(QString::fromUtf8(f.readAll()), meta);
    n.title = meta.value("title");
    if (n.title.isEmpty()) {
        static const QRegularExpression h1(QStringLiteral("^#\\s+(.+)$"), QRegularExpression::MultilineOption);
        const auto m = h1.match(n.body);
        n.title = m.hasMatch() ? m.captured(1).trimmed() : pretty(fi.completeBaseName());
    }
    n.system = meta.value("system");
    if (n.system.isEmpty())
        n.system = m_zoneSystems.value(n.location.section('/', 0, 1), QStringLiteral("General")).toString();
    n.pinned = meta.value("pinned") == "true";
    for (const QString &t : meta.value("tags").split(',', Qt::SkipEmptyParts))
        if (!t.trimmed().isEmpty()) n.tags << t.trimmed();
    n.updated = fi.lastModified();
    n.created = QDateTime::fromString(meta.value("created"), Qt::ISODate);
    if (!n.created.isValid())
        n.created = fi.birthTime().isValid() ? fi.birthTime() : n.updated;
    return true;
}

void NotesModel::scan()
{
    m_all.clear();
    m_spots.clear();
    QStringList dirs, files;
    scanDir({}, 0, dirs, files);

    // Watch exactly what's there now.
    const QStringList watched = m_watcher.directories() + m_watcher.files();
    if (!watched.isEmpty())
        m_watcher.removePaths(watched);
    m_watcher.addPaths(dirs);
    if (!files.isEmpty())
        m_watcher.addPaths(files);

    emit spotsChanged();
    refreshSystems();
    refresh();
}

void NotesModel::setZones(const QVariantMap &zoneSystems)
{
    m_zoneSystems = zoneSystems;
    for (auto it = zoneSystems.begin(); it != zoneSystems.end(); ++it)
        QDir().mkpath(m_root + "/" + it.key());
    scan();
}

// ---- model ---------------------------------------------------------------

int NotesModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_visible.size();
}

QVariant NotesModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_visible.size())
        return {};
    const Note &n = m_all[m_visible[index.row()]];
    switch (role) {
    case IdRole: return n.id;
    case Qt::DisplayRole:
    case TitleRole: return n.title;
    case SystemRole: return n.system;
    case TagsRole: return n.tags;
    case PinnedRole: return n.pinned;
    case CreatedRole: return n.created;
    case UpdatedRole: return n.updated;
    case PreviewRole: return stripMarkdown(withoutTitle(n));
    case BodyRole: return withoutTitle(n);
    case LocationRole: return n.location;
    case PathRole: return absPath(n.id);
    }
    return {};
}

QHash<int, QByteArray> NotesModel::roleNames() const
{
    return {
        {IdRole, "noteId"}, {TitleRole, "title"}, {SystemRole, "system"},
        {TagsRole, "tags"}, {PinnedRole, "pinned"}, {CreatedRole, "created"},
        {UpdatedRole, "updated"}, {PreviewRole, "preview"}, {BodyRole, "body"},
        {LocationRole, "location"}, {PathRole, "path"},
    };
}

void NotesModel::setSystemFilter(const QString &s)
{
    if (s == m_systemFilter) return;
    m_systemFilter = s;
    emit filterChanged();
    refresh();
}

void NotesModel::setSearch(const QString &s)
{
    if (s == m_search) return;
    m_search = s;
    emit filterChanged();
    refresh();
}

void NotesModel::setLocationFilter(const QString &s)
{
    if (s == m_locationFilter) return;
    m_locationFilter = s;
    emit filterChanged();
    refresh();
}

bool NotesModel::inLocation(const Note &n, const QString &loc) const
{
    return loc.isEmpty() || n.location == loc || n.location.startsWith(loc + "/");
}

bool NotesModel::matches(const Note &n) const
{
    if (!m_systemFilter.isEmpty() && n.system != m_systemFilter)
        return false;
    if (!inLocation(n, m_locationFilter))
        return false;
    const QString q = m_search.trimmed();
    for (const QString &word : q.split(' ', Qt::SkipEmptyParts)) {
        if (word.startsWith('#')) {
            if (!n.tags.contains(word.mid(1), Qt::CaseInsensitive))
                return false;
        } else if (!n.title.contains(word, Qt::CaseInsensitive)
                   && !n.body.contains(word, Qt::CaseInsensitive)
                   && !n.tags.join(' ').contains(word, Qt::CaseInsensitive)) {
            return false;
        }
    }
    return true;
}

void NotesModel::refresh()
{
    QVector<int> next;
    for (int i = 0; i < m_all.size(); ++i)
        if (matches(m_all[i]))
            next.append(i);
    std::stable_sort(next.begin(), next.end(), [this](int a, int b) {
        const Note &x = m_all[a], &y = m_all[b];
        if (x.pinned != y.pinned) return x.pinned;
        return x.updated > y.updated;
    });
    QStringList nextIds;
    for (int i : next) nextIds << m_all[i].id;

    if (nextIds == m_visibleIds) {
        m_visible = next;
        if (!m_visible.isEmpty())
            emit dataChanged(index(0), index(m_visible.size() - 1));
    } else {
        // Same notes, new order with exactly one moved: animate a move.
        int from = -1, to = -1;
        if (nextIds.size() == m_visibleIds.size()
            && QSet<QString>(nextIds.begin(), nextIds.end()) == QSet<QString>(m_visibleIds.begin(), m_visibleIds.end())) {
            for (int i = 0; i < m_visibleIds.size(); ++i) {
                QStringList trial = m_visibleIds;
                const QString item = trial.takeAt(i);
                const int dest = nextIds.indexOf(item);
                trial.insert(dest, item);
                if (trial == nextIds) { from = i; to = dest; break; }
            }
        }
        if (from >= 0 && from != to && beginMoveRows({}, from, from, {}, to > from ? to + 1 : to)) {
            m_visible = next;
            m_visibleIds = nextIds;
            endMoveRows();
            emit dataChanged(index(0), index(m_visible.size() - 1));
        } else {
            beginResetModel();
            m_visible = next;
            m_visibleIds = nextIds;
            endResetModel();
        }
    }
    ++m_revision;
    emit countsChanged();
}

void NotesModel::refreshSystems()
{
    QStringList s = kDefaultSystems;
    for (const Note &n : std::as_const(m_all))
        if (!s.contains(n.system))
            s.insert(s.size() - 1, n.system); // keep "General" last
    if (s != m_systems) {
        m_systems = s;
        emit systemsChanged();
    }
}

int NotesModel::find(const QString &id) const
{
    for (int i = 0; i < m_all.size(); ++i)
        if (m_all[i].id == id)
            return i;
    return -1;
}

// ---- notes ---------------------------------------------------------------

QString NotesModel::slug(const QString &s)
{
    QString out = s.trimmed().toLower();
    static const QRegularExpression bad(QStringLiteral("[^a-z0-9]+"));
    out.replace(bad, QStringLiteral("-"));
    while (out.startsWith('-')) out.remove(0, 1);
    while (out.endsWith('-')) out.chop(1);
    return out.left(60);
}

QString NotesModel::uniquePath(const QString &dirRel, const QString &stem, const QString &ext) const
{
    const QString base = dirRel.isEmpty() ? stem : dirRel + "/" + stem;
    QString rel = base + ext;
    for (int i = 2; QFileInfo::exists(m_root + "/" + rel); ++i)
        rel = base + "-" + QString::number(i) + ext;
    return rel;
}

QString NotesModel::create(const QString &location, const QString &title)
{
    const QString t = title.trimmed().isEmpty() ? tr("Untitled note") : title.trimmed();
    QString stem = slug(t);
    if (stem.isEmpty()) stem = QStringLiteral("note");
    QDir().mkpath(m_root + "/" + location);
    const QString rel = uniquePath(location, stem, ".md");
    QSaveFile f(m_root + "/" + rel);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Text))
        return {};
    f.write(("# " + t + "\n\n").toUtf8());
    if (!f.commit())
        return {};
    scan();
    return rel;
}

QVariantMap NotesModel::get(const QString &id) const
{
    const int i = find(id);
    if (i < 0)
        return {};
    const Note &n = m_all[i];
    return {
        {"noteId", n.id}, {"title", n.title}, {"system", n.system}, {"tags", n.tags},
        {"pinned", n.pinned}, {"created", n.created}, {"updated", n.updated}, {"body", withoutTitle(n)},
        {"location", n.location}, {"path", absPath(n.id)},
    };
}

void NotesModel::setPinned(const QString &id, bool pinned)
{
    QFile f(absPath(id));
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return;
    QString text = QString::fromUtf8(f.readAll());
    f.close();
    const QString line = QStringLiteral("pinned: %1").arg(pinned ? "true" : "false");
    static const QRegularExpression existing(QStringLiteral("^pinned:.*$"), QRegularExpression::MultilineOption);
    if (text.startsWith("---\n")) {
        const int end = text.indexOf("\n---", 3);
        const int at = text.indexOf(existing);
        if (at >= 0 && at < end)
            text.replace(at, text.indexOf('\n', at) - at, line);
        else
            text.insert(4, line + "\n");
    } else {
        text.prepend("---\n" + line + "\n---\n");
    }
    QSaveFile out(f.fileName());
    if (out.open(QIODevice::WriteOnly | QIODevice::Text)) {
        out.write(text.toUtf8());
        out.commit();
    }
    scan();
}

void NotesModel::remove(const QString &id)
{
    if (find(id) < 0)
        return;
    QDir().mkpath(m_root + "/.trash");
    const QString dest = m_root + "/.trash/" + QString(id).replace('/', "__");
    QFile::remove(dest);
    QFile::rename(absPath(id), dest);
    scan();
}

int NotesModel::countFor(const QString &system) const
{
    if (system.isEmpty())
        return m_all.size();
    return int(std::count_if(m_all.begin(), m_all.end(), [&](const Note &n) { return n.system == system; }));
}

int NotesModel::countForLocation(const QString &location) const
{
    return int(std::count_if(m_all.begin(), m_all.end(), [&](const Note &n) { return inLocation(n, location); }));
}

int NotesModel::indexOf(const QString &id) const
{
    return int(m_visibleIds.indexOf(id));
}

QString NotesModel::idAt(int row) const
{
    return row >= 0 && row < m_visibleIds.size() ? m_visibleIds[row] : QString();
}

// ---- spots ---------------------------------------------------------------

QVariantList NotesModel::spots() const
{
    QVariantList out;
    for (const Spot &sp : m_spots)
        out.append(QVariantMap{{"spotId", sp.id}, {"name", sp.name}, {"view", sp.view}, {"zone", sp.zone},
                               {"x", sp.x}, {"y", sp.y}, {"placed", sp.placed}});
    return out;
}

static void writePlace(const QString &dir, double x, double y)
{
    QSaveFile f(dir + "/.place.json");
    if (f.open(QIODevice::WriteOnly)) {
        f.write(QJsonDocument(QJsonObject{{"x", x}, {"y", y}}).toJson(QJsonDocument::Compact) + "\n");
        f.commit();
    }
}

QString NotesModel::addSpot(const QVariantMap &fields)
{
    const QString zone = fields.value("zone").toString();
    if (zone.count('/') != 1)
        return {};
    QString stem = slug(fields.value("name").toString());
    if (stem.isEmpty()) stem = QStringLiteral("spot");
    const QString rel = uniquePath(zone, stem, QString());
    QDir().mkpath(m_root + "/" + rel);
    writePlace(m_root + "/" + rel, fields.value("x").toDouble(), fields.value("y").toDouble());
    scan();
    return rel;
}

void NotesModel::placeSpot(const QString &id, double x, double y)
{
    if (!isFolder(id))
        return;
    writePlace(m_root + "/" + id, x, y);
    scan();
}

QString NotesModel::renameSpot(const QString &id, const QString &name)
{
    const QString stem = slug(name);
    if (stem.isEmpty() || !isFolder(id))
        return id;
    const QString parent = id.section('/', 0, -2);
    if (stem == id.section('/', -1))
        return id;
    const QString rel = uniquePath(parent, stem, QString());
    if (!QDir(m_root).rename(id, rel))
        return id;
    if (m_locationFilter == id || m_locationFilter.startsWith(id + "/")) {
        m_locationFilter = rel + m_locationFilter.mid(id.size());
        emit filterChanged();
    }
    scan();
    return rel;
}

void NotesModel::removeSpot(const QString &id)
{
    if (!isFolder(id) || id.count('/') < 2)
        return;
    const QString parent = id.section('/', 0, -2);
    QDir dir(m_root + "/" + id);
    for (const QFileInfo &fi : dir.entryInfoList(QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot | QDir::Hidden)) {
        if (fi.fileName() == ".place.json") {
            QFile::remove(fi.absoluteFilePath());
            continue;
        }
        const QString target = m_root + "/" + uniquePath(parent, fi.completeBaseName(), fi.isDir() ? QString() : "." + fi.suffix());
        QFile::rename(fi.absoluteFilePath(), target);
    }
    QDir(m_root).rmdir(id);
    if (m_locationFilter == id || m_locationFilter.startsWith(id + "/")) {
        m_locationFilter = parent;
        emit filterChanged();
    }
    scan();
}

// ---- paths ---------------------------------------------------------------

QString NotesModel::absPath(const QString &rel) const
{
    return rel.isEmpty() ? m_root : m_root + "/" + rel;
}

QString NotesModel::relPath(const QString &abs) const
{
    const QString p = QDir::cleanPath(abs);
    if (p == m_root)
        return QStringLiteral(".");
    if (!p.startsWith(m_root + "/"))
        return {};
    return p.mid(m_root.size() + 1);
}

bool NotesModel::isFolder(const QString &rel) const
{
    return QFileInfo(absPath(rel)).isDir();
}
