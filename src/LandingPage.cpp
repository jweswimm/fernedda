#include "LandingPage.h"

#include "Recents.h"

#include <QDir>
#include <QFileInfo>
#include <QHBoxLayout>
#include <QLabel>
#include <QListWidget>
#include <QMenu>
#include <QPainter>
#include <QPushButton>
#include <QShortcut>
#include <QStyledItemDelegate>
#include <QVBoxLayout>

namespace {

enum Role { FileRole = Qt::UserRole, NameRole, RootRole, OpenedRole, MissingRole };

QString tildePath(const QString &path)
{
    const QString home = QDir::homePath();
    return path == home ? "~" : path.startsWith(home + "/") ? "~" + path.mid(home.size()) : path;
}

QString relativeTime(const QDateTime &t)
{
    if (!t.isValid())
        return {};
    const qint64 s = t.secsTo(QDateTime::currentDateTime());
    if (s < 60)
        return "just now";
    if (s < 3600)
        return QString("%1 min ago").arg(s / 60);
    const qint64 days = t.date().daysTo(QDate::currentDate());
    if (days == 0)
        return QString("%1 h ago").arg(s / 3600);
    if (days == 1)
        return "yesterday";
    if (days < 7)
        return QString("%1 days ago").arg(days);
    return QLocale().toString(t.date(), QLocale::ShortFormat);
}

// Two-line row: project name + root folder on the left, last opened on the right.
class RecentDelegate : public QStyledItemDelegate {
public:
    using QStyledItemDelegate::QStyledItemDelegate;

    QSize sizeHint(const QStyleOptionViewItem &opt, const QModelIndex &) const override
    {
        return {opt.rect.width(), opt.fontMetrics.height() * 2 + 26};
    }

    void paint(QPainter *p, const QStyleOptionViewItem &opt, const QModelIndex &idx) const override
    {
        const QPalette &pal = opt.palette;
        const bool missing = idx.data(MissingRole).toBool();
        const QRectF r = QRectF(opt.rect).adjusted(0, 2, 0, -2);

        p->save();
        p->setRenderHint(QPainter::Antialiasing);
        if (opt.state & (QStyle::State_MouseOver | QStyle::State_Selected)) {
            p->setPen(Qt::NoPen);
            p->setBrush(pal.color(QPalette::AlternateBase));
            p->drawRoundedRect(r, 9, 9);
        }

        const QRectF content = r.adjusted(14, 0, -14, 0);
        const QString number = idx.row() < 9 ? QString::number(idx.row() + 1) : QString();
        QFont small = opt.font;
        small.setPointSizeF(small.pointSizeF() * 0.9);
        const QFontMetrics sfm(small);

        // Right side: when it was opened, and its 1-9 shortcut
        const QString when = missing ? "File not found" : relativeTime(idx.data(OpenedRole).toDateTime());
        p->setFont(small);
        p->setPen(missing ? QColor(217, 83, 79) : pal.color(QPalette::PlaceholderText));
        p->drawText(content, Qt::AlignRight | Qt::AlignVCenter, when);
        const int rightWidth = sfm.horizontalAdvance(when) + 16;

        // Left side: name over root path
        QFont bold = opt.font;
        bold.setWeight(QFont::DemiBold);
        const QFontMetrics bfm(bold);
        const qreal lineGap = 2;
        const qreal top = content.center().y() - (bfm.height() + sfm.height() + lineGap) / 2;
        const qreal textWidth = content.width() - rightWidth;
        p->setFont(bold);
        p->setPen(missing ? pal.color(QPalette::PlaceholderText) : pal.color(QPalette::Text));
        const QString name = bfm.elidedText(idx.data(NameRole).toString(), Qt::ElideRight, int(textWidth) - 30);
        p->drawText(QPointF(content.left(), top + bfm.ascent()), name);
        if (!number.isEmpty()) {
            p->setFont(small);
            p->setPen(pal.color(QPalette::Mid).lighter(160));
            p->drawText(QPointF(content.left() + bfm.horizontalAdvance(name) + 8, top + bfm.ascent()), number);
        }
        p->setFont(small);
        p->setPen(pal.color(QPalette::PlaceholderText));
        p->drawText(QPointF(content.left(), top + bfm.height() + lineGap + sfm.ascent()),
                    sfm.elidedText(tildePath(idx.data(RootRole).toString()), Qt::ElideMiddle, int(textWidth)));
        p->restore();
    }
};

}

