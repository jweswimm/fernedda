import QtQuick
import QtQuick.Layouts

// Segmented state-of-charge bar. While charging, a highlight sweeps along it.
Item {
    id: m
    property real soc: NaN       // 0..1
    property real current: NaN   // A, + charging
    readonly property bool charging: !isNaN(current) && current > 0.3
    readonly property int segments: 20
    readonly property real lv: isNaN(soc) ? 0 : Math.max(0, Math.min(1, soc))
    readonly property color barColor: lv < 0.25 ? Theme.danger : lv < 0.5 ? Theme.warn : Theme.power
    implicitHeight: 26
    clip: true

    Row {
        id: row
        anchors.fill: parent
        spacing: 3
        Repeater {
            model: m.segments
            Rectangle {
                required property int index
                readonly property bool on: (index + 0.5) / m.segments <= m.lv
                width: (row.width - row.spacing * (m.segments - 1)) / m.segments
                height: row.height
                radius: 3
                color: on ? m.barColor : Theme.alpha(Theme.textFaint, 0.18)
                opacity: on ? 0.55 + 0.45 * (index + 1) / m.segments : 1
                Behavior on color { ColorAnimation { duration: 500 } }
            }
        }
    }
    // Charging sweep
    Rectangle {
        visible: m.charging
        height: row.height
        width: 40
        radius: 3
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 0.5; color: Theme.alpha(Theme.dark ? Theme.text : Theme.surface, Theme.dark ? 0.3 : 0.6) }
            GradientStop { position: 1; color: "transparent" }
        }
        NumberAnimation on x {
            running: m.charging
            from: -40; to: row.width * m.lv
            duration: 1600; loops: Animation.Infinite; easing.type: Easing.InOutQuad
        }
    }
}
