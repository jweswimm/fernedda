#pragma once

#include <QString>

namespace Opener {

// Opens a file: text/code in a terminal editor (nvim by default), everything else
// in the system default app. Returns a short name of what it was opened with, or
// an empty string on failure.
QString open(const QString &path);

bool isText(const QString &path);

}
