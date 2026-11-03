#include "NotesModel.h"

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJSEngine>
#include <QQmlEngine>
#include <QRandomGenerator>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <QStandardPaths>
#include <algorithm>

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
} // namespace

NotesModel *NotesModel::create(QQmlEngine *, QJSEngine *)
{
    static NotesModel *s = new NotesModel;
    QJSEngine::setObjectOwnership(s, QJSEngine::CppOwnership);
    return s;
}

NotesModel::NotesModel(QObject *parent) : QAbstractListModel(parent)
{
    m_dir = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/fernedda/notes";
    QDir().mkpath(m_dir);
    load();
    loadSpots();
    if (m_all.isEmpty())
        seed();
    refreshSystems();
    refresh();
}

// ---- file format ---------------------------------------------------------
//
// ---
// title: Oil change
// system: Engine
// location: engine            (optional: boat zone or spot id)
// tags: maintenance, oil
// pinned: false
// created: 2026-11-02T10:00:00Z
// updated: 2026-11-02T10:05:00Z
// ---
// Markdown body…

bool NotesModel::parse(const QString &text, Note &n)
{
    QString body = text;
    if (text.startsWith("---\n") || text.startsWith("---\r\n")) {
        const int start = text.indexOf('\n') + 1;
        const int end = text.indexOf(QRegularExpression("^---\\s*$", QRegularExpression::MultilineOption), start);
        if (end < 0)
            return false;
        const QStringList lines = text.mid(start, end - start).split('\n');
        for (const QString &line : lines) {
            const int colon = line.indexOf(':');
            if (colon < 0) continue;
            const QString key = line.left(colon).trimmed();
            const QString val = line.mid(colon + 1).trimmed();
            if (key == "title") n.title = val;
            else if (key == "system") n.system = val;
            else if (key == "location") n.location = val;
            else if (key == "pinned") n.pinned = (val == "true");
            else if (key == "created") n.created = QDateTime::fromString(val, Qt::ISODate);
            else if (key == "updated") n.updated = QDateTime::fromString(val, Qt::ISODate);
            else if (key == "tags") {
                for (const QString &t : val.split(',', Qt::SkipEmptyParts))
                    if (!t.trimmed().isEmpty()) n.tags << t.trimmed();
            }
        }
        const int bodyStart = text.indexOf('\n', end);
        body = bodyStart < 0 ? QString() : text.mid(bodyStart + 1);
    }
    n.body = body;
    return true;
}

bool NotesModel::write(const Note &n) const
{
    QSaveFile f(m_dir + "/" + n.id + ".md");
    if (!f.open(QIODevice::WriteOnly | QIODevice::Text))
        return false;
    auto oneLine = [](QString s) { return s.replace('\n', ' ').trimmed(); };
    QString out;
    out += "---\n";
    out += "title: " + oneLine(n.title) + "\n";
    out += "system: " + oneLine(n.system) + "\n";
    if (!n.location.isEmpty())
        out += "location: " + oneLine(n.location) + "\n";
    out += "tags: " + oneLine(n.tags.join(", ")) + "\n";
    out += QStringLiteral("pinned: %1\n").arg(n.pinned ? "true" : "false");
    out += "created: " + n.created.toUTC().toString(Qt::ISODate) + "\n";
    out += "updated: " + n.updated.toUTC().toString(Qt::ISODate) + "\n";
    out += "---\n";
    out += n.body;
    f.write(out.toUtf8());
    return f.commit();
}

void NotesModel::load()
{
    const QDir dir(m_dir);
    for (const QFileInfo &fi : dir.entryInfoList({"*.md"}, QDir::Files)) {
        QFile f(fi.absoluteFilePath());
        if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
            continue;
        Note n;
        n.id = fi.completeBaseName();
        if (!parse(QString::fromUtf8(f.readAll()), n))
            continue;
        if (!n.created.isValid()) n.created = fi.birthTime().isValid() ? fi.birthTime() : fi.lastModified();
        if (!n.updated.isValid()) n.updated = fi.lastModified();
        if (n.title.isEmpty()) n.title = n.id;
        if (n.system.isEmpty()) n.system = "General";
        m_all.append(n);
    }
}

