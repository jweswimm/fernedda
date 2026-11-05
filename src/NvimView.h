#pragma once

#include <QColor>
#include <QFont>
#include <QQuickPaintedItem>
#include <QTimer>
#include <QVector>
#include <QtQml/qqmlregistration.h>

// Draws the embedded Neovim's screen and sends it keys and mouse input. Neovim
// describes its screen as a grid of cells (the "linegrid" UI protocol); floats
// and the command line arrive already composited into that one grid.
class NvimView : public QQuickPaintedItem {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QFont font READ font WRITE setFont NOTIFY fontChanged)
    // The background when Neovim doesn't set one (e.g. a "transparent" colorscheme),
    // as a terminal's own background would be.
    Q_PROPERTY(QColor hostBackground READ hostBackground WRITE setHostBackground NOTIFY backgroundChanged)
    Q_PROPERTY(QColor background READ background NOTIFY backgroundChanged)

public:
    explicit NvimView(QQuickItem *parent = nullptr);

    QFont font() const { return m_font; }
    void setFont(const QFont &font);
    QColor hostBackground() const { return m_hostBg; }
    void setHostBackground(const QColor &color);
    QColor background() const { return m_bg; }

    void paint(QPainter *painter) override;

signals:
    void fontChanged();
    void backgroundChanged();

protected:
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;
    void keyPressEvent(QKeyEvent *event) override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void wheelEvent(QWheelEvent *event) override;
    void focusInEvent(QFocusEvent *event) override;
    void focusOutEvent(QFocusEvent *event) override;

private:
    struct Cell {
        QString text = QStringLiteral(" ");
        int hl = 0;
    };
    enum Underline { NoLine, Single, Double, Curl, Dotted, Dashed };
    struct Attr {
        int fg = -1, bg = -1, sp = -1;   // 0xRRGGBB, or -1 for the default
        bool reverse = false, bold = false, italic = false, strike = false;
        Underline underline = NoLine;
    };
    struct CursorMode {
        enum Shape { Block, Horizontal, Vertical } shape = Block;
        int percent = 100;
        int attr = 0;
    };

    void onRedraw(const QVariantList &events);
    void onRunning();
    void gridResize(int cols, int rows);
    void gridLine(const QVariantList &args);
    void gridScroll(int top, int bottom, int rows);
    void defineAttr(int id, const QVariantMap &map);
    void setModes(const QVariantList &modes);
    void updateMetrics();
    void sendSize();
    void updateBackground();

    Cell &cell(int row, int col) { return m_cells[row * m_cols + col]; }
    const Attr &attr(int id) const;
    QColor fgOf(const Attr &a) const;
    QColor bgOf(const Attr &a) const;
    QColor spOf(const Attr &a) const;
    const QFont &fontOf(const Attr &a) const { return m_fonts[(a.bold ? 1 : 0) + (a.italic ? 2 : 0)]; }
    void paintLine(QPainter *p, const Attr &a, qreal x, qreal y, qreal w);
    void paintCursor(QPainter *p);
    void mouse(QMouseEvent *event, const QString &action);

    QFont m_font;
    QFont m_fonts[4];              // regular, bold, italic, bold italic
    qreal m_cellW = 8, m_cellH = 16, m_baseline = 12;
    QTimer m_resize;

    int m_cols = 0, m_rows = 0;
    QVector<Cell> m_cells;
    QVector<Attr> m_attrs;
    QColor m_fg = Qt::white, m_bg = Qt::black, m_sp = Qt::red;
    QColor m_nvimBg = Qt::black, m_hostBg = Qt::black;
    bool m_transparent = false;

    QVector<CursorMode> m_modes;
    int m_mode = 0;
    int m_curRow = 0, m_curCol = 0;
    bool m_busy = false;

    QString m_dragButton;
    int m_dragRow = -1, m_dragCol = -1;
};
