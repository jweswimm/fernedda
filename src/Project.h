#pragma once

#include <QJsonObject>
#include <QRectF>
#include <QString>
#include <QVector>

#include <memory>

struct Hotspot {
    QRectF rect;     // fractions of the image size, 0..1
    QString target;  // entry name inside the folder, or ".." for the parent
};

struct FolderMap {
    QString image;   // file name inside the project's images folder, empty if none
    QVector<Hotspot> hotspots;
};

// A .fernedda project file: a name, a root folder, and a picture + regions per folder.
// Folders are stored relative to the root; pictures live in "<file>-images/" next to it.
class Project {
public:
    static std::unique_ptr<Project> open(const QString &file, QString *error);
    static std::unique_ptr<Project> create(const QString &file, const QString &name, const QString &root,
                                           QString *error);

    QString file() const { return m_file; }
    QString name() const { return m_name; }
    QString root() const { return m_root; }
    bool rootExists() const;
    bool setRoot(const QString &root, QString *error);

    // Folders are absolute paths inside root().
    bool contains(const QString &folder) const;
    FolderMap get(const QString &folder) const;
    void setHotspots(const QString &folder, const QVector<Hotspot> &hotspots);
    // Copies the image into the project; returns false if that fails.
    bool setImage(const QString &folder, const QString &sourceFile);

    QString imagePath(const QString &name) const;

private:
    Project() = default;
    QString key(const QString &folder) const;
    QString imageDir() const { return m_file + "-images"; }
    bool save(QString *error = nullptr) const;

    QString m_file, m_name, m_root;
    QJsonObject m_maps;
};