void NotesModel::seed()
{
    const QDateTime now = QDateTime::currentDateTimeUtc();
    auto add = [&](const QString &title, const QString &system, const QString &location,
                   const QStringList &tags, bool pinned, int daysAgo, const QString &body) {
        Note n;
        n.id = QStringLiteral("seed-%1").arg(m_all.size() + 1);
        n.title = title;
        n.system = system;
        n.location = location;
        n.tags = tags;
        n.pinned = pinned;
        n.created = n.updated = now.addDays(-daysAgo);
        n.body = body;
        write(n);
        m_all.append(n);
    };

    add("Welcome aboard", "General", {}, {"howto"}, true, 0,
        "Notes are plain **Markdown** files, one per note, kept in\n"
        "`~/.local/share/fernedda/notes/`. Edit them here or in any text editor.\n\n"
        "## Tips\n\n"
        "- File each note under a **system** (Engine, Rigging…) and add tags\n"
        "- Or switch to **Boat** and tap a part of the boat to file notes there; double-tap to drop a named spot\n"
        "- **Pin** the ones you need often; they stay at the top\n"
        "- *Insert readings* stamps the current engine hours, battery and position into the note — handy for maintenance logs\n"
        "- Use checklists:\n\n"
        "- [x] Install fernedda\n"
        "- [ ] Hook up a Signal K server\n");
    add("Oil & filter change", "Engine", "engine", {"maintenance", "oil"}, false, 12,
        "Changed oil and filter.\n\n"
        "| Item | Detail |\n|---|---|\n"
        "| Oil | 15W-40, 3.8 L |\n| Filter | (part number here) |\n| Engine hours | 1,838 |\n\n"
        "Next change due around **1,938 h**.\n");
    add("Rig check before season", "Rigging", "mast", {"inspection", "checklist"}, false, 30,
        "- [ ] Inspect swage fittings for cracks\n"
        "- [ ] Cotter pins taped at turnbuckles\n"
        "- [ ] Halyards — chafe at sheaves\n"
        "- [ ] Spreader boots\n"
        "- [ ] Furler drum & swivel lubrication\n");
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
    case PreviewRole: return stripMarkdown(n.body);
    case BodyRole: return n.body;
    case LocationRole: return n.location;
    }
    return {};
}

