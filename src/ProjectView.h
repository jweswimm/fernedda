#pragma once

#include "Project.h"

#include <QHash>
#include <QImage>
#include <QSet>
#include <QWidget>

#include <memory>

class PictureView;
class QHBoxLayout;
class QLabel;
class QListWidget;
class QPushButton;
class QTimer;

// Browsing an open project: picture with regions, breadcrumbs, and the folder listing.
class ProjectView : public QWidget {
    Q_OBJECT
public:
    ProjectView(std::unique_ptr<Project> project, QWidget *parent);
    ~ProjectView() override;

signals:
    void closeRequested();

protected:
    bool eventFilter(QObject *obj, QEvent *e) override;
    void resizeEvent(QResizeEvent *e) override;

private:
    struct Entry {
        QString name;
        bool dir;
    };

    void navigate(const QString &path, bool record = true);
    void refresh();
    void render();
    void renderCrumbs();
    void renderList();
    void renderHint();
    void activate(const QString &name);
    void goBack();
    void goForward();
    void goUp();
    void toggleEdit();
    void cancel();
    void chooseImage();
    void setImage(const QString &file);
    void toast(const QString &msg);

    QString join(const QString &name) const;
    bool exists(const QString &name) const;
    bool isDir(const QString &name) const;
    QImage image(const QString &name);
    void prefetch(const QString &folder);

    std::unique_ptr<Project> m_project;
    QString m_path, m_parent;
    QVector<Entry> m_entries;
    FolderMap m_map;
    QStringList m_back, m_forward;
    bool m_editing = false;

    QHash<QString, QImage> m_images;  // image name -> decoded image
    QSet<QString> m_loading;

    QHBoxLayout *m_crumbLayout;
    QPushButton *m_replaceBtn;
    QPushButton *m_editBtn;
    PictureView *m_view;
    QLabel *m_hint;
    QListWidget *m_list;
    QLabel *m_toast;
    QTimer *m_toastTimer;
};
