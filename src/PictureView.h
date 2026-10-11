#pragma once

#include "Store.h"

#include <QImage>
#include <QPixmap>
#include <QSet>
#include <QWidget>

// Shows a folder's picture with clickable regions. In edit mode, drag to draw a region.
class PictureView : public QWidget {
    Q_OBJECT
public:
    explicit PictureView(QWidget *parent = nullptr);

    void setPicture(const QImage &image);  // null image shows the empty state
    void setHotspots(const QVector<Hotspot> &hotspots, const QSet<QString> &missing);
    void setEditing(bool editing);

    bool hasPending() const { return !m_pending.isNull(); }
    void clearPending();
    void commitPending(const QString &target);

signals:
    void activated(const QString &target);
    void hovered(const QString &target);
    void hotspotsChanged(const QVector<Hotspot> &hotspots);
    void pendingChanged();
    void chooseImage();
    void imageDropped(const QString &file);

protected:
    void paintEvent(QPaintEvent *) override;
    void resizeEvent(QResizeEvent *) override;
    void mousePressEvent(QMouseEvent *) override;
    void mouseMoveEvent(QMouseEvent *) override;
    void mouseReleaseEvent(QMouseEvent *) override;
    void leaveEvent(QEvent *) override;
    void dragEnterEvent(QDragEnterEvent *) override;
    void dragLeaveEvent(QDragLeaveEvent *) override;
    void dropEvent(QDropEvent *) override;

private:
    QRect imageRect() const;
    QRect emptyRect() const;
    QRectF toWidget(const QRectF &frac) const;
    QPointF toFrac(const QPointF &p) const;
    int hotspotAt(const QPointF &p) const;
    int deleteButtonAt(const QPointF &p) const;
    void updateHover(const QPointF &p);

    QImage m_image;
    QPixmap m_scaled;
    QVector<Hotspot> m_hotspots;
    QSet<QString> m_missing;
    bool m_editing = false;
    bool m_dropping = false;
    bool m_mouseInside = false;
    int m_hover = -1;
    int m_pressed = -1;
    bool m_dragging = false;
    QPointF m_dragStart;
    QRectF m_pending;  // fractions; null when nothing is being drawn
};
