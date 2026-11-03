#pragma once

#include <QAbstractListModel>
#include <QDateTime>
#include <QFileSystemWatcher>
#include <QStringList>
#include <QTimer>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class QQmlEngine;
class QJSEngine;

// Boat notes as a plain folder tree, edited in Neovim:
//
//   boat/<view>/<zone>/note.md            e.g. boat/below/engine/oil-change.md
//   boat/<view>/<zone>/<spot>/note.md     a spot is just a sub-folder;
//   boat/<view>/<zone>/<spot>/.place.json where its pin sits on the drawing
//
// The tree is watched, so files and folders made in oil (or anywhere) show
// up live. Front-matter is optional (title, system, tags, pinned); a note
// without it takes its title from the first heading or the file name and
// its system from the zone it lives in.
//
// Exposed to QML as the `Notes` singleton; it is itself the (filtered,
// sorted) list model: pinned first, then most recently updated.
class NotesModel : public QAbstractListModel {
    Q_OBJECT
    QML_NAMED_ELEMENT(Notes)
    QML_SINGLETON
    Q_PROPERTY(QString systemFilter READ systemFilter WRITE setSystemFilter NOTIFY filterChanged)
    Q_PROPERTY(QString search READ search WRITE setSearch NOTIFY filterChanged)
    // A folder relative to the root ("below/engine"); matches everything under it.
    Q_PROPERTY(QString locationFilter READ locationFilter WRITE setLocationFilter NOTIFY filterChanged)
    // Spot folders: [{ spotId, name, view, zone, x, y, placed }], x/y in metres.
    Q_PROPERTY(QVariantList spots READ spots NOTIFY spotsChanged)
    Q_PROPERTY(QStringList systems READ systems NOTIFY systemsChanged)
    Q_PROPERTY(int total READ total NOTIFY countsChanged)
    Q_PROPERTY(int count READ count NOTIFY countsChanged)
    // Bumps on every change, so bindings that call countFor*() refresh.
    Q_PROPERTY(int revision READ revision NOTIFY countsChanged)
    Q_PROPERTY(QString root READ root CONSTANT)

public:
    enum Role {
        IdRole = Qt::UserRole + 1,
        TitleRole,
        SystemRole,
        TagsRole,
        PinnedRole,
        CreatedRole,
        UpdatedRole,
        PreviewRole,
        BodyRole,
        LocationRole,
        PathRole,
    };

    static NotesModel *create(QQmlEngine *, QJSEngine *);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString systemFilter() const { return m_systemFilter; }
    void setSystemFilter(const QString &s);
    QString search() const { return m_search; }
    void setSearch(const QString &s);
    QString locationFilter() const { return m_locationFilter; }
    void setLocationFilter(const QString &s);
    QVariantList spots() const;
    QStringList systems() const { return m_systems; }
    int total() const { return m_all.size(); }
    int count() const { return m_visible.size(); }
    int revision() const { return m_revision; }
    QString root() const { return m_root; }

    // Called once from QML with the boat drawing's zones:
    // { "below/engine": "Engine", ... } — makes the folders, sets default systems.
    Q_INVOKABLE void setZones(const QVariantMap &zoneSystems);

    // New note "<location>/<slug of title>.md"; returns its id (relative path).
    Q_INVOKABLE QString create(const QString &location, const QString &title);
    Q_INVOKABLE QVariantMap get(const QString &id) const;
    Q_INVOKABLE void setPinned(const QString &id, bool pinned);
    Q_INVOKABLE void remove(const QString &id);   // moves to boat/.trash/
    Q_INVOKABLE int countFor(const QString &system) const;
    Q_INVOKABLE int countForLocation(const QString &location) const;
    Q_INVOKABLE int indexOf(const QString &id) const;
    Q_INVOKABLE QString idAt(int row) const;

    // Spots. addSpot takes { name, zone, x, y } and returns the new folder id.
    Q_INVOKABLE QString addSpot(const QVariantMap &fields);
    Q_INVOKABLE void placeSpot(const QString &id, double x, double y);
    Q_INVOKABLE QString renameSpot(const QString &id, const QString &name);
    // Its notes and sub-folders move up to the zone.
    Q_INVOKABLE void removeSpot(const QString &id);

    // Paths: relative ids ↔ absolute paths ("" when outside the boat folder).
    Q_INVOKABLE QString absPath(const QString &rel) const;
    Q_INVOKABLE QString relPath(const QString &abs) const;
    Q_INVOKABLE bool isFolder(const QString &rel) const;

signals:
    void filterChanged();
    void systemsChanged();
    void countsChanged();
    void spotsChanged();

private:
    struct Note {
        QString id, title, system, body, location;
        QStringList tags;
        bool pinned = false;
        QDateTime created, updated;
    };
    struct Spot {
        QString id, name, view, zone;
        double x = 0, y = 0;
        bool placed = false;
    };

    explicit NotesModel(QObject *parent = nullptr);
    void scan();
    void scanDir(const QString &rel, int depth, QStringList &dirs, QStringList &files);
    bool readNote(const QString &rel, Note &n) const;
    bool inLocation(const Note &n, const QString &loc) const;
    bool matches(const Note &n) const;
    void refresh();
    void refreshSystems();
    int find(const QString &id) const;
    QString uniquePath(const QString &dirRel, const QString &stem, const QString &ext) const;
    static QString slug(const QString &s);
    static QString withoutTitle(const Note &n);

    QString m_root;
    QVector<Note> m_all;
    QVector<int> m_visible;     // indexes into m_all
    QStringList m_visibleIds;
    QVector<Spot> m_spots;
    QVariantMap m_zoneSystems;
    QString m_systemFilter, m_search, m_locationFilter;
    QStringList m_systems;
    int m_revision = 0;
    QFileSystemWatcher m_watcher;
    QTimer m_rescan;
};
