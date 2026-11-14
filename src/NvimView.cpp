#include "NvimView.h"

#include "NvimLink.h"

#include <QFontMetricsF>
#include <QKeyEvent>
#include <QPainter>
#include <QPainterPath>
#include <QtMath>

namespace {

QString namedKey(int key)
{
    switch (key) {
    case Qt::Key_Escape: return "Esc";
    case Qt::Key_Return: case Qt::Key_Enter: return "CR";
    case Qt::Key_Tab: case Qt::Key_Backtab: return "Tab";
    case Qt::Key_Backspace: return "BS";
    case Qt::Key_Delete: return "Del";
    case Qt::Key_Insert: return "Insert";
    case Qt::Key_Home: return "Home";
    case Qt::Key_End: return "End";
    case Qt::Key_PageUp: return "PageUp";
    case Qt::Key_PageDown: return "PageDown";
    case Qt::Key_Up: return "Up";
    case Qt::Key_Down: return "Down";
    case Qt::Key_Left: return "Left";
    case Qt::Key_Right: return "Right";
    case Qt::Key_Space: return "Space";
    }
    if (key >= Qt::Key_F1 && key <= Qt::Key_F35)
        return "F" + QString::number(key - Qt::Key_F1 + 1);
    return {};
}

// A key event in Neovim's notation: "a", "<lt>", "<C-w>", "<S-Tab>"…
QString vimKey(const QKeyEvent *e)
{
    const Qt::KeyboardModifiers mods = e->modifiers();
    QString prefix;
    if (mods & Qt::ControlModifier) prefix += "C-";
    if (mods & Qt::AltModifier) prefix += "A-";
    if (mods & Qt::MetaModifier) prefix += "D-";

    const int key = e->key();
    const QString name = namedKey(key);
    if (!name.isEmpty()) {
        const bool shift = (mods & Qt::ShiftModifier) || key == Qt::Key_Backtab;
        if (name == "Space" && prefix.isEmpty() && !shift)
            return " ";
        return "<" + prefix + (shift ? "S-" : "") + name + ">";
    }

    if (prefix.isEmpty()) {
        QString text = e->text();
        return text.replace('<', "<lt>");
    }

    // With Ctrl the text is a control character, so go by the key instead.
    if (key >= Qt::Key_A && key <= Qt::Key_Z) {
        const QChar letter = QChar(key).toLower();
        if (mods & Qt::ControlModifier)
            return "<" + prefix + ((mods & Qt::ShiftModifier) ? "S-" : "") + letter + ">";
        return "<" + prefix + ((mods & Qt::ShiftModifier) ? letter.toUpper() : letter) + ">";
    }
    if (key == '<') return "<" + prefix + "lt>";
    if (key == '\\') return "<" + prefix + "Bslash>";
    if (key == '|') return "<" + prefix + "Bar>";
    if (key > 0x20 && key < 0x110000 && QChar::isPrint(char32_t(key)))
        return "<" + prefix + QString::fromUcs4(reinterpret_cast<const char32_t *>(&key), 1) + ">";
    return {};                    // a modifier on its own
}

QString mouseMods(Qt::KeyboardModifiers mods)
{
    QString out;
    if (mods & Qt::ShiftModifier) out += "S";
    if (mods & Qt::ControlModifier) out += "C";
    if (mods & Qt::AltModifier) out += "A";
    return out;
}

} // namespace

NvimView::NvimView(QQuickItem *parent) : QQuickPaintedItem(parent)
{
    setAcceptedMouseButtons(Qt::LeftButton | Qt::MiddleButton | Qt::RightButton);
    // Not opaque, with no fill of its own: the parent shows `background`, and
    // anything placed under this item (touch buttons) shows through around the
    // text. (Opaque painting with a transparent fill draws black on a GPU.)
    setOpaquePainting(false);
    setFillColor(Qt::transparent);

    m_resize.setSingleShot(true);
    m_resize.setInterval(40);     // resizes come in bursts while dragging
    connect(&m_resize, &QTimer::timeout, this, &NvimView::sendSize);

    m_font.setFamily("monospace");
    m_font.setPixelSize(14);
    updateMetrics();

    NvimLink *link = NvimLink::instance();
    connect(link, &NvimLink::redraw, this, &NvimView::onRedraw);
    connect(link, &NvimLink::runningChanged, this, &NvimView::onRunning);
    connect(link, &NvimLink::transparentChanged, this, [this](bool transparent) {
        m_transparent = transparent;
        updateBackground();
    });
}