LandingPage::LandingPage(QWidget *parent) : QWidget(parent)
{
    setObjectName("landing");

    auto *title = new QLabel("fernedda");
    title->setObjectName("title");
    auto *subtitle = new QLabel("Navigate your files through pictures");
    subtitle->setObjectName("subtitle");

    auto *newBtn = new QPushButton("New project");
    newBtn->setObjectName("primary");
    newBtn->setToolTip("Ctrl+N");
    auto *openBtn = new QPushButton("Open project…");
    openBtn->setObjectName("big");
    openBtn->setToolTip("Ctrl+O");
    auto *buttons = new QHBoxLayout;
    buttons->setSpacing(10);
    buttons->addWidget(newBtn, 1);
    buttons->addWidget(openBtn, 1);

    auto *recentLabel = new QLabel("RECENT");
    recentLabel->setObjectName("section");

    m_list = new QListWidget;
    m_list->setObjectName("recent");
    m_list->setItemDelegate(new RecentDelegate(m_list));
    m_list->setFrameShape(QFrame::NoFrame);
    m_list->setMouseTracking(true);
    m_list->setContextMenuPolicy(Qt::CustomContextMenu);
    m_list->setVerticalScrollMode(QAbstractItemView::ScrollPerPixel);

    m_empty = new QLabel("No recent projects yet");
    m_empty->setObjectName("empty");
    m_empty->setAlignment(Qt::AlignCenter);

    // Centered column
    auto *column = new QWidget;
    column->setMaximumWidth(560);
    auto *cl = new QVBoxLayout(column);
    cl->setContentsMargins(0, 0, 0, 0);
    cl->setSpacing(0);
    cl->addWidget(title);
    cl->addSpacing(2);
    cl->addWidget(subtitle);
    cl->addSpacing(28);
    cl->addLayout(buttons);
    cl->addSpacing(32);
    cl->addWidget(recentLabel);
    cl->addSpacing(6);
    cl->addWidget(m_list, 1);
    cl->addWidget(m_empty);
    cl->addStretch();

    auto *outer = new QHBoxLayout(this);
    outer->setContentsMargins(24, 64, 24, 24);
    outer->addStretch();
    outer->addWidget(column, 100);
    outer->addStretch();

    connect(newBtn, &QPushButton::clicked, this, &LandingPage::newProject);
    connect(openBtn, &QPushButton::clicked, this, &LandingPage::openProject);
    connect(m_list, &QListWidget::itemActivated, this, [this](QListWidgetItem *it) { openRow(m_list->row(it)); });
    connect(m_list, &QWidget::customContextMenuRequested, this, [this](const QPoint &pos) {
        QListWidgetItem *it = m_list->itemAt(pos);
        if (!it)
            return;
        QMenu menu;
        menu.addAction("Remove from recent", this, [this, it] {
            Recents::remove(it->data(FileRole).toString());
            reload();
        });
        menu.exec(m_list->viewport()->mapToGlobal(pos));
    });

    connect(new QShortcut(QKeySequence::New, this), &QShortcut::activated, this, &LandingPage::newProject);
    connect(new QShortcut(QKeySequence::Open, this), &QShortcut::activated, this, &LandingPage::openProject);
    for (int i = 0; i < 9; ++i)
        connect(new QShortcut(Qt::Key_1 + i, this), &QShortcut::activated, this, [this, i] { openRow(i); });

    reload();
}

void LandingPage::reload()
{
    m_list->clear();
    for (const Recents::Entry &e : Recents::load()) {
        auto *it = new QListWidgetItem(m_list);
        it->setData(FileRole, e.file);
        it->setData(NameRole, e.name);
        it->setData(RootRole, e.root);
        it->setData(OpenedRole, e.opened);
        it->setData(MissingRole, !QFileInfo::exists(e.file));
        it->setToolTip(tildePath(e.file));
    }
    const bool any = m_list->count() > 0;
    m_list->setVisible(any);
    m_empty->setVisible(!any);
    if (any) {
        m_list->setCurrentRow(0);  // Enter opens the most recent project
        m_list->setFocus();
    }
}

void LandingPage::openRow(int row)
{
    if (QListWidgetItem *it = m_list->item(row))
        emit openRecent(it->data(FileRole).toString());
}
