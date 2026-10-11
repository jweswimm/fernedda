#include "Store.h"

#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSaveFile>
#include <QStandardPaths>

Store::Store()
    : m_dir(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/fernedda")
{
    QDir().mkpath(m_dir + "/images");
    QFile f(m_dir + "/maps.json");
    if (f.open(QIODevice::ReadOnly))
        m_maps = QJsonDocument::fromJson(f.readAll()).object();
}

FolderMap Store::get(const QString &folder) const
{
    FolderMap m;
    const QJsonObject o = m_maps.value(folder).toObject();
    m.image = o.value("image").toString();
    for (const QJsonValue &v : o.value("hotspots").toArray()) {
        const QJsonObject h = v.toObject();
        m.hotspots.push_back({QRectF(h["x"].toDouble(), h["y"].toDouble(), h["w"].toDouble(), h["h"].toDouble()),
                              h["target"].toString()});
    }
    return m;
}

void Store::setHotspots(const QString &folder, const QVector<Hotspot> &hotspots)
{
    QJsonArray arr;
    for (const Hotspot &h : hotspots)
        arr.append(QJsonObject{{"x", h.rect.x()}, {"y", h.rect.y()}, {"w", h.rect.width()},
                               {"h", h.rect.height()}, {"target", h.target}});
    QJsonObject o = m_maps.value(folder).toObject();
    o["hotspots"] = arr;
    m_maps[folder] = o;
    save();
}

bool Store::setImage(const QString &folder, const QString &sourceFile)
{
    QFile src(sourceFile);
    if (!src.open(QIODevice::ReadOnly))
        return false;
    const QByteArray data = src.readAll();
    // Content-addressed, so the same picture is only stored once.
    const QString hash = QCryptographicHash::hash(data, QCryptographicHash::Sha256).toHex().left(32);
    QString ext = QFileInfo(sourceFile).suffix().toLower();
    if (ext.isEmpty())
        ext = "img";
    const QString name = hash + "." + ext;
    QFile dst(imagePath(name));
    if (!dst.exists() && (!dst.open(QIODevice::WriteOnly) || dst.write(data) != data.size()))
        return false;

    QJsonObject o = m_maps.value(folder).toObject();
    o["image"] = name;
    m_maps[folder] = o;
    save();
    return true;
}

QString Store::imagePath(const QString &name) const
{
    return m_dir + "/images/" + name;
}

void Store::save() const
{
    QSaveFile f(m_dir + "/maps.json");
    if (f.open(QIODevice::WriteOnly)) {
        f.write(QJsonDocument(m_maps).toJson());
        f.commit();
    }
}
