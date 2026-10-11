#include "MainWindow.h"

#include "Opener.h"
#include "PictureView.h"

#include <QApplication>
#include <QDir>
#include <QFileDialog>
#include <QFileIconProvider>
#include <QHBoxLayout>
#include <QImageReader>
#include <QLabel>
#include <QListWidget>
#include <QMouseEvent>
#include <QPushButton>
#include <QShortcut>
#include <QSplitter>
#include <QTimer>
#include <QToolButton>
#include <QVBoxLayout>
#include <QtConcurrent>

#include <algorithm>

namespace {

constexpr int kMaxImageSide = 3840;  // big photos are downscaled once on load
constexpr int kMaxCachedImages = 40;

enum Role { NameRole = Qt::UserRole, DirRole };

QImage loadImage(const QString &file)
{
    QImageReader reader(file);
    reader.setAutoTransform(true);
    const QSize s = reader.size();
    if (s.isValid() && qMax(s.width(), s.height()) > kMaxImageSide)
        reader.setScaledSize(s.scaled(kMaxImageSide, kMaxImageSide, Qt::KeepAspectRatio));
    return reader.read();
}

}

MainWindow::MainWindow(const QString &startPath)
{
    // Header: breadcrumbs + buttons
    auto *header = new QWidget;
    header->setObjectName("header");
    auto *hl = new QHBoxLayout(header);
    hl->setContentsMargins(10, 6, 10, 6);
    hl->setSpacing(8);
    m_crumbs = new QWidget;
    m_crumbs->setSizePolicy(QSizePolicy::Ignored, QSizePolicy::Preferred);
    m_crumbLayout = new QHBoxLayout(m_crumbs);
    m_crumbLayout->setContentsMargins(0, 0, 0, 0);
    m_crumbLayout->setSpacing(0);
    m_replaceBtn = new QPushButton("Change picture");
    m_editBtn = new QPushButton("Edit");
    m_editBtn->setToolTip("Edit regions (E)");
    m_editBtn->setObjectName("edit");
    hl->addWidget(m_crumbs, 1);
    hl->addWidget(m_replaceBtn);
    hl->addWidget(m_editBtn);

    // Picture
    m_view = new PictureView;

    // Sidebar
    auto *side = new QWidget;
    side->setObjectName("side");
    auto *sl = new QVBoxLayout(side);
    sl->setContentsMargins(0, 0, 0, 0);
    sl->setSpacing(0);
    m_hint = new QLabel;
    m_hint->setObjectName("hint");
    m_hint->setWordWrap(true);
    m_list = new QListWidget;
    m_list->setFrameShape(QFrame::NoFrame);
    m_list->setUniformItemSizes(true);
    m_list->setTextElideMode(Qt::ElideMiddle);
    m_list->setMouseTracking(true);
    sl->addWidget(m_hint);
    sl->addWidget(m_list);

    auto *split = new QSplitter;
    split->addWidget(m_view);
    split->addWidget(side);
    split->setStretchFactor(0, 1);
    split->setCollapsible(0, false);
    split->setSizes({900, 260});
    split->setHandleWidth(1);

    auto *central = new QWidget;
    auto *cl = new QVBoxLayout(central);
    cl->setContentsMargins(0, 0, 0, 0);
    cl->setSpacing(0);
    cl->addWidget(header);
    cl->addWidget(split, 1);
    setCentralWidget(central);

    m_toast = new QLabel(central);
    m_toast->setObjectName("toast");
    m_toast->hide();
    m_toastTimer = new QTimer(this);
    m_toastTimer->setSingleShot(true);
    connect(m_toastTimer, &QTimer::timeout, m_toast, &QWidget::hide);

    // Wiring
    connect(m_editBtn, &QPushButton::clicked, this, &MainWindow::toggleEdit);
    connect(m_replaceBtn, &QPushButton::clicked, this, &MainWindow::chooseImage);
    connect(m_view, &PictureView::chooseImage, this, &MainWindow::chooseImage);
    connect(m_view, &PictureView::imageDropped, this, &MainWindow::setImage);
    connect(m_view, &PictureView::activated, this, &MainWindow::activate);
    connect(m_view, &PictureView::pendingChanged, this, [this] { renderHint(); });
    connect(m_view, &PictureView::hovered, this, [this](const QString &t) {
        if (isDir(t) && exists(t))
            prefetch(join(t));
    });
    connect(m_view, &PictureView::hotspotsChanged, this, [this](const QVector<Hotspot> &h) {
        m_map.hotspots = h;
        m_store.setHotspots(m_path, h);
        renderList();
        renderHint();
    });
    connect(m_list, &QListWidget::itemActivated, this,
            [this](QListWidgetItem *it) { activate(it->data(NameRole).toString()); });
    connect(m_list, &QListWidget::itemEntered, this, [this](QListWidgetItem *it) {
        if (it->data(DirRole).toBool())
            prefetch(join(it->data(NameRole).toString()));
    });

    auto shortcut = [this](const QKeySequence &k, auto fn) {
        connect(new QShortcut(k, this), &QShortcut::activated, this, fn);
    };
    shortcut(Qt::Key_E, &MainWindow::toggleEdit);
    shortcut(Qt::Key_Escape, &MainWindow::cancel);
    shortcut(Qt::Key_Backspace, &MainWindow::goUp);
    shortcut(Qt::ALT | Qt::Key_Up, &MainWindow::goUp);
    shortcut(QKeySequence::Back, &MainWindow::goBack);
    shortcut(QKeySequence::Forward, &MainWindow::goForward);
    shortcut(QKeySequence::Refresh, &MainWindow::refresh);
    shortcut(Qt::CTRL | Qt::Key_O, &MainWindow::chooseImage);
    shortcut(QKeySequence::Quit, &QWidget::close);

    qApp->installEventFilter(this);  // mouse back/forward buttons

    resize(1200, 800);
    navigate(startPath, false);
}

