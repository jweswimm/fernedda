#pragma once

#include <QColor>
#include <QPointer>
#include <QQuickPaintedItem>
#include <QTimer>
#include <QtQml/qqmlregistration.h>
#include <algorithm>

class Channel;

// Time-series plot of one Signal K path's history. Used both as a tiny
// sparkline (showAxes: false) and as the big interactive chart in the detail
// view (hover for a crosshair readout).
//
// Values are shown as `raw * valueScale + valueOffset`, so QML can plot knots from m/s
// (valueScale: 1.94384) or °C from K (valueOffset: -273.15).
class HistoryPlot : public QQuickPaintedItem {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString path READ path WRITE setPath NOTIFY pathChanged)
    Q_PROPERTY(int windowSeconds READ windowSeconds WRITE setWindowSeconds NOTIFY styleChanged)
    Q_PROPERTY(double valueScale READ valueScale WRITE setValueScale NOTIFY styleChanged)
    Q_PROPERTY(double valueOffset READ valueOffset WRITE setValueOffset NOTIFY styleChanged)
    Q_PROPERTY(bool angle READ angle WRITE setAngle NOTIFY styleChanged)
    Q_PROPERTY(QColor color READ color WRITE setColor NOTIFY styleChanged)
    Q_PROPERTY(QColor gridColor READ gridColor WRITE setGridColor NOTIFY styleChanged)
    Q_PROPERTY(QColor textColor READ textColor WRITE setTextColor NOTIFY styleChanged)
    Q_PROPERTY(QColor surfaceColor READ surfaceColor WRITE setSurfaceColor NOTIFY styleChanged)
    Q_PROPERTY(bool showAxes READ showAxes WRITE setShowAxes NOTIFY styleChanged)
    Q_PROPERTY(double lineWidth READ lineWidth WRITE setLineWidth NOTIFY styleChanged)
    Q_PROPERTY(double fillOpacity READ fillOpacity WRITE setFillOpacity NOTIFY styleChanged)
    Q_PROPERTY(int decimals READ decimals WRITE setDecimals NOTIFY styleChanged)
    Q_PROPERTY(QString unit READ unit WRITE setUnit NOTIFY styleChanged)
    Q_PROPERTY(bool includeZero READ includeZero WRITE setIncludeZero NOTIFY styleChanged)
    Q_PROPERTY(double reveal READ reveal WRITE setReveal NOTIFY styleChanged)
    Q_PROPERTY(bool hovering READ hovering NOTIFY hoverChanged)
    Q_PROPERTY(double minimum READ minimum NOTIFY rangeChanged)
    Q_PROPERTY(double maximum READ maximum NOTIFY rangeChanged)
    Q_PROPERTY(double average READ average NOTIFY rangeChanged)

public:
    explicit HistoryPlot(QQuickItem *parent = nullptr);
    void paint(QPainter *p) override;

    QString path() const { return m_path; }
    void setPath(const QString &p);
    int windowSeconds() const { return m_window; }
    void setWindowSeconds(int s) { set(m_window, std::max(10, s)); }
    double valueScale() const { return m_scale; }
    void setValueScale(double v) { set(m_scale, v); }
    double valueOffset() const { return m_offset; }
    void setValueOffset(double v) { set(m_offset, v); }
    bool angle() const { return m_angle; }
    void setAngle(bool v) { set(m_angle, v); }
    QColor color() const { return m_color; }
    void setColor(const QColor &c) { set(m_color, c); }
    QColor gridColor() const { return m_grid; }
    void setGridColor(const QColor &c) { set(m_grid, c); }
    QColor textColor() const { return m_text; }
    void setTextColor(const QColor &c) { set(m_text, c); }
    QColor surfaceColor() const { return m_surface; }
    void setSurfaceColor(const QColor &c) { set(m_surface, c); }
    bool showAxes() const { return m_axes; }
    void setShowAxes(bool v) { set(m_axes, v); }
    double lineWidth() const { return m_lineWidth; }
    void setLineWidth(double v) { set(m_lineWidth, v); }
    double fillOpacity() const { return m_fillOpacity; }
    void setFillOpacity(double v) { set(m_fillOpacity, v); }
    int decimals() const { return m_decimals; }
    void setDecimals(int v) { set(m_decimals, v); }
    QString unit() const { return m_unit; }
    void setUnit(const QString &v) { set(m_unit, v); }
    bool includeZero() const { return m_includeZero; }
    void setIncludeZero(bool v) { set(m_includeZero, v); }
    double reveal() const { return m_reveal; }
    void setReveal(double v) { set(m_reveal, v); }
    bool hovering() const { return m_hoverX >= 0; }
    double minimum() const { return m_min; }
    double maximum() const { return m_max; }
    double average() const { return m_avg; }

signals:
    void pathChanged();
    void styleChanged();
    void hoverChanged();
    void rangeChanged();

protected:
    void hoverMoveEvent(QHoverEvent *e) override;
    void hoverLeaveEvent(QHoverEvent *e) override;

private:
    template <typename T> void set(T &field, const T &v)
    {
        if (field == v)
            return;
        field = v;
        emit styleChanged();
        update();
    }
    void scheduleUpdate();

    QString m_path;
    QPointer<Channel> m_channel;
    QMetaObject::Connection m_conn;
    QTimer m_throttle;

    int m_window = 600;
    double m_scale = 1, m_offset = 0;
    bool m_angle = false;
    QColor m_color{"#4fd1c5"}, m_grid{"#22ffffff"}, m_text{"#99ffffff"}, m_surface{"#101a2b"};
    bool m_axes = true;
    double m_lineWidth = 2;
    double m_fillOpacity = 0.35;
    int m_decimals = 1;
    QString m_unit;
    bool m_includeZero = false;
    double m_reveal = 1;
    double m_hoverX = -1;
    double m_min = qQNaN(), m_max = qQNaN(), m_avg = qQNaN();
};