void NvimView::setFont(const QFont &font)
{
    if (font == m_font)
        return;
    m_font = font;
    updateMetrics();
    m_resize.start();
    update();
    emit fontChanged();
}

void NvimView::setLineSpacing(int px)
{
    px = qMax(0, px);
    if (px == m_lineSpacing)
        return;
    m_lineSpacing = px;
    updateMetrics();
    m_resize.start();
    update();
    emit fontChanged();
}

void NvimView::setHostBackground(const QColor &color)
{
    if (color == m_hostBg)
        return;
    m_hostBg = color;
    updateBackground();
}

void NvimView::updateBackground()
{
    const QColor color = m_transparent ? m_hostBg : m_nvimBg;
    if (color == m_bg)
        return;
    m_bg = color;
    update();
    emit backgroundChanged();
}

void NvimView::updateMetrics()
{
    m_font.setStyleHint(QFont::Monospace);
    m_font.setKerning(false);
    m_body = makeMetrics(m_font, m_lineSpacing);
    QFont foot = m_font;
    if (m_footerPx > 0)
        foot.setPixelSize(m_footerPx);
    m_foot = m_footerPx > 0 ? makeMetrics(foot, 0) : m_body;
}

NvimView::Metrics NvimView::makeMetrics(QFont font, int spacing)
{
    Metrics m;
    for (int i = 0; i < 4; ++i) {
        m.fonts[i] = font;
        m.fonts[i].setBold(i & 1);
        m.fonts[i].setItalic(i & 2);
    }
    const QFontMetricsF fm(font);
    m.cellW = fm.horizontalAdvance(QLatin1Char('M'));
    m.cellH = qCeil(fm.height()) + spacing;
    m.baseline = qRound((m.cellH - fm.height()) / 2 + fm.ascent());
    return m;
}

void NvimView::setFooterRows(int rows)
{
    rows = qMax(0, rows);
    if (rows == m_footerRows)
        return;
    m_footerRows = rows;
    m_resize.start();
    update();
    emit fontChanged();
}

void NvimView::setFooterPixelSize(int px)
{
    px = qMax(0, px);
    if (px == m_footerPx)
        return;
    m_footerPx = px;
    updateMetrics();
    m_resize.start();
    update();
    emit fontChanged();
}

// Body rows from the top, then the footer rows below them.
qreal NvimView::rowY(int row) const
{
    const int body = m_rows - footerCount();
    return row <= body ? row * m_body.cellH : body * m_body.cellH + (row - body) * m_foot.cellH;
}

int NvimView::rowAt(qreal y) const
{
    const int body = m_rows - footerCount();
    const int row = y < body * m_body.cellH ? int(y / m_body.cellH)
                                            : body + int((y - body * m_body.cellH) / m_foot.cellH);
    return qBound(0, row, qMax(0, m_rows - 1));
}

QRectF NvimView::cellsRect(int row, int col, int count) const
{
    const Metrics &m = metricsOf(row);
    return QRectF(col * m.cellW, rowY(row), count * m.cellW, m.cellH);
}

void NvimView::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickPaintedItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.size() != oldGeometry.size())
        m_resize.start();
}

void NvimView::sendSize()
{
    const int cols = qMax(1, int(width() / m_body.cellW));
    const int foot = m_footerRows;
    const int rows = qMax(1, foot + int((height() - foot * m_foot.cellH) / m_body.cellH));
    NvimLink::instance()->resizeUi(cols, rows);
}

void NvimView::onRunning()
{
    if (NvimLink::instance()->running()) {
        sendSize();
        return;
    }
    m_cols = m_rows = 0;
    m_cells.clear();
    m_attrs.clear();
    m_modes.clear();
    m_busy = false;
    update();
}

// ---- the redraw protocol ---------------------------------------------------