// ---------- navigation ----------

void MainWindow::navigate(const QString &path, bool record)
{
    const QFileInfo fi(path);
    const QString canon = fi.canonicalFilePath();
    if (canon.isEmpty() || !fi.isDir())
        return toast("Not a folder: " + path);
    QDir dir(canon);
    if (!dir.isReadable())
        return toast("Permission denied: " + canon);

    if (record && !m_path.isEmpty() && canon != m_path) {
        m_back.push_back(m_path);
        m_forward.clear();
    }
    m_path = canon;
    m_parent = dir.isRoot() ? QString() : QFileInfo(canon).absolutePath();

    m_entries.clear();
    for (const QFileInfo &e : dir.entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot,
                                                QDir::DirsFirst | QDir::Name | QDir::IgnoreCase))
        m_entries.push_back({e.fileName(), e.isDir()});
    m_map = m_store.get(m_path);
    render();
}

void MainWindow::refresh()
{
    navigate(m_path, false);
}

void MainWindow::goBack()
{
    if (m_back.isEmpty())
        return;
    m_forward.push_back(m_path);
    navigate(m_back.takeLast(), false);
}

void MainWindow::goForward()
{
    if (m_forward.isEmpty())
        return;
    m_back.push_back(m_path);
    navigate(m_forward.takeLast(), false);
}

void MainWindow::goUp()
{
    if (!m_parent.isEmpty())
        navigate(m_parent);
}

void MainWindow::activate(const QString &name)
{
    if (m_editing && m_view->hasPending())
        return m_view->commitPending(name);
    if (!exists(name))
        return toast("Missing: " + name);
    const QString path = join(name);
    if (isDir(name))
        return navigate(path);
    const QString with = Opener::open(path);
    toast(with.isEmpty() ? "Couldn't open " + name : "Opened " + name + " in " + with);
}

QString MainWindow::join(const QString &name) const
{
    return name == ".." ? m_parent : QDir(m_path).filePath(name);
}

bool MainWindow::exists(const QString &name) const
{
    if (name == "..")
        return !m_parent.isEmpty();
    return std::any_of(m_entries.begin(), m_entries.end(), [&](const Entry &e) { return e.name == name; });
}

bool MainWindow::isDir(const QString &name) const
{
    if (name == "..")
        return true;
    return std::any_of(m_entries.begin(), m_entries.end(), [&](const Entry &e) { return e.dir && e.name == name; });
}

// ---------- images ----------

QImage MainWindow::image(const QString &name)
{
    if (name.isEmpty())
        return {};
    auto it = m_images.constFind(name);
    if (it != m_images.constEnd())
        return *it;
    if (m_images.size() >= kMaxCachedImages)
        m_images.clear();
    return m_images[name] = loadImage(m_store.imagePath(name));
}

// Decode a folder's picture in the background so clicking into it is instant.
void MainWindow::prefetch(const QString &folder)
{
    const QString name = m_store.get(folder).image;
    if (name.isEmpty() || m_images.contains(name) || m_loading.contains(name))
        return;
    m_loading.insert(name);
    QtConcurrent::run(loadImage, m_store.imagePath(name)).then(this, [this, name](const QImage &img) {
        m_loading.remove(name);
        if (m_images.size() >= kMaxCachedImages)
            m_images.clear();
        m_images.insert(name, img);
    });
}

void MainWindow::chooseImage()
{
    const QString f = QFileDialog::getOpenFileName(this, "Choose a picture for this folder", m_path,
                                                   "Images (*.png *.jpg *.jpeg *.gif *.webp *.bmp *.svg *.tif *.tiff *.avif)");
    if (!f.isEmpty())
        setImage(f);
}

