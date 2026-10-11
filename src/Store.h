#pragma once

#include <QJsonObject>
#include <QRectF>
#include <QString>
#include <QVector>

struct Hotspot {
    QRectF rect;     // fractions of the image size, 0..1
    QString target;  // entry name inside the folder, or ".." for the parent
};

struct FolderMap {
    QString image;   // file name inside Store::imageDir(), empty if none
    QVector<Hotspot> hotspots;
};

// Pictures and regions per folder, kept in ~/.local/share/fernedda/maps.json.
class Store {
public:
    Store();

    FolderMap get(const QString &folder) const;
    void setHotspots(const QString &folder, const QVector<Hotspot> &hotspots);
    // Copies the image into the store; returns false if it can't be read.
    bool setImage(const QString &folder, const QString &sourceFile);

    QString imagePath(const QString &name) const;

private:
    void save() const;

    QString m_dir;
    QJsonObject m_maps;
};
