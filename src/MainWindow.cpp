#include "MainWindow.h"

#include "LandingPage.h"
#include "NewProjectDialog.h"
#include "Project.h"
#include "ProjectView.h"
#include "Recents.h"

#include <QFileDialog>
#include <QFileInfo>
#include <QMessageBox>
#include <QShortcut>
#include <QStackedWidget>
#include <QStandardPaths>

MainWindow::MainWindow(const QString &projectFile)
{
    m_stack = new QStackedWidget;
    m_landing = new LandingPage;
    m_stack->addWidget(m_landing);
    setCentralWidget(m_stack);

    connect(m_landing, &LandingPage::newProject, this, &MainWindow::newProject);
    connect(m_landing, &LandingPage::openProject, this, &MainWindow::browseProject);
    connect(m_landing, &LandingPage::openRecent, this, &MainWindow::openProject);
    connect(new QShortcut(QKeySequence::Quit, this), &QShortcut::activated, this, &QWidget::close);

    resize(1200, 800);
    showLanding();
    if (!projectFile.isEmpty())
        openProject(projectFile);
}

void MainWindow::showLanding()
{
    m_landing->reload();
    m_stack->setCurrentWidget(m_landing);
    setWindowTitle("fernedda");
    if (m_view) {
        m_view->deleteLater();  // may be called from one of its own signals
        m_view = nullptr;
    }
}

void MainWindow::newProject()
{
    NewProjectDialog dialog(this);
    if (dialog.exec() != QDialog::Accepted)
        return;
    QString error;
    auto project = Project::create(dialog.file(), dialog.name(), dialog.root(), &error);
    if (!project)
        return void(QMessageBox::warning(this, "Couldn't create project", error));
    showProject(std::move(project));
}

void MainWindow::browseProject()
{
    const QString file = QFileDialog::getOpenFileName(
        this, "Open project", QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation),
        "fernedda projects (*.fernedda)");
    if (!file.isEmpty())
        openProject(file);
}

void MainWindow::openProject(const QString &file)
{
    if (!QFileInfo::exists(file)) {
        if (QMessageBox::question(this, "Project not found",
                                  file + "\nwasn't found. Remove it from recent projects?")
            == QMessageBox::Yes) {
            Recents::remove(file);
            m_landing->reload();
        }
        return;
    }

    QString error;
    auto project = Project::open(file, &error);
    if (!project)
        return void(QMessageBox::warning(this, "Couldn't open project", error));

    // The mapped folder may have been moved or renamed since.
    if (!project->rootExists()) {
        if (QMessageBox::question(this, "Folder not found",
                                  "The folder for “" + project->name() + "” wasn't found:\n" + project->root()
                                      + "\n\nChoose where it is now?")
            != QMessageBox::Yes)
            return;
        const QString dir = QFileDialog::getExistingDirectory(this, "Where is “" + project->name() + "” now?");
        if (dir.isEmpty())
            return;
        if (!project->setRoot(dir, &error))
            return void(QMessageBox::warning(this, "Couldn't update project", error));
    }
    showProject(std::move(project));
}

void MainWindow::showProject(std::unique_ptr<Project> project)
{
    Recents::touch(project->file(), project->name(), project->root());
    if (m_view)
        m_view->deleteLater();
    m_view = new ProjectView(std::move(project), m_stack);
    m_stack->addWidget(m_view);
    m_stack->setCurrentWidget(m_view);
    m_view->setFocus();
    connect(m_view, &ProjectView::closeRequested, this, &MainWindow::showLanding);
}