void MainWindow::setImage(const QString &file)
{
    if (loadImage(file).isNull())
        return toast("That isn't an image Qt can read");
    if (!m_store.setImage(m_path, file))
        return toast("Couldn't save the picture");
    m_map = m_store.get(m_path);
    render();
}

// ---------- rendering ----------

void MainWindow::render()
{
    setWindowTitle(QFileInfo(m_path).fileName().isEmpty() ? "/ — fernedda"
                                                          : QFileInfo(m_path).fileName() + " — fernedda");
    m_editBtn->setText(m_editing ? "Done" : "Edit");
    m_editBtn->setProperty("on", m_editing);
    m_editBtn->style()->polish(m_editBtn);
    m_replaceBtn->setVisible(m_editing && !m_map.image.isEmpty());

    QSet<QString> missing;
    for (const Hotspot &h : m_map.hotspots)
        if (!exists(h.target))
            missing.insert(h.target);
    m_view->setPicture(image(m_map.image));
    m_view->setHotspots(m_map.hotspots, missing);
    m_view->setEditing(m_editing);

    renderCrumbs();
    renderList();
    renderHint();
}

void MainWindow::renderCrumbs()
{
    while (QLayoutItem *item = m_crumbLayout->takeAt(0)) {
        delete item->widget();
        delete item;
    }
    auto addCrumb = [this](const QString &label, const QString &path, bool last) {
        auto *b = new QToolButton;
        b->setText(label);
        b->setAutoRaise(true);
        b->setProperty("crumb", last ? "last" : "");
        connect(b, &QToolButton::clicked, this, [this, path] { navigate(path); });
        m_crumbLayout->addWidget(b);
    };
    const QStringList parts = m_path.split('/', Qt::SkipEmptyParts);
    addCrumb("/", "/", parts.isEmpty());
    QString acc;
    for (int i = 0; i < parts.size(); ++i) {
        acc += "/" + parts[i];
        if (i > 0) {
            auto *sep = new QLabel("/");
            sep->setObjectName("sep");
            m_crumbLayout->addWidget(sep);
        }
        addCrumb(parts[i], acc, i == parts.size() - 1);
    }
    m_crumbLayout->addStretch();
}

void MainWindow::renderList()
{
    static QFileIconProvider icons;
    static const QIcon dirIcon = icons.icon(QAbstractFileIconProvider::Folder);
    static const QIcon fileIcon = icons.icon(QAbstractFileIconProvider::File);

    QSet<QString> mapped;
    for (const Hotspot &h : m_map.hotspots)
        mapped.insert(h.target);

    m_list->setUpdatesEnabled(false);
    m_list->clear();
    auto add = [&](const QString &name, bool dir, const QString &label) {
        auto *it = new QListWidgetItem(dir ? dirIcon : fileIcon, label, m_list);
        it->setData(NameRole, name);
        it->setData(DirRole, dir);
        if (mapped.contains(name)) {
            QFont f = m_list->font();
            f.setBold(true);
            it->setFont(f);
            it->setForeground(palette().color(QPalette::Highlight));
        }
    };
    if (!m_parent.isEmpty())
        add("..", true, "↑ Parent folder");
    for (const Entry &e : m_entries)
        add(e.name, e.dir, e.name);
    m_list->setUpdatesEnabled(true);
}

void MainWindow::renderHint()
{
    m_hint->setVisible(m_editing);
    const bool picking = m_view->hasPending();
    m_hint->setProperty("ask", picking);
    m_hint->style()->polish(m_hint);
    m_hint->setText(m_map.image.isEmpty() ? "Add a picture first"
                    : picking            ? "Now pick what this region opens ↓  (Esc to cancel)"
                                         : "Drag on the picture to draw a region");
}

// ---------- misc ----------

void MainWindow::toggleEdit()
{
    m_editing = !m_editing;
    render();
}

void MainWindow::cancel()
{
    if (m_view->hasPending())
        m_view->clearPending();
    else if (m_editing)
        toggleEdit();
}

void MainWindow::toast(const QString &msg)
{
    m_toast->setText(msg);
    m_toast->adjustSize();
    const QWidget *c = centralWidget();
    m_toast->move((c->width() - m_toast->width()) / 2, c->height() - m_toast->height() - 20);
    m_toast->raise();
    m_toast->show();
    m_toastTimer->start(1800);
}

void MainWindow::resizeEvent(QResizeEvent *e)
{
    QMainWindow::resizeEvent(e);
    if (m_toast->isVisible())
        toast(m_toast->text());
}

bool MainWindow::eventFilter(QObject *obj, QEvent *e)
{
    if (e->type() == QEvent::MouseButtonPress) {
        const auto *me = static_cast<QMouseEvent *>(e);
        if (me->button() == Qt::BackButton) {
            goBack();
            return true;
        }
        if (me->button() == Qt::ForwardButton) {
            goForward();
            return true;
        }
    }
    return QMainWindow::eventFilter(obj, e);
}
