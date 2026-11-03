#include "HistoryPlot.h"
#include "SignalKStore.h"

#include <QDateTime>
#include <QFontMetricsF>
#include <QGuiApplication>
#include <QLinearGradient>
#include <QPainter>
#include <QPainterPath>
#include <algorithm>
#include <cmath>
#include <limits>

namespace {
// A "nice" step (1, 2, 2.5, 5 × 10^n) giving roughly `target` intervals.
double niceStep(double span, int target)
{
    if (span <= 0)
        return 1;
    const double raw = span / target;
    const double mag = std::pow(10, std::floor(std::log10(raw)));
    const double norm = raw / mag;
    double nice = 10;
    if (norm <= 1) nice = 1;
    else if (norm <= 2) nice = 2;
    else if (norm <= 2.5) nice = 2.5;
    else if (norm <= 5) nice = 5;
    return nice * mag;
}

QString timeLabel(int secondsAgo)
{
    if (secondsAgo == 0)
        return QStringLiteral("now");
    if (secondsAgo % 3600 == 0)
        return QStringLiteral("-%1h").arg(secondsAgo / 3600);
    if (secondsAgo >= 60)
        return QStringLiteral("-%1m").arg(secondsAgo / 60);
    return QStringLiteral("-%1s").arg(secondsAgo);
}

struct Pt {
    qint64 t;
    double v;
};
} // namespace

HistoryPlot::HistoryPlot(QQuickItem *parent) : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
    setAcceptHoverEvents(true);
    m_throttle.setSingleShot(true);
    m_throttle.setInterval(250);
    connect(&m_throttle, &QTimer::timeout, this, [this] { update(); });
    // Scroll with time even if the value doesn't change.
    connect(SignalKStore::instance(), &SignalKStore::tick, this, &HistoryPlot::scheduleUpdate);
}

void HistoryPlot::setPath(const QString &p)
{
    if (p == m_path)
        return;
    m_path = p;
    disconnect(m_conn);
    m_channel = p.isEmpty() ? nullptr : SignalKStore::instance()->channel(p);
    if (m_channel)
        m_conn = connect(m_channel, &Channel::changed, this, &HistoryPlot::scheduleUpdate);
    emit pathChanged();
    update();
}

void HistoryPlot::scheduleUpdate()
{
    if (!m_throttle.isActive())
        m_throttle.start();
}

void HistoryPlot::hoverMoveEvent(QHoverEvent *e)
{
    const bool was = hovering();
    m_hoverX = e->position().x();
    if (!was)
        emit hoverChanged();
    update();
}

void HistoryPlot::hoverLeaveEvent(QHoverEvent *)
{
    m_hoverX = -1;
    emit hoverChanged();
    update();
}

