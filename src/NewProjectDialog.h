#pragma once

#include <QDialog>

class QLabel;
class QLineEdit;
class QPushButton;

// Asks for a project name, the folder it maps, and where to save the .fernedda file.
class NewProjectDialog : public QDialog {
    Q_OBJECT
public:
    explicit NewProjectDialog(QWidget *parent = nullptr);

    QString name() const;
    QString root() const;
    QString file() const;

    void accept() override;

private:
    void suggestFile();
    void validate();

    QLineEdit *m_name;
    QLineEdit *m_root;
    QLineEdit *m_file;
    QLabel *m_error;
    QPushButton *m_create;
    bool m_fileEdited = false;
};
