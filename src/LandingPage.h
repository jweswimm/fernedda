#pragma once

#include <QWidget>

class QListWidget;
class QLabel;

// First screen: start a new project, open one, or pick a recent one.
class LandingPage : public QWidget {
    Q_OBJECT
public:
    explicit LandingPage(QWidget *parent = nullptr);
    void reload();  // re-read the recent projects list

signals:
    void newProject();
    void openProject();
    void openRecent(const QString &file);

private:
    void openRow(int row);

    QListWidget *m_list;
    QLabel *m_empty;
};