void NvimView::onRedraw(const QVariantList &events)
{
    for (const QVariant &event : events) {
        const QVariantList batch = event.toList();
        const QString name = batch.value(0).toString();

        if (name == "flush") { update(); continue; }
        if (name == "busy_start") { m_busy = true; continue; }
        if (name == "busy_stop") { m_busy = false; continue; }

        // Every other event repeats its arguments once per call in the batch.
        for (qsizetype i = 1; i < batch.size(); ++i) {
            const QVariantList args = batch.at(i).toList();
            if (name == "grid_line") {
                gridLine(args);
            } else if (name == "grid_cursor_goto") {
                m_curRow = args.value(1).toInt();
                m_curCol = args.value(2).toInt();
            } else if (name == "grid_scroll") {
                gridScroll(args.value(1).toInt(), args.value(2).toInt(), args.value(5).toInt());
            } else if (name == "grid_clear") {
                m_cells.fill(Cell{});
            } else if (name == "grid_resize") {
                gridResize(args.value(1).toInt(), args.value(2).toInt());
            } else if (name == "hl_attr_define") {
                defineAttr(args.value(0).toInt(), args.value(1).toMap());
            } else if (name == "default_colors_set") {
                m_fg = QColor::fromRgb(QRgb(args.value(0).toInt()));
                m_nvimBg = QColor::fromRgb(QRgb(args.value(1).toInt()));
                m_sp = QColor::fromRgb(QRgb(args.value(2).toInt()));
                updateBackground();
            } else if (name == "mode_info_set") {
                setModes(args.value(1).toList());
            } else if (name == "mode_change") {
                m_mode = args.value(1).toInt();
            }
        }
    }
}

void NvimView::gridResize(int cols, int rows)
{
    m_cols = cols;
    m_rows = rows;
    m_cells = QVector<Cell>(cols * rows);
}

void NvimView::gridLine(const QVariantList &args)
{
    const int row = args.value(1).toInt();
    int col = args.value(2).toInt();
    if (row < 0 || row >= m_rows)
        return;
    int hl = 0;                   // a cell without an id keeps the previous one
    const QVariantList cells = args.value(3).toList();
    for (const QVariant &v : cells) {
        const QVariantList c = v.toList();
        const QString text = c.value(0).toString();
        if (c.size() > 1) hl = c.at(1).toInt();
        const int repeat = c.size() > 2 ? c.at(2).toInt() : 1;
        for (int i = 0; i < repeat && col < m_cols; ++i, ++col) {
            Cell &target = cell(row, col);
            target.text = text;
            target.hl = hl;
        }
    }
}

// Positive rows: the region moves up (nvim then fills what's uncovered).
void NvimView::gridScroll(int top, int bottom, int rows)
{
    if (rows > 0) {
        for (int r = top; r + rows < bottom; ++r)
            std::copy_n(m_cells.constBegin() + (r + rows) * m_cols, m_cols, m_cells.begin() + r * m_cols);
    } else if (rows < 0) {
        for (int r = bottom - 1; r + rows >= top; --r)
            std::copy_n(m_cells.constBegin() + (r + rows) * m_cols, m_cols, m_cells.begin() + r * m_cols);
    }
}

void NvimView::defineAttr(int id, const QVariantMap &map)
{
    if (id < 0)
        return;
    if (id >= m_attrs.size())
        m_attrs.resize(id + 1);
    Attr a;
    a.fg = map.value("foreground", -1).toInt();
    a.bg = map.value("background", -1).toInt();
    a.sp = map.value("special", -1).toInt();
    a.reverse = map.value("reverse").toBool();
    a.bold = map.value("bold").toBool();
    a.italic = map.value("italic").toBool();
    a.strike = map.value("strikethrough").toBool();
    if (map.value("undercurl").toBool()) a.underline = Curl;
    else if (map.value("underdouble").toBool()) a.underline = Double;
    else if (map.value("underdotted").toBool()) a.underline = Dotted;
    else if (map.value("underdashed").toBool()) a.underline = Dashed;
    else if (map.value("underline").toBool()) a.underline = Single;
    m_attrs[id] = a;
}

void NvimView::setModes(const QVariantList &modes)
{
    m_modes.clear();
    for (const QVariant &v : modes) {
        const QVariantMap map = v.toMap();
        CursorMode mode;
        const QString shape = map.value("cursor_shape").toString();
        mode.shape = shape == "horizontal" ? CursorMode::Horizontal
                   : shape == "vertical" ? CursorMode::Vertical : CursorMode::Block;
        mode.percent = map.value("cell_percentage", 100).toInt();
        mode.attr = map.value("attr_id").toInt();
        m_modes.append(mode);
    }
}

// ---- painting --------------------------------------------------------------