QHash<int, QByteArray> NotesModel::roleNames() const
{
    return {
        {IdRole, "noteId"}, {TitleRole, "title"}, {SystemRole, "system"},
        {TagsRole, "tags"}, {PinnedRole, "pinned"}, {CreatedRole, "created"},
        {UpdatedRole, "updated"}, {PreviewRole, "preview"}, {BodyRole, "body"},
        {LocationRole, "location"},
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
    if (n.location == loc)
        return true;
    if (n.location.isEmpty())
        return false;
    for (const Spot &sp : m_spots)
        if (sp.id == n.location)
            return sp.zone == loc;
    return false;
}

bool NotesModel::matches(const Note &n) const
{
    if (!m_systemFilter.isEmpty() && n.system != m_systemFilter)
        return false;
    if (!m_locationFilter.isEmpty() && !inLocation(n, m_locationFilter))
        return false;
    const QString q = m_search.trimmed();
    if (q.isEmpty())
        return true;
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

    if (next == m_visible) {
        if (!m_visible.isEmpty())
            emit dataChanged(index(0), index(m_visible.size() - 1));
    } else if (next.size() == m_visible.size()
               && QSet<int>(next.begin(), next.end()) == QSet<int>(m_visible.begin(), m_visible.end())) {
        // Same notes, new order: if exactly one note moved, animate a move.
        int from = -1, to = -1;
        for (int i = 0; i < m_visible.size(); ++i) {
            QVector<int> trial = m_visible;
            const int item = trial.takeAt(i);
            const int dest = next.indexOf(item);
            trial.insert(dest, item);
            if (trial == next) { from = i; to = dest; break; }
        }
        if (from >= 0 && beginMoveRows({}, from, from, {}, to > from ? to + 1 : to)) {
            m_visible = next;
            endMoveRows();
            emit dataChanged(index(0), index(m_visible.size() - 1));
        } else {
            beginResetModel();
            m_visible = next;
            endResetModel();
        }
    } else {
        beginResetModel();
        m_visible = next;
        endResetModel();
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

QString NotesModel::create(const QString &system, const QString &location)
{
    Note n;
    n.created = n.updated = QDateTime::currentDateTimeUtc();
    n.id = n.created.toString("yyyyMMdd-HHmmss") + "-"
         + QString::number(QRandomGenerator::global()->bounded(0x10000), 16).rightJustified(4, '0');
    n.title = tr("Untitled note");
    n.system = system.isEmpty() ? QStringLiteral("General") : system;
    n.location = location;
    write(n);
    m_all.append(n);
    refreshSystems();
    refresh();
    return n.id;
}

QVariantMap NotesModel::get(const QString &id) const
{
    const int i = find(id);
    if (i < 0)
        return {};
    const Note &n = m_all[i];
    return {
        {"noteId", n.id}, {"title", n.title}, {"system", n.system}, {"tags", n.tags},
        {"pinned", n.pinned}, {"created", n.created}, {"updated", n.updated}, {"body", n.body},
        {"location", n.location},
    };
}

void NotesModel::save(const QString &id, const QVariantMap &fields)
{
    const int i = find(id);
    if (i < 0)
        return;
    Note &n = m_all[i];
    const Note before = n;
    if (fields.contains("title")) n.title = fields.value("title").toString();
    if (fields.contains("body")) n.body = fields.value("body").toString();
    if (fields.contains("system")) n.system = fields.value("system").toString();
    if (fields.contains("location")) n.location = fields.value("location").toString();
    if (fields.contains("pinned")) n.pinned = fields.value("pinned").toBool();
    if (fields.contains("tags")) {
        const QVariant t = fields.value("tags");
        QStringList tags;
        const QStringList raw = t.metaType().id() == QMetaType::QString ? t.toString().split(',')
                                                                         : t.toStringList();
        for (const QString &tag : raw) {
            QString s = tag.trimmed();
            if (s.startsWith('#')) s.remove(0, 1);
            if (!s.isEmpty() && !tags.contains(s, Qt::CaseInsensitive)) tags << s;
        }
        n.tags = tags;
    }
    const bool edited = n.title != before.title || n.body != before.body || n.system != before.system
                     || n.tags != before.tags || n.location != before.location;
    if (!edited && n.pinned == before.pinned)
        return;
    // Pinning alone shouldn't bump a note to "just edited".
    if (edited)
        n.updated = QDateTime::currentDateTimeUtc();
    write(n);
    refreshSystems();
    refresh();
}

void NotesModel::remove(const QString &id)
{
    const int i = find(id);
    if (i < 0)
        return;
    // Move to a trash folder rather than deleting outright.
    QDir().mkpath(m_dir + "/.trash");
    QFile::remove(m_dir + "/.trash/" + id + ".md");
    QFile::rename(m_dir + "/" + id + ".md", m_dir + "/.trash/" + id + ".md");
    beginResetModel();
    m_all.removeAt(i);
    m_visible.clear();
    endResetModel();
    refreshSystems();
    refresh();
}

int NotesModel::countFor(const QString &system) const
{
    if (system.isEmpty())
        return m_all.size();
    return int(std::count_if(m_all.begin(), m_all.end(), [&](const Note &n) { return n.system == system; }));
}

int NotesModel::indexOf(const QString &id) const
{
    for (int r = 0; r < m_visible.size(); ++r)
        if (m_all[m_visible[r]].id == id)
            return r;
    return -1;
}

QStringList NotesModel::allTags() const
{
    QStringList out;
    for (const Note &n : m_all)
        for (const QString &t : n.tags)
            if (!out.contains(t, Qt::CaseInsensitive)) out << t;
    out.sort(Qt::CaseInsensitive);
    return out;
}

int NotesModel::countForLocation(const QString &location) const
{
    if (location.isEmpty())
        return m_all.size();
    return int(std::count_if(m_all.begin(), m_all.end(), [&](const Note &n) { return inLocation(n, location); }));
}

// ---- spots ---------------------------------------------------------------
//
// Kept in spots.json next to the notes:
// [{ "id": "spot-…", "name": "Raw water strainer", "view": "below", "x": 4.1, "y": 0.2, "zone": "engine" }]

void NotesModel::loadSpots()
{
    QFile f(m_dir + "/spots.json");
    if (!f.open(QIODevice::ReadOnly))
        return;
    const QJsonArray arr = QJsonDocument::fromJson(f.readAll()).array();
    for (const QJsonValue &v : arr) {
        const QJsonObject o = v.toObject();
        Spot sp;
        sp.id = o.value("id").toString();
        sp.name = o.value("name").toString();
        sp.view = o.value("view").toString();
        sp.zone = o.value("zone").toString();
        sp.x = o.value("x").toDouble();
        sp.y = o.value("y").toDouble();
        if (!sp.id.isEmpty())
            m_spots.append(sp);
    }
}

void NotesModel::saveSpots() const
{
    QJsonArray arr;
    for (const Spot &sp : m_spots)
        arr.append(QJsonObject{{"id", sp.id}, {"name", sp.name}, {"view", sp.view},
                               {"x", sp.x}, {"y", sp.y}, {"zone", sp.zone}});
    QSaveFile f(m_dir + "/spots.json");
    if (f.open(QIODevice::WriteOnly)) {
        f.write(QJsonDocument(arr).toJson());
        f.commit();
    }
}

QVariantList NotesModel::spots() const
{
    QVariantList out;
    for (const Spot &sp : m_spots)
        out.append(QVariantMap{{"spotId", sp.id}, {"name", sp.name}, {"view", sp.view},
                               {"x", sp.x}, {"y", sp.y}, {"zone", sp.zone}});
    return out;
}

QString NotesModel::addSpot(const QVariantMap &fields)
{
    Spot sp;
    sp.id = "spot-" + QDateTime::currentDateTimeUtc().toString("yyyyMMddHHmmss")
          + QString::number(QRandomGenerator::global()->bounded(0x10000), 16).rightJustified(4, '0');
    sp.name = fields.value("name").toString().trimmed();
    if (sp.name.isEmpty()) sp.name = tr("Spot");
    sp.view = fields.value("view").toString();
    sp.zone = fields.value("zone").toString();
    sp.x = fields.value("x").toDouble();
    sp.y = fields.value("y").toDouble();
    m_spots.append(sp);
    saveSpots();
    emit spotsChanged();
    return sp.id;
}

void NotesModel::updateSpot(const QString &id, const QVariantMap &fields)
{
    for (Spot &sp : m_spots) {
        if (sp.id != id) continue;
        if (fields.contains("name") && !fields.value("name").toString().trimmed().isEmpty())
            sp.name = fields.value("name").toString().trimmed();
        if (fields.contains("x")) sp.x = fields.value("x").toDouble();
        if (fields.contains("y")) sp.y = fields.value("y").toDouble();
        const bool zoneMoved = fields.contains("zone") && fields.value("zone").toString() != sp.zone;
        if (fields.contains("zone")) sp.zone = fields.value("zone").toString();
        saveSpots();
        emit spotsChanged();
        if (zoneMoved) refresh(); // zone filters and counts include spot notes
        return;
    }
}

void NotesModel::removeSpot(const QString &id)
{
    const auto it = std::find_if(m_spots.begin(), m_spots.end(), [&](const Spot &s) { return s.id == id; });
    if (it == m_spots.end())
        return;
    const QString zone = it->zone;
    m_spots.erase(it);
    for (Note &n : m_all) {
        if (n.location == id) {
            n.location = zone;
            write(n);
        }
    }
    saveSpots();
    if (m_locationFilter == id) {
        m_locationFilter = zone;
        emit filterChanged();
    }
    emit spotsChanged();
    refresh();
}
