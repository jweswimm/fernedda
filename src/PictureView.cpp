#include "PictureView.h"

#include <QDragEnterEvent>
#include <QMimeData>
#include <QMouseEvent>
#include <QPainter>
#include <QPainterPath>

namespace {
constexpr int kMargin = 20;
constexpr qreal kRadius = 12;
constexpr qreal kDeleteRadius = 10;
const QColor kDanger(217, 83, 79);
}

PictureView::PictureView(QWidget *parent) : QWidget(parent)
{
    setMouseTracking(true);
    setAcceptDrops(true);
    setMinimumSize(200, 200);
}

void PictureView::setPicture(const QImage &image)
{
    m_image = image;
    m_scaled = QPixmap();
    m_pending = QRectF();
    m_hover = m_pressed = -1;
    update();
}

void PictureView::setHotspots(const QVector<Hotspot> &hotspots, const QSet<QString> &missing)
{
    m_hotspots = hotspots;
    m_missing = missing;
    m_hover = -1;
    update();
}

void PictureView::setEditing(bool editing)
{
    m_editing = editing;
    m_pending = QRectF();
    update();
}

void PictureView::clearPending()
{
    m_pending = QRectF();
    update();
    emit pendingChanged();
}

void PictureView::commitPending(const QString &target)
{
    if (m_pending.isNull())
        return;
    m_hotspots.push_back({m_pending, target});
    m_pending = QRectF();
    update();
    emit hotspotsChanged(m_hotspots);
    emit pendingChanged();
}

// ---------- geometry ----------

QRect PictureView::imageRect() const
{
    if (m_image.isNull())
        return {};
    const QRect avail = rect().adjusted(kMargin, kMargin, -kMargin, -kMargin);
    const QSize s = m_image.size().scaled(avail.size(), Qt::KeepAspectRatio);
    return QRect(avail.center() - QPoint(s.width() / 2, s.height() / 2), s);
}

QRect PictureView::emptyRect() const
{
    QRect r(0, 0, 380, 130);
    r.moveCenter(rect().center());
    return r;
}

QRectF PictureView::toWidget(const QRectF &f) const
{
    const QRectF ir = imageRect();
    return QRectF(ir.x() + f.x() * ir.width(), ir.y() + f.y() * ir.height(),
                  f.width() * ir.width(), f.height() * ir.height());
}

QPointF PictureView::toFrac(const QPointF &p) const
{
    const QRectF ir = imageRect();
    return {qBound(0.0, (p.x() - ir.x()) / ir.width(), 1.0), qBound(0.0, (p.y() - ir.y()) / ir.height(), 1.0)};
}

int PictureView::hotspotAt(const QPointF &p) const
{
    for (int i = m_hotspots.size() - 1; i >= 0; --i)  // topmost first
        if (toWidget(m_hotspots[i].rect).contains(p))
            return i;
    return -1;
}

int PictureView::deleteButtonAt(const QPointF &p) const
{
    if (!m_editing)
        return -1;
    for (int i = m_hotspots.size() - 1; i >= 0; --i) {
        const QPointF d = p - toWidget(m_hotspots[i].rect).topRight();
        if (QPointF::dotProduct(d, d) <= kDeleteRadius * kDeleteRadius)
            return i;
    }
    return -1;
}

// ---------- painting ----------

void PictureView::resizeEvent(QResizeEvent *)
{
    m_scaled = QPixmap();
}