const NvimView::Attr &NvimView::attr(int id) const
{
    static const Attr plain;
    return id > 0 && id < m_attrs.size() ? m_attrs.at(id) : plain;
}

QColor NvimView::fgOf(const Attr &a) const
{
    const int c = a.reverse ? a.bg : a.fg;
    return c >= 0 ? QColor::fromRgb(QRgb(c)) : a.reverse ? m_bg : m_fg;
}

QColor NvimView::bgOf(const Attr &a) const
{
    const int c = a.reverse ? a.fg : a.bg;
    return c >= 0 ? QColor::fromRgb(QRgb(c)) : a.reverse ? m_fg : m_bg;
}

QColor NvimView::spOf(const Attr &a) const
{
    if (a.sp >= 0)
        return QColor::fromRgb(QRgb(a.sp));
    return fgOf(a);
}

void NvimView::paintLine(QPainter *p, const Metrics &m, const Attr &a, qreal x, qreal y, qreal w)
{
    if (a.strike) {
        p->setPen(fgOf(a));
        p->drawLine(QPointF(x, y + m.cellH / 2), QPointF(x + w, y + m.cellH / 2));
    }
    if (a.underline == NoLine)
        return;
    const qreal ly = y + m.baseline + 1.5;
    QPen pen(spOf(a));
    switch (a.underline) {
    case Curl: {
        QPainterPath path(QPointF(x, ly + 1));
        path.lineTo(x + w / 4, ly - 1);
        path.lineTo(x + w * 3 / 4, ly + 2);
        path.lineTo(x + w, ly);
        p->save();
        p->setRenderHint(QPainter::Antialiasing);
        p->setPen(pen);
        p->drawPath(path);
        p->restore();
        return;
    }
    case Double:
        p->setPen(pen);
        p->drawLine(QPointF(x, ly + 2), QPointF(x + w, ly + 2));
        break;
    case Dotted: pen.setStyle(Qt::DotLine); p->setPen(pen); break;
    case Dashed: pen.setStyle(Qt::DashLine); p->setPen(pen); break;
    default: p->setPen(pen);
    }
    p->drawLine(QPointF(x, ly), QPointF(x + w, ly));
}

void NvimView::paint(QPainter *p)
{
    if (m_cells.isEmpty())
        return;

    // Backgrounds first, so a glyph overhanging its cell isn't cut off by the next.
    for (int r = 0; r < m_rows; ++r) {
        const Metrics &m = metricsOf(r);
        const qreal y = rowY(r);
        for (int c = 0; c < m_cols;) {
            const QColor bg = bgOf(attr(cell(r, c).hl));
            int end = c + 1;
            while (end < m_cols && bgOf(attr(cell(r, end).hl)) == bg)
                ++end;
            // A smaller footer row doesn't reach the right edge; its last colour does.
            const qreal right = end == m_cols ? width() : end * m.cellW;
            if (bg != m_bg)
                p->fillRect(QRectF(c * m.cellW, y, right - c * m.cellW, m.cellH), bg);
            c = end;
        }
    }

    for (int r = 0; r < m_rows; ++r) {
        const Metrics &m = metricsOf(r);
        const qreal y = rowY(r);
        for (int c = 0; c < m_cols;) {
            const Cell &first = cell(r, c);
            const Attr &a = attr(first.hl);
            if (a.underline != NoLine || a.strike)
                paintLine(p, m, a, c * m.cellW, y, m.cellW);
            if (first.text.isEmpty() || first.text == QLatin1String(" ")) {
                ++c;
                continue;
            }
            // Plain ASCII draws in runs. Anything else draws alone, on its cell:
            // it may come from a fallback font with different widths.
            QString run = first.text;
            int end = c + 1;
            const auto ascii = [](const QString &s) { return s.size() == 1 && s.at(0).unicode() < 0x7f; };
            if (ascii(run)) {
                while (end < m_cols) {
                    const Cell &next = cell(r, end);
                    if (next.hl != first.hl || !ascii(next.text) || next.text == QLatin1String(" "))
                        break;
                    if (a.underline != NoLine || a.strike)
                        paintLine(p, m, a, end * m.cellW, y, m.cellW);
                    run += next.text;
                    ++end;
                }
            }
            p->setFont(m.of(a));
            p->setPen(fgOf(a));
            p->drawText(QPointF(c * m.cellW, y + m.baseline), run);
            c = end;
        }
    }
    paintCursor(p);
}

