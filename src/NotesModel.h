#pragma once

#include <QAbstractListModel>
#include <QDateTime>
#include <QStringList>
#include <QtQml/qqmlregistration.h>

class QQmlEngine;
class QJSEngine;

// Boat notes, one Markdown file per note with a small front-matter header,
// stored in ~/.local/share/fernedda/notes/. Plain files on purpose: they can
// be synced, grepped, or edited by hand.
//
// Exposed to QML as the `Notes` singleton; it is itself the (filtered,
// sorted) list model: pinned first, then most recently updated.
class NotesModel : public QAbstractListModel {
    Q_OBJECT
    QML_NAMED_ELEMENT(Notes)
    QML_SINGLETON
    Q_PROPERTY(QString systemFilter READ systemFilter WRITE setSystemFilter NOTIFY filterChanged)
    Q_PROPERTY(QString search READ search WRITE setSearch NOTIFY filterChanged)
    // Where on the boat: a zone id from the boat drawing, or a spot id.
    // A zone filter also matches notes filed under spots inside that zone.
    Q_PROPERTY(QString locationFilter READ locationFilter WRITE setLocationFilter NOTIFY filterChanged)
    // User-placed spots (named pins on the boat drawing that act as folders):
    // [{ spotId, name, view, x, y, zone }], x/y in metres in that view.
    Q_PROPERTY(QVariantList spots READ spots NOTIFY spotsChanged)
    // Bumps on every change, so bindings that call countFor*() refresh.
    Q_PROPERTY(int revision READ revision NOTIFY countsChanged)
    Q_PROPERTY(QStringList systems READ systems NOTIFY systemsChanged)
    Q_PROPERTY(int total READ total NOTIFY countsChanged)
    Q_PROPERTY(int count READ count NOTIFY countsChanged)
    Q_PROPERTY(QString folder READ folder CONSTANT)

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
    int revision() const { return m_revision; }
    QStringList systems() const { return m_systems; }
    int total() const { return m_all.size(); }
    int count() const { return m_visible.size(); }
    QString folder() const { return m_dir; }

    Q_INVOKABLE QString create(const QString &system = {}, const QString &location = {});
    Q_INVOKABLE QVariantMap get(const QString &id) const;
    // Accepts any of: title, body, system, tags (list or comma string), pinned.
    Q_INVOKABLE void save(const QString &id, const QVariantMap &fields);
    Q_INVOKABLE void remove(const QString &id);
    Q_INVOKABLE int countFor(const QString &system) const;
    Q_INVOKABLE int indexOf(const QString &id) const;
    Q_INVOKABLE QStringList allTags() const;
    Q_INVOKABLE int countForLocation(const QString &location) const;

    // Spots. addSpot takes { name, view, x, y, zone } and returns the new id.
    Q_INVOKABLE QString addSpot(const QVariantMap &fields);
    Q_INVOKABLE void updateSpot(const QString &id, const QVariantMap &fields);
    // Notes filed under the spot move up to its zone.
    Q_INVOKABLE void removeSpot(const QString &id);

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

    explicit NotesModel(QObject *parent = nullptr);
    void load();
    void seed();
    bool write(const Note &n) const;
    static bool parse(const QString &text, Note &n);
    int find(const QString &id) const;
    bool matches(const Note &n) const;
    void refresh();
    void refreshSystems();
    bool inLocation(const Note &n, const QString &loc) const;
    void loadSpots();
    void saveSpots() const;

    struct Spot {
        QString id, name, view, zone;
        double x = 0, y = 0;
    };
    QVector<Spot> m_spots;
    int m_revision = 0;

    QString m_dir;
    QVector<Note> m_all;
    QVector<int> m_visible; // indexes into m_all
    QString m_systemFilter, m_search, m_locationFilter;
    QStringList m_systems;
};