void PictureView::paintEvent(QPaintEvent *)
{
    QPainter p(this);
    p.setRenderHint(QPainter::Antialiasing);
    const QPalette pal = palette();
    const QColor accent = pal.color(QPalette::Highlight);

    if (m_image.isNull()) {
        const QRect er = emptyRect();
        const bool hot = m_mouseInside && er.contains(mapFromGlobal(QCursor::pos()));
        QPen pen(hot ? accent : pal.color(QPalette::Mid), 2, Qt::DashLine);
        p.setPen(pen);
        p.setBrush(Qt::NoBrush);
        p.drawRoundedRect(QRectF(er).adjusted(1, 1, -1, -1), 16, 16);
        QFont f = font();
        f.setBold(true);
        f.setPointSizeF(f.pointSizeF() * 1.1);
        p.setFont(f);
        p.setPen(pal.color(QPalette::WindowText));
        p.drawText(er.adjusted(0, 0, 0, -er.height() / 2 + 4), Qt::AlignHCenter | Qt::AlignBottom,
                   "No picture for this folder yet");
        p.setFont(font());
        p.setPen(pal.color(QPalette::PlaceholderText));
        p.drawText(er.adjusted(0, er.height() / 2 + 4, 0, 0), Qt::AlignHCenter | Qt::AlignTop,
                   "Drop an image here, or click to choose one");
    } else {
        const QRect ir = imageRect();
        const qreal dpr = devicePixelRatioF();
        const QSize want = ir.size() * dpr;
        if (m_scaled.isNull() || m_scaled.size() != want) {
            m_scaled = QPixmap::fromImage(m_image.scaled(want, Qt::IgnoreAspectRatio, Qt::SmoothTransformation));
            m_scaled.setDevicePixelRatio(dpr);
        }
        QPainterPath clip;
        clip.addRoundedRect(ir, kRadius, kRadius);
        p.setClipPath(clip);
        p.drawPixmap(ir.topLeft(), m_scaled);
        p.setClipping(false);

        QFont labelFont = font();
        labelFont.setPointSizeF(labelFont.pointSizeF() * 0.9);
        const QFontMetrics fm(labelFont);

        for (int i = 0; i < m_hotspots.size(); ++i) {
            const QRectF r = toWidget(m_hotspots[i].rect);
            const bool missing = m_missing.contains(m_hotspots[i].target);
            const bool strong = m_editing || i == m_hover || missing;
            const QColor c = missing ? kDanger : accent;

            if (strong) {
                QColor fill = c;
                fill.setAlpha(45);
                p.setBrush(fill);
                p.setPen(QPen(c, 2));
            } else if (m_mouseInside) {
                p.setBrush(Qt::NoBrush);
                p.setPen(QPen(QColor(255, 255, 255, 90), 1));
            } else {
                continue;
            }
            p.drawRoundedRect(r.adjusted(1, 1, -1, -1), 8, 8);

            if (m_editing || i == m_hover) {
                const QString name = m_hotspots[i].target == ".." ? "↑ Parent folder" : m_hotspots[i].target;
                const QString text = fm.elidedText(name, Qt::ElideRight, int(r.width()) - 26);
                const QRectF lr(r.left() + 6, r.bottom() - 6 - fm.height() - 8, fm.horizontalAdvance(text) + 14,
                                fm.height() + 8);
                p.setPen(Qt::NoPen);
                p.setBrush(QColor(0, 0, 0, 185));
                p.drawRoundedRect(lr, 6, 6);
                p.setPen(Qt::white);
                p.setFont(labelFont);
                p.drawText(lr, Qt::AlignCenter, text);
            }
            if (m_editing) {
                const QPointF c2 = r.topRight();
                p.setPen(Qt::NoPen);
                p.setBrush(kDanger);
                p.drawEllipse(c2, kDeleteRadius, kDeleteRadius);
                p.setPen(QPen(Qt::white, 1.6, Qt::SolidLine, Qt::RoundCap));
                const qreal k = 3.5;
                p.drawLine(c2 + QPointF(-k, -k), c2 + QPointF(k, k));
                p.drawLine(c2 + QPointF(-k, k), c2 + QPointF(k, -k));
            }
        }

        if (!m_pending.isNull()) {
            const QRectF r = toWidget(m_pending);
            QColor fill = accent;
            fill.setAlpha(45);
            p.setBrush(fill);
            p.setPen(QPen(Qt::white, 2, Qt::DashLine));
            p.drawRoundedRect(r, 8, 8);
        }
    }

    if (m_dropping) {
        const QRectF r = QRectF(rect()).adjusted(12, 12, -12, -12);
        QColor fill = accent;
        fill.setAlpha(40);
        p.setBrush(fill);
        p.setPen(QPen(accent, 2, Qt::DashLine));
        p.drawRoundedRect(r, 14, 14);
        QFont f = font();
        f.setBold(true);
        p.setFont(f);
        p.setPen(accent);
        p.drawText(r, Qt::AlignCenter, "Drop to set picture");
    }
}

