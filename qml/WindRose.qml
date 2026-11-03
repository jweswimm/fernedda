import QtQuick
import QtQuick.Shapes

// Boat-relative wind instrument. Bow is up; apparent wind is the solid
// pointer, true wind the hollow one. Red/green arcs mark the close-hauled
// zone on port/starboard.
Item {
    id: rose
    property real awa: NaN   // degrees, -180..180, + = starboard
    property real twa: NaN
    property real aws: NaN   // knots
    property real tws: NaN
    property real heading: NaN // degrees true, shown on top

    readonly property real s: Math.min(width, height)
    readonly property real r: s / 2 - 6
    readonly property real cx: width / 2
    readonly property real cy: height / 2

    Canvas {
        id: dial
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative
        property color faint: Theme.textFaint
        property color dim: Theme.textDim
        property color port: Theme.port
        property color stbd: Theme.starboard
        property color ring: Theme.border
        onFaintChanged: requestPaint()
        onPortChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const cx = rose.cx, cy = rose.cy, r = rose.r
            const rad = d => (d - 90) * Math.PI / 180

            // Faint face
            ctx.beginPath()
            ctx.arc(cx, cy, r, 0, 2 * Math.PI)
            ctx.strokeStyle = ring
            ctx.lineWidth = 1.5
            ctx.stroke()

            // Close-hauled sectors
            ctx.lineWidth = 7
            ctx.lineCap = "butt"
            ctx.strokeStyle = Qt.rgba(stbd.r, stbd.g, stbd.b, 0.75)
            ctx.beginPath(); ctx.arc(cx, cy, r - 5, rad(20), rad(60)); ctx.stroke()
            ctx.strokeStyle = Qt.rgba(port.r, port.g, port.b, 0.75)
            ctx.beginPath(); ctx.arc(cx, cy, r - 5, rad(-60), rad(-20)); ctx.stroke()
            // Run sectors, fainter
            ctx.strokeStyle = Qt.rgba(stbd.r, stbd.g, stbd.b, 0.25)
            ctx.beginPath(); ctx.arc(cx, cy, r - 5, rad(120), rad(180)); ctx.stroke()
            ctx.strokeStyle = Qt.rgba(port.r, port.g, port.b, 0.25)
            ctx.beginPath(); ctx.arc(cx, cy, r - 5, rad(180), rad(240)); ctx.stroke()

            // Ticks and labels
            ctx.lineCap = "round"
            ctx.font = Math.round(Math.max(10, r * 0.085)) + "px '" + Theme.fontFamily + "'"
            ctx.textAlign = "center"
            ctx.textBaseline = "middle"
            for (let a = 0; a < 360; a += 5) {
                const major = a % 30 === 0, mid = a % 10 === 0
                const len = major ? 12 : mid ? 7 : 3
                const t = rad(a)
                ctx.strokeStyle = major ? dim : faint
                ctx.lineWidth = major ? 2 : 1
                ctx.beginPath()
                ctx.moveTo(cx + Math.cos(t) * (r - 12), cy + Math.sin(t) * (r - 12))
                ctx.lineTo(cx + Math.cos(t) * (r - 12 - len), cy + Math.sin(t) * (r - 12 - len))
                ctx.stroke()
                if (major && a !== 0) {
                    const lr = r - 12 - len - r * 0.09
                    ctx.fillStyle = dim
                    ctx.fillText(String(a > 180 ? 360 - a : a), cx + Math.cos(t) * lr, cy + Math.sin(t) * lr)
                }
            }
        }
    }

    // Boat silhouette
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        readonly property real hullL: rose.r * 0.62
        readonly property real hullB: rose.r * 0.21
        ShapePath {
            strokeColor: Theme.alpha(Theme.textDim, 0.45)
            strokeWidth: 1.5
            fillColor: Theme.alpha(Theme.textFaint, 0.10)
            startX: rose.cx; startY: rose.cy - parent.hullL * 0.55
            PathCubic {
                x: rose.cx + parent.hullB; y: rose.cy + parent.hullL * 0.38
                control1X: rose.cx + parent.hullB * 0.9; control1Y: rose.cy - parent.hullL * 0.35
                control2X: rose.cx + parent.hullB * 1.05; control2Y: rose.cy + parent.hullL * 0.05
            }
            PathLine { x: rose.cx + parent.hullB * 0.7; y: rose.cy + parent.hullL * 0.45 }
            PathLine { x: rose.cx - parent.hullB * 0.7; y: rose.cy + parent.hullL * 0.45 }
            PathLine { x: rose.cx - parent.hullB; y: rose.cy + parent.hullL * 0.38 }
            PathCubic {
                x: rose.cx; y: rose.cy - parent.hullL * 0.55
                control1X: rose.cx - parent.hullB * 1.05; control1Y: rose.cy + parent.hullL * 0.05
                control2X: rose.cx - parent.hullB * 0.9; control2Y: rose.cy - parent.hullL * 0.35
            }
        }
    }

    // True wind marker (hollow)
    Item {
        anchors.fill: parent
        visible: !isNaN(rose.twa)
        rotation: isNaN(rose.twa) ? 0 : rose.twa
        Behavior on rotation { RotationAnimation { direction: RotationAnimation.Shortest; duration: 900; easing.type: Easing.OutCubic } }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Theme.accent2
                strokeWidth: 2.5
                fillColor: Theme.alpha(Theme.accent2, 0.15)
                joinStyle: ShapePath.RoundJoin
                startX: rose.cx; startY: rose.cy - rose.r + 18
                PathLine { x: rose.cx - rose.r * 0.07; y: rose.cy - rose.r + 18 - rose.r * 0.13 }
                PathLine { x: rose.cx + rose.r * 0.07; y: rose.cy - rose.r + 18 - rose.r * 0.13 }
                PathLine { x: rose.cx; y: rose.cy - rose.r + 18 }
            }
        }
    }

    // Apparent wind pointer
    Item {
        anchors.fill: parent
        visible: !isNaN(rose.awa)
        rotation: isNaN(rose.awa) ? 0 : rose.awa
        Behavior on rotation { RotationAnimation { direction: RotationAnimation.Shortest; duration: 700; easing.type: Easing.OutCubic } }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            // Long faint shaft toward the center
            ShapePath {
                strokeColor: Theme.alpha(Theme.wind, 0.35)
                strokeWidth: 2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                startX: rose.cx; startY: rose.cy - rose.r + 30
                PathLine { x: rose.cx; y: rose.cy - rose.r * 0.42 }
            }
            ShapePath {
                strokeColor: "transparent"
                fillColor: Theme.wind
                startX: rose.cx; startY: rose.cy - rose.r + 34
                PathLine { x: rose.cx - rose.r * 0.085; y: rose.cy - rose.r + 6 }
                PathLine { x: rose.cx + rose.r * 0.085; y: rose.cy - rose.r + 6 }
                PathLine { x: rose.cx; y: rose.cy - rose.r + 34 }
            }
        }
    }

    // Readouts
    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -rose.r * 0.02
        spacing: 0
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("AWS")
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(10, rose.r * 0.075)
            font.letterSpacing: 1.5
        }
        AnimatedNumber {
            anchors.horizontalCenter: parent.horizontalCenter
            value: rose.aws
            decimals: 1
            font.pixelSize: Math.max(22, rose.r * 0.28)
            font.weight: Font.Light
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("AWA %1°%2").arg(isNaN(rose.awa) ? "—" : Math.abs(Math.round(rose.awa)))
                                    .arg(isNaN(rose.awa) ? "" : rose.awa >= 0 ? " S" : " P")
            color: isNaN(rose.awa) ? Theme.textDim : rose.awa >= 0 ? Theme.starboard : Theme.port
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(11, rose.r * 0.09)
            font.features: { "tnum": 1 }
        }
        Item { width: 1; height: rose.r * 0.06 }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("TWS %1 kn").arg(Units.fmt(rose.tws, 1))
            color: Theme.accent2
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(11, rose.r * 0.085)
            font.features: { "tnum": 1 }
        }
    }
}
