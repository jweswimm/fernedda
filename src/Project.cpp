#include "Project.h"

#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSaveFile>

namespace {
constexpr int kFormatVersion = 1;
}

std::unique_ptr<Project> Project::open(const QString &file, QString *error)
{
    QFile f(file);
    if (!f.open(QIODevice::ReadOnly)) {
        *error = "Couldn't open " + file + ":\n" + f.errorString();
        return nullptr;
    }
    QJsonParseError parseError;
    const QJsonObject o = QJsonDocument::fromJson(f.readAll(), &parseError).object();
    if (parseError.error != QJsonParseError::NoError || !o.contains("fernedda")) {
        *error = file + " isn't a fernedda project.";
        return nullptr;
    }
    std::unique_ptr<Project> p(new Project);
    p->m_file = QFileInfo(file).absoluteFilePath();
    p->m_name = o["name"].toString(QFileInfo(file).completeBaseName());
    p->m_root = o["root"].toString();
    p->m_maps = o["maps"].toObject();
    return p;
}

std::unique_ptr<Project> Project::create(const QString &file, const QString &name, const QString &root,
                                         QString *error)
{
    std::unique_ptr<Project> p(new Project);
    p->m_file = QFileInfo(file).absoluteFilePath();
    p->m_name = name;
    p->m_root = QFileInfo(root).canonicalFilePath();
    if (p->m_root.isEmpty()) {
        *error = "Folder not found: " + root;
        return nullptr;
    }
    if (!p->save(error))
        return nullptr;
    return p;
}

bool Project::rootExists() const
{
    return QFileInfo(m_root).isDir();
}

bool Project::setRoot(const QString &root, QString *error)
{
    m_root = QFileInfo(root).canonicalFilePath();
    return save(error);
}

bool Project::contains(const QString &folder) const
{
    return folder == m_root || folder.startsWith(m_root.endsWith('/') ? m_root : m_root + '/');
}

QString Project::key(const QString &folder) const
{
    const QString rel = QDir(m_root).relativeFilePath(folder);
    return rel.isEmpty() ? QStringLiteral(".") : rel;
}

FolderMap Project::get(const QString &folder) const
{
    FolderMap m;
    const QJsonObject o = m_maps.value(key(folder)).toObject();
    m.image = o.value("image").toString();
    for (const QJsonValue &v : o.value("hotspots").toArray()) {
        const QJsonObject h = v.toObject();
        m.hotspots.push_back({QRectF(h["x"].toDouble(), h["y"].toDouble(), h["w"].toDouble(), h["h"].toDouble()),
                              h["target"].toString()});
    }
    return m;
}

void Project::setHotspots(const QString &folder, const QVector<Hotspot> &hotspots)
{
    QJsonArray arr;
    for (const Hotspot &h : hotspots)
        arr.append(QJsonObject{{"x", h.rect.x()}, {"y", h.rect.y()}, {"w", h.rect.width()},
                               {"h", h.rect.height()}, {"target", h.target}});
    QJsonObject o = m_maps.value(key(folder)).toObject();
    o["hotspots"] = arr;
    m_maps[key(folder)] = o;
    save();
}

bool Project::setImage(const QString &folder, const QString &sourceFile)
{
    QFile src(sourceFile);
    if (!src.open(QIODevice::ReadOnly) || !QDir().mkpath(imageDir()))
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

    QJsonObject o = m_maps.value(key(folder)).toObject();
    o["image"] = name;
    m_maps[key(folder)] = o;
    return save();
}

QString Project::imagePath(const QString &name) const
{
    return imageDir() + "/" + name;
}

bool Project::save(QString *error) const
{
    QSaveFile f(m_file);
    const QJsonObject o{{"fernedda", kFormatVersion}, {"name", m_name}, {"root", m_root}, {"maps", m_maps}};
    if (f.open(QIODevice::WriteOnly) && f.write(QJsonDocument(o).toJson()) >= 0 && f.commit())
        return true;
    if (error)
        *error = "Couldn't save " + m_file + ":\n" + f.errorString();
    return false;
}
