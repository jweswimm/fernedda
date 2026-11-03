import QtQuick
import QtQuick.Shapes

// 240° arc gauge with optional warning/danger thresholds and tick marks.
Item {
    id: g
    property real value: NaN
    property real minimum: 0
    property real maximum: 100
    property real warnAt: NaN
    property real dangerAt: NaN
    property string unit
    property string label
    property int decimals: 0
    property color color: Theme.accent
    property int ticks: 8

    readonly property real sweep: 240
    readonly property real startAngle: 150 // degrees, clockwise from +x
    readonly property real frac: isNaN(value) ? 0 : Math.max(0, Math.min(1, (value - minimum) / (maximum - minimum)))
    property real shownFrac: frac
    Behavior on shownFrac { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }

    readonly property color levelColor: !isNaN(dangerAt) && value >= dangerAt ? Theme.danger
                                      : !isNaN(warnAt) && value >= warnAt ? Theme.warn : color

    readonly property real d: Math.min(width, height / 0.86)
    readonly property real r: d / 2 - 8
    readonly property real cx: width / 2
    readonly property real cy: r + 8

    implicitWidth: 160
    implicitHeight: 140

    function fracOf(v) { return Math.max(0, Math.min(1, (v - minimum) / (maximum - minimum))) }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        // Track
        ShapePath {
            strokeColor: Theme.alpha(Theme.textFaint, 0.35)
            strokeWidth: 10
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: g.cx; centerY: g.cy; radiusX: g.r; radiusY: g.r; startAngle: g.startAngle; sweepAngle: g.sweep }
        }
        // Danger zone hint on the track
        ShapePath {
            strokeColor: Theme.alpha(Theme.danger, isNaN(g.dangerAt) ? 0 : 0.35)
            strokeWidth: 10
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            PathAngleArc {
                centerX: g.cx; centerY: g.cy; radiusX: g.r; radiusY: g.r
                startAngle: g.startAngle + g.sweep * (isNaN(g.dangerAt) ? 1 : g.fracOf(g.dangerAt))
                sweepAngle: g.sweep * (isNaN(g.dangerAt) ? 0 : 1 - g.fracOf(g.dangerAt))
            }
        }
        // Glow under the value arc
        ShapePath {
            strokeColor: Theme.alpha(g.levelColor, 0.18)
            strokeWidth: 20
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: g.cx; centerY: g.cy; radiusX: g.r; radiusY: g.r; startAngle: g.startAngle; sweepAngle: Math.max(0.01, g.sweep * g.shownFrac) }
        }
        ShapePath {
            strokeColor: g.levelColor
            strokeWidth: 10
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: g.cx; centerY: g.cy; radiusX: g.r; radiusY: g.r; startAngle: g.startAngle; sweepAngle: Math.max(0.01, g.sweep * g.shownFrac) }
        }
    }

    // Ticks
    Repeater {
        model: g.ticks + 1
        Rectangle {
            required property int index
            readonly property real a: (g.startAngle + g.sweep * index / g.ticks) * Math.PI / 180
            width: 2; height: 6; radius: 1
            color: Theme.textFaint
            x: g.cx + Math.cos(a) * (g.r - 16) - width / 2
            y: g.cy + Math.sin(a) * (g.r - 16) - height / 2
            rotation: g.startAngle + g.sweep * index / g.ticks + 90
        }
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: g.cy - height / 2 + 4
        spacing: -2
        AnimatedNumber {
            anchors.horizontalCenter: parent.horizontalCenter
            value: g.value
            decimals: g.decimals
            font.pixelSize: Math.max(18, g.r * 0.46)
            font.weight: Font.Light
            color: g.levelColor === g.color ? Theme.text : g.levelColor
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: g.unit
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(10, g.r * 0.16)
        }
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: g.cy + g.r * 0.62
        text: g.label
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: 12
    }
}
