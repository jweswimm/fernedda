#include "Opener.h"

#include <QDesktopServices>
#include <QFile>
#include <QFileInfo>
#include <QMimeDatabase>
#include <QProcess>
#include <QSet>
#include <QStandardPaths>
#include <QStringList>
#include <QUrl>

namespace {

// Extensions that are always text, including ones mime detection gets wrong (.ts -> video/mp2t).
const QSet<QString> kTextExts = {
    "txt", "md", "markdown", "rst", "org", "log", "csv", "tsv",
    "py", "js", "mjs", "cjs", "ts", "tsx", "jsx", "json", "jsonc", "yaml", "yml", "toml", "ini", "cfg", "conf",
    "env", "xml", "html", "htm", "css", "scss", "sass", "less", "vue", "svelte",
    "c", "h", "cpp", "cc", "hpp", "cs", "java", "kt", "kts", "go", "rs", "rb", "php", "pl", "lua", "vim",
    "sh", "bash", "zsh", "fish", "ps1", "bat", "sql", "graphql", "proto", "swift", "dart", "scala", "clj",
    "ex", "exs", "erl", "hs", "ml", "nix", "zig", "r", "jl", "tex", "bib", "diff", "patch", "gitignore",
    "dockerfile", "makefile", "cmake", "gradle", "lock", "svg",
};

// How to run a command in a new terminal window, in order of preference.
// Override with e.g. FERNEDDA_TERMINAL="kitty".
const QList<QStringList> kTerminals = {
    {"alacritty", "-e"},
    {"kitty"},
    {"foot"},
    {"wezterm", "start", "--"},
    {"ghostty", "-e"},
    {"ptyxis", "--new-window", "--"},
    {"gnome-terminal", "--"},
    {"konsole", "-e"},
    {"xterm", "-e"},
};

QStringList terminalCommand()
{
    const QString env = qEnvironmentVariable("FERNEDDA_TERMINAL");
    if (!env.isEmpty())
        return QProcess::splitCommand(env);
    for (const QStringList &t : kTerminals)
        if (!QStandardPaths::findExecutable(t.first()).isEmpty())
            return t;
    return {};
}

}

bool Opener::isText(const QString &path)
{
    const QFileInfo fi(path);
    if (!fi.isFile())
        return false;
    const QString name = fi.fileName().toLower();
    const QString ext = name.contains('.') ? fi.suffix().toLower() : name;
    if (kTextExts.contains(ext) || fi.size() == 0)
        return true;

    // Looks at both the name and the file's contents, so README/Makefile etc. are caught too.
    const QMimeType mime = QMimeDatabase().mimeTypeForFile(fi);
    if (mime.inherits("text/plain"))
        return true;
    if (!mime.isDefault())  // a known, non-text type
        return false;

    // Unknown type: no NUL bytes in the first 8KB means text.
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return false;
    return !f.read(8192).contains('\0');
}

QString Opener::open(const QString &path)
{
    if (isText(path)) {
        const QString editor = qEnvironmentVariable("FERNEDDA_EDITOR", "nvim");
        QStringList cmd = terminalCommand();
        if (!cmd.isEmpty() && !QStandardPaths::findExecutable(editor).isEmpty()) {
            const QString program = cmd.takeFirst();
            if (QProcess::startDetached(program, cmd << editor << path, QFileInfo(path).absolutePath()))
                return editor;
        }
    }
    return QDesktopServices::openUrl(QUrl::fromLocalFile(path)) ? QStringLiteral("default app") : QString();
}