void NvimView::paintCursor(QPainter *p)
{
    if (m_busy || m_curRow < 0 || m_curRow >= m_rows || m_curCol < 0 || m_curCol >= m_cols)
        return;
    const Cell &under = cell(m_curRow, m_curCol);
    const Attr &cellAttr = attr(under.hl);
    const CursorMode mode = m_mode >= 0 && m_mode < m_modes.size() ? m_modes.at(m_mode) : CursorMode{};

    // With no cursor highlight, a cursor inverts the cell's own colours.
    QColor fill = fgOf(cellAttr), text = bgOf(cellAttr);
    if (mode.attr > 0) {
        const Attr &a = attr(mode.attr);
        if (a.fg >= 0 || a.bg >= 0 || a.reverse) {
            fill = bgOf(a);
            text = fgOf(a);
        }
    }

    const bool wide = m_curCol + 1 < m_cols && cell(m_curRow, m_curCol + 1).text.isEmpty();
    const Metrics &m = metricsOf(m_curRow);
    const QRectF box = cellsRect(m_curRow, m_curCol, wide ? 2 : 1);

    if (!hasActiveFocus()) {
        p->setPen(fill);
        p->setBrush(Qt::NoBrush);
        p->drawRect(box.adjusted(0.5, 0.5, -0.5, -0.5));
        return;
    }
    const qreal share = qBound(1, mode.percent, 100) / 100.0;
    switch (mode.shape) {
    case CursorMode::Horizontal:
        p->fillRect(QRectF(box.left(), box.bottom() - qMax(1.0, box.height() * share), box.width(), qMax(1.0, box.height() * share)), fill);
        break;
    case CursorMode::Vertical:
        p->fillRect(QRectF(box.left(), box.top(), qMax(1.0, box.width() * share), box.height()), fill);
        break;
    case CursorMode::Block:
        p->fillRect(box, fill);
        p->setFont(m.of(cellAttr));
        p->setPen(text);
        p->drawText(QPointF(box.left(), box.top() + m.baseline), under.text);
        break;
    }
}

// ---- input -----------------------------------------------------------------

void NvimView::keyPressEvent(QKeyEvent *event)
{
    const QString keys = vimKey(event);
    if (keys.isEmpty()) {
        event->ignore();
        return;
    }
    NvimLink::instance()->input(keys);
    event->accept();
}

void NvimView::mouse(QMouseEvent *event, const QString &action)
{
    const int row = rowAt(event->position().y());
    const int col = qBound(0, int(event->position().x() / metricsOf(row).cellW), qMax(0, m_cols - 1));
    if (action == QLatin1String("drag") && row == m_dragRow && col == m_dragCol)
        return;                   // still in the same cell
    m_dragRow = row;
    m_dragCol = col;
    NvimLink::instance()->inputMouse(m_dragButton, action, mouseMods(event->modifiers()), row, col);
}

void NvimView::mousePressEvent(QMouseEvent *event)
{
    forceActiveFocus(Qt::MouseFocusReason);
    m_dragButton = event->button() == Qt::RightButton ? "right"
                 : event->button() == Qt::MiddleButton ? "middle" : "left";
    mouse(event, "press");
    event->accept();
}

void NvimView::mouseMoveEvent(QMouseEvent *event) { mouse(event, "drag"); }
void NvimView::mouseReleaseEvent(QMouseEvent *event) { mouse(event, "release"); }

void NvimView::wheelEvent(QWheelEvent *event)
{
    const int dy = event->angleDelta().y();
    if (dy == 0) {
        event->ignore();
        return;
    }
    const int row = rowAt(event->position().y());
    const int col = qBound(0, int(event->position().x() / metricsOf(row).cellW), qMax(0, m_cols - 1));
    NvimLink::instance()->inputMouse("wheel", dy > 0 ? "up" : "down", mouseMods(event->modifiers()), row, col);
    event->accept();
}

void NvimView::focusInEvent(QFocusEvent *event)
{
    QQuickPaintedItem::focusInEvent(event);
    NvimLink::instance()->setUiFocus(true);
    update();                     // the cursor goes solid
}

void NvimView::focusOutEvent(QFocusEvent *event)
{
    QQuickPaintedItem::focusOutEvent(event);
    NvimLink::instance()->setUiFocus(false);
    update();                     // the cursor goes hollow
}
