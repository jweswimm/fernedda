#pragma once

#include <QMainWindow>

#include <memory>

class LandingPage;
class Project;
class ProjectView;
class QStackedWidget;

// Switches between the landing page and an open project.
class MainWindow : public QMainWindow {
    Q_OBJECT
public:
    explicit MainWindow(const QString &projectFile = {});

private:
    void showLanding();
    void newProject();
    void browseProject();
    void openProject(const QString &file);
    void showProject(std::unique_ptr<Project> project);

    QStackedWidget *m_stack;
    LandingPage *m_landing;
    ProjectView *m_view = nullptr;
};