// ---------- mouse ----------

void PictureView::updateHover(const QPointF &pos)
{
    const int hover = hotspotAt(pos);
    if (hover != m_hover) {
        m_hover = hover;
        if (hover >= 0)
            emit hovered(m_hotspots[hover].target);
    }

    if (m_image.isNull())
        setCursor(emptyRect().contains(pos.toPoint()) ? Qt::PointingHandCursor : Qt::ArrowCursor);
    else if (deleteButtonAt(pos) >= 0)
        setCursor(Qt::PointingHandCursor);
    else if (m_editing)
        setCursor(hover >= 0 ? Qt::ArrowCursor : imageRect().contains(pos.toPoint()) ? Qt::CrossCursor : Qt::ArrowCursor);
    else
        setCursor(hover >= 0 ? Qt::PointingHandCursor : Qt::ArrowCursor);
    update();
}

void PictureView::mousePressEvent(QMouseEvent *e)
{
    if (e->button() != Qt::LeftButton) {
        e->ignore();  // let back/forward buttons reach the window
        return;
    }
    const QPointF pos = e->position();
    if (m_image.isNull()) {
        if (emptyRect().contains(pos.toPoint()))
            emit chooseImage();
        return;
    }
    if (m_editing) {
        if (const int d = deleteButtonAt(pos); d >= 0) {
            m_hotspots.removeAt(d);
            m_hover = -1;
            update();
            emit hotspotsChanged(m_hotspots);
            return;
        }
        if (hotspotAt(pos) >= 0 || !imageRect().contains(pos.toPoint()))
            return;
        m_dragging = true;
        m_dragStart = toFrac(pos);
        m_pending = QRectF(m_dragStart, QSizeF(0, 0));
        update();
        return;
    }
    m_pressed = hotspotAt(pos);
}

void PictureView::mouseMoveEvent(QMouseEvent *e)
{
    m_mouseInside = true;
    if (m_dragging) {
        m_pending = QRectF(m_dragStart, toFrac(e->position())).normalized();
        update();
        return;
    }
    updateHover(e->position());
}

void PictureView::mouseReleaseEvent(QMouseEvent *e)
{
    if (e->button() != Qt::LeftButton) {
        e->ignore();
        return;
    }
    if (m_dragging) {
        m_dragging = false;
        if (m_pending.width() < 0.01 || m_pending.height() < 0.01)
            m_pending = QRectF();
        update();
        emit pendingChanged();
        return;
    }
    const int i = hotspotAt(e->position());
    if (i >= 0 && i == m_pressed)
        emit activated(m_hotspots[i].target);
    m_pressed = -1;
}

void PictureView::leaveEvent(QEvent *)
{
    m_mouseInside = false;
    m_hover = -1;
    update();
}

// ---------- drag & drop ----------

static QString droppedImage(const QMimeData *mime)
{
    for (const QUrl &url : mime->urls()) {
        if (!url.isLocalFile())
            continue;
        const QString f = url.toLocalFile();
        const QString ext = f.section('.', -1).toLower();
        static const QSet<QString> exts = {"png", "jpg", "jpeg", "gif", "webp", "bmp", "svg", "tif", "tiff", "avif"};
        if (exts.contains(ext))
            return f;
    }
    return {};
}

void PictureView::dragEnterEvent(QDragEnterEvent *e)
{
    if (!droppedImage(e->mimeData()).isEmpty()) {
        e->acceptProposedAction();
        m_dropping = true;
        update();
    }
}

void PictureView::dragLeaveEvent(QDragLeaveEvent *)
{
    m_dropping = false;
    update();
}

void PictureView::dropEvent(QDropEvent *e)
{
    m_dropping = false;
    update();
    const QString f = droppedImage(e->mimeData());
    if (!f.isEmpty()) {
        e->acceptProposedAction();
        emit imageDropped(f);
    }
}
