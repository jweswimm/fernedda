#include "NewProjectDialog.h"

#include <QDialogButtonBox>
#include <QDir>
#include <QFileDialog>
#include <QFileInfo>
#include <QFormLayout>
#include <QHBoxLayout>
#include <QLabel>
#include <QLineEdit>
#include <QMessageBox>
#include <QPushButton>
#include <QStandardPaths>
#include <QVBoxLayout>

namespace {

QString expandTilde(QString path)
{
    path = path.trimmed();
    if (path == "~" || path.startsWith("~/"))
        path.replace(0, 1, QDir::homePath());
    return path;
}

QString defaultSaveDir()
{
    const QString docs = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    return QFileInfo(docs).isDir() ? docs : QDir::homePath();
}

}

NewProjectDialog::NewProjectDialog(QWidget *parent) : QDialog(parent)
{
    setWindowTitle("New project");
    setMinimumWidth(520);

    m_name = new QLineEdit;
    m_name->setPlaceholderText("e.g. Photos");
    m_root = new QLineEdit(QDir::homePath());
    m_file = new QLineEdit;

    auto withBrowse = [](QLineEdit *edit, QPushButton *&button) {
        auto *row = new QHBoxLayout;
        row->setSpacing(6);
        button = new QPushButton("Browse…");
        row->addWidget(edit, 1);
        row->addWidget(button);
        return row;
    };
    QPushButton *rootBrowse, *fileBrowse;

    auto *form = new QFormLayout;
    form->setVerticalSpacing(10);
    form->addRow("Name", m_name);
    form->addRow("Folder", withBrowse(m_root, rootBrowse));
    form->addRow("Save as", withBrowse(m_file, fileBrowse));

    m_error = new QLabel;
    m_error->setObjectName("error");

    auto *buttons = new QDialogButtonBox(QDialogButtonBox::Cancel);
    m_create = buttons->addButton("Create", QDialogButtonBox::AcceptRole);
    m_create->setObjectName("primary");
    m_create->setDefault(true);

    auto *layout = new QVBoxLayout(this);
    layout->setContentsMargins(20, 20, 20, 16);
    auto *hint = new QLabel("The project maps a folder and everything inside it.");
    hint->setObjectName("subtitle");
    layout->addWidget(hint);
    layout->addSpacing(12);
    layout->addLayout(form);
    layout->addSpacing(4);
    layout->addWidget(m_error);
    layout->addStretch();
    layout->addWidget(buttons);

    connect(buttons, &QDialogButtonBox::accepted, this, &QDialog::accept);
    connect(buttons, &QDialogButtonBox::rejected, this, &QDialog::reject);
    connect(m_name, &QLineEdit::textChanged, this, [this] { suggestFile(); validate(); });
    connect(m_root, &QLineEdit::textChanged, this, &NewProjectDialog::validate);
    connect(m_file, &QLineEdit::textEdited, this, [this] { m_fileEdited = true; validate(); });

    connect(rootBrowse, &QPushButton::clicked, this, [this] {
        const QString dir = QFileDialog::getExistingDirectory(this, "Folder to map", root());
        if (dir.isEmpty())
            return;
        m_root->setText(dir);
        if (m_name->text().trimmed().isEmpty())
            m_name->setText(QFileInfo(dir).fileName());
    });
    connect(fileBrowse, &QPushButton::clicked, this, [this] {
        QString f = QFileDialog::getSaveFileName(this, "Save project as", file(), "fernedda projects (*.fernedda)",
                                                 nullptr, QFileDialog::DontConfirmOverwrite);
        if (f.isEmpty())
            return;
        if (!f.endsWith(".fernedda"))
            f += ".fernedda";
        m_file->setText(f);
        m_fileEdited = true;
        validate();
    });

    suggestFile();
    validate();
}

QString NewProjectDialog::name() const
{
    return m_name->text().trimmed();
}

QString NewProjectDialog::root() const
{
    return expandTilde(m_root->text());
}

QString NewProjectDialog::file() const
{
    QString f = expandTilde(m_file->text());
    if (!f.isEmpty() && !f.endsWith(".fernedda"))
        f += ".fernedda";
    return f;
}

// Keep the save path in step with the name until the user picks one themselves.
void NewProjectDialog::suggestFile()
{
    if (m_fileEdited)
        return;
    QString base = name();
    base.replace('/', '-');
    if (base.isEmpty())
        base = "untitled";
    m_file->setText(defaultSaveDir() + "/" + base + ".fernedda");
}

void NewProjectDialog::validate()
{
    QString error;
    if (!QFileInfo(root()).isDir())
        error = "That folder doesn't exist.";
    else if (!QFileInfo(QFileInfo(file()).absolutePath()).isDir())
        error = "The save location's folder doesn't exist.";
    m_error->setText(error);
    m_error->setVisible(!error.isEmpty());
    m_create->setEnabled(error.isEmpty() && !name().isEmpty() && !file().isEmpty());
}

void NewProjectDialog::accept()
{
    if (QFileInfo::exists(file())
        && QMessageBox::question(this, "Replace project?",
                                 QFileInfo(file()).fileName() + " already exists. Replace it?")
               != QMessageBox::Yes)
        return;
    QDialog::accept();
}
