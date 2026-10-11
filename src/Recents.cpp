#include "Recents.h"

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QStandardPaths>

namespace {

constexpr int kMaxRecents = 15;

QString storePath()
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + "/fernedda";
    QDir().mkpath(dir);
    return dir + "/recent.json";
}

void save(const QVector<Recents::Entry> &entries)
{
    QJsonArray arr;
    for (const Recents::Entry &e : entries)
        arr.append(QJsonObject{{"file", e.file}, {"name", e.name}, {"root", e.root},
                               {"opened", e.opened.toString(Qt::ISODate)}});
    QSaveFile f(storePath());
    if (f.open(QIODevice::WriteOnly)) {
        f.write(QJsonDocument(arr).toJson());
        f.commit();
    }
}

}

QVector<Recents::Entry> Recents::load()
{
    QVector<Entry> out;
    QFile f(storePath());
    if (!f.open(QIODevice::ReadOnly))
        return out;
    for (const QJsonValue &v : QJsonDocument::fromJson(f.readAll()).array()) {
        const QJsonObject o = v.toObject();
        out.push_back({o["file"].toString(), o["name"].toString(), o["root"].toString(),
                       QDateTime::fromString(o["opened"].toString(), Qt::ISODate)});
    }
    return out;
}

void Recents::touch(const QString &file, const QString &name, const QString &root)
{
    QVector<Entry> entries = load();
    entries.removeIf([&](const Entry &e) { return e.file == file; });
    entries.prepend({file, name, root, QDateTime::currentDateTime()});
    if (entries.size() > kMaxRecents)
        entries.resize(kMaxRecents);
    save(entries);
}

void Recents::remove(const QString &file)
{
    QVector<Entry> entries = load();
    entries.removeIf([&](const Entry &e) { return e.file == file; });
    save(entries);
}