void HistoryPlot::paint(QPainter *p)
{
    p->setRenderHint(QPainter::Antialiasing);
    const double W = width(), H = height();
    if (W < 4 || H < 4)
        return;

    QFont font = QGuiApplication::font();
    font.setPixelSize(11);
    p->setFont(font);
    const QFontMetricsF fm(font);

    const double leftPad = m_axes ? 44 : 1;
    const double rightPad = m_axes ? 12 : 1;
    const double topPad = m_axes ? 10 : 2;
    const double bottomPad = m_axes ? 22 : 2;
    const QRectF plot(leftPad, topPad, W - leftPad - rightPad, H - topPad - bottomPad);
    if (plot.width() < 4 || plot.height() < 4)
        return;

    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    const qint64 t0 = now - qint64(m_window) * 1000;

    // Gather visible samples, bucketed to about one point per two pixels.
    QVector<Pt> pts;
    if (m_channel) {
        const auto &h = m_channel->history();
        auto first = std::lower_bound(h.begin(), h.end(), t0,
                                      [](const Sample &s, qint64 t) { return s.t < t; });
        if (first != h.begin())
            --first; // one sample before the window so the line reaches the edge
        const int buckets = std::max(2, int(plot.width() / 2));
        const double bucketMs = double(now - t0) / buckets;
        int curBucket = -1;
        double sum = 0;
        int n = 0;
        qint64 tsum = 0;
        auto flush = [&] {
            if (n) pts.append({tsum / n, sum / n});
            sum = 0; n = 0; tsum = 0;
        };
        for (auto it = first; it != h.end(); ++it) {
            double v = it->v * m_scale + m_offset;
            if (m_angle) {
                v = std::fmod(v, 360.0);
                if (v < 0) v += 360;
            }
            const int b = int((it->t - t0) / bucketMs);
            // Angles don't average across the 0/360 seam; keep raw points for them.
            if (b != curBucket || m_angle) {
                flush();
                curBucket = b;
            }
            sum += v; tsum += it->t; ++n;
        }
        flush();
    }

    // Y range
    double lo = std::numeric_limits<double>::max(), hi = std::numeric_limits<double>::lowest();
    double total = 0;
    int counted = 0;
    for (const Pt &pt : pts) {
        if (pt.t < t0) continue;
        lo = std::min(lo, pt.v);
        hi = std::max(hi, pt.v);
        total += pt.v;
        ++counted;
    }
    if (!counted) {
        lo = 0; hi = 1;
    }
    const double nan = qQNaN();
    const double newMin = counted ? lo : nan, newMax = counted ? hi : nan, newAvg = counted ? total / counted : nan;
    auto differs = [](double a, double b) { return std::isnan(a) != std::isnan(b) || (!std::isnan(a) && a != b); };
    if (differs(newMin, m_min) || differs(newMax, m_max) || differs(newAvg, m_avg)) {
        m_min = newMin; m_max = newMax; m_avg = newAvg;
        QMetaObject::invokeMethod(this, &HistoryPlot::rangeChanged, Qt::QueuedConnection);
    }
    if (m_angle) {
        lo = 0; hi = 360;
    } else {
        if (m_includeZero) {
            lo = std::min(lo, 0.0);
            hi = std::max(hi, 0.0);
        }
        double span = hi - lo;
        if (span < 1e-9) {
            span = std::max(std::abs(hi) * 0.1, 1.0);
            lo -= span / 2;
            hi += span / 2;
        }
        const double pad = span * 0.12;
        if (!(m_includeZero && lo == 0)) lo -= pad;
        hi += pad;
    }
    const double step = m_angle ? 90 : niceStep(hi - lo, 4);
    if (!m_angle && m_axes) {
        lo = std::floor(lo / step) * step;
        hi = std::ceil(hi / step) * step;
    }

    auto X = [&](qint64 t) { return plot.left() + plot.width() * double(t - t0) / double(now - t0); };
    auto Y = [&](double v) { return plot.bottom() - plot.height() * (v - lo) / (hi - lo); };

    // Grid + labels
    if (m_axes) {
        QPen gridPen(m_grid, 1, Qt::DashLine);
        gridPen.setDashPattern({2, 4});
        p->setPen(gridPen);
        for (double v = lo; v <= hi + step * 0.01; v += step) {
            const double y = std::round(Y(v)) + 0.5;
            p->setPen(gridPen);
            p->drawLine(QPointF(plot.left(), y), QPointF(plot.right(), y));
            p->setPen(m_text);
            const QString label = QString::number(v, 'f', step < 1 ? (step < 0.1 ? 2 : 1) : 0);
            p->drawText(QRectF(0, y - 8, leftPad - 8, 16), Qt::AlignRight | Qt::AlignVCenter, label);
        }
        // Time ticks
        const int tickSteps[] = {10, 30, 60, 120, 300, 600, 900, 1800, 3600, 7200};
        int tick = tickSteps[0];
        for (int s : tickSteps) {
            tick = s;
            if (m_window / s <= 6) break;
        }
        p->setPen(m_text);
        for (int s = 0; s <= m_window; s += tick) {
            const double x = X(now - qint64(s) * 1000);
            const QString label = timeLabel(s);
            const double w = fm.horizontalAdvance(label);
            const double lx = std::clamp(x - w / 2, plot.left(), plot.right() - w);
            p->drawText(QPointF(lx, H - 6), label);
        }
    }

    if (pts.size() < 2)
        return;

    // Reveal animation clips from the left.
    p->save();
    p->setClipRect(QRectF(plot.left() - 4, 0, plot.width() * m_reveal + 8, H));
    p->setClipping(true);
    QRectF clipPlot = plot.adjusted(-2, -4, 2, 2);
    p->setClipRect(clipPlot, Qt::IntersectClip);

    // Build the line as one or more segments (angles break at the 0/360 seam).
    QVector<QPainterPath> segments(1);
    QVector<QPointF> segStart(1), segEnd(1);
    bool started = false;
    for (int i = 0; i < pts.size(); ++i) {
        const QPointF pt(X(pts[i].t), Y(pts[i].v));
        if (m_angle && i > 0 && std::abs(pts[i].v - pts[i - 1].v) > 180) {
            segments.append(QPainterPath());
            segStart.append(pt);
            segEnd.append(pt);
            started = false;
        }
        QPainterPath &path = segments.last();
        if (!started) {
            path.moveTo(pt);
            segStart.last() = pt;
            started = true;
        } else {
            path.lineTo(pt);
        }
        segEnd.last() = pt;
    }

    // Area fill under the line
    if (m_fillOpacity > 0) {
        QLinearGradient g(0, plot.top(), 0, plot.bottom());
        QColor c0 = m_color, c1 = m_color;
        c0.setAlphaF(m_fillOpacity);
        c1.setAlphaF(0);
        g.setColorAt(0, c0);
        g.setColorAt(1, c1);
        for (int i = 0; i < segments.size(); ++i) {
            QPainterPath area = segments[i];
            area.lineTo(segEnd[i].x(), plot.bottom());
            area.lineTo(segStart[i].x(), plot.bottom());
            area.closeSubpath();
            p->fillPath(area, g);
        }
    }

    // Glow + line
    QColor glow = m_color;
    glow.setAlphaF(0.18);
    p->setBrush(Qt::NoBrush);
    p->setPen(QPen(glow, m_lineWidth * 3.5, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
    for (const auto &s : segments) p->drawPath(s);
    p->setPen(QPen(m_color, m_lineWidth, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
    for (const auto &s : segments) p->drawPath(s);

    // Latest-value dot
    if (m_reveal >= 1) {
        const QPointF last = segEnd.last();
        QColor halo = m_color;
        halo.setAlphaF(0.25);
        p->setPen(Qt::NoPen);
        p->setBrush(halo);
        p->drawEllipse(last, m_lineWidth * 3, m_lineWidth * 3);
        p->setBrush(m_color);
        p->drawEllipse(last, m_lineWidth * 1.4, m_lineWidth * 1.4);
    }
    p->restore();

    // Hover crosshair
    if (m_hoverX >= plot.left() && m_hoverX <= plot.right() && m_axes) {
        const qint64 ht = t0 + qint64((m_hoverX - plot.left()) / plot.width() * double(now - t0));
        auto it = std::min_element(pts.begin(), pts.end(), [&](const Pt &a, const Pt &b) {
            return std::llabs(a.t - ht) < std::llabs(b.t - ht);
        });
        const QPointF pt(X(it->t), Y(it->v));
        p->setPen(QPen(m_text, 1, Qt::DotLine));
        p->drawLine(QPointF(pt.x(), plot.top()), QPointF(pt.x(), plot.bottom()));
        p->setPen(QPen(m_surface, 2));
        p->setBrush(m_color);
        p->drawEllipse(pt, 5, 5);

        const QString text = QStringLiteral("%1 %2  ·  %3")
                                 .arg(QString::number(it->v, 'f', m_decimals), m_unit,
                                      QDateTime::fromMSecsSinceEpoch(it->t).toString("HH:mm:ss"));
        QFont bold = font;
        bold.setPixelSize(12);
        bold.setBold(true);
        const QFontMetricsF bfm(bold);
        const double tw = bfm.horizontalAdvance(text) + 18, th = 26;
        double bx = pt.x() + 12;
        if (bx + tw > W) bx = pt.x() - 12 - tw;
        const double by = std::clamp(pt.y() - th - 8, 0.0, H - th);
        QColor bg = m_surface;
        bg.setAlphaF(0.94);
        p->setPen(QPen(m_color, 1));
        p->setBrush(bg);
        p->drawRoundedRect(QRectF(bx, by, tw, th), 8, 8);
        p->setFont(bold);
        QColor tc = m_text;
        tc.setAlphaF(1);
        p->setPen(tc);
        p->drawText(QRectF(bx, by, tw, th), Qt::AlignCenter, text);
    }
}
