#pragma once

#include <QDateTime>
#include <QString>
#include <QVector>

// Recently opened projects, newest first, kept in ~/.config/fernedda/recent.json.
namespace Recents {

struct Entry {
    QString file;
    QString name;
    QString root;
    QDateTime opened;
};

QVector<Entry> load();
void touch(const QString &file, const QString &name, const QString &root);
void remove(const QString &file);

}
