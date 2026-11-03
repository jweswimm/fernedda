import QtQuick
import QtQuick.Layouts

// Capsule tank with a slowly sloshing liquid surface.
ColumnLayout {
    id: tank
    property real level: NaN   // 0..1
    property string label
    property color color: Theme.accent2
    property real capacityL: NaN
    property bool lowIsBad: true  // fuel/water: warn when low; waste: warn when high
    spacing: 6

    readonly property real lv: isNaN(level) ? 0 : Math.max(0, Math.min(1, level))
    property real shown: lv
    Behavior on shown { NumberAnimation { duration: 1200; easing.type: Easing.OutCubic } }
    readonly property bool alarm: !isNaN(level) && (lowIsBad ? level < 0.15 : level > 0.85)
    readonly property color liquid: alarm ? Theme.warn : color

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        Rectangle {
            id: shell
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(parent.width, 58)
            height: parent.height
            radius: width / 2.6
            color: Theme.alpha(Theme.textFaint, 0.10)
            border.color: Theme.border
            border.width: 1
            clip: true

            Item {
                id: fill
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: parent.height * tank.shown

                // Two big, slowly rotating rounded squares make a wavy surface.
                Rectangle {
                    width: shell.width * 2.4; height: width
                    radius: width * 0.42
                    x: (shell.width - width) / 2
                    y: -6
                    color: Theme.alpha(tank.liquid, 0.35)
                    RotationAnimation on rotation { from: 0; to: 360; duration: 9000; loops: Animation.Infinite }
                }
                Rectangle {
                    width: shell.width * 2.4; height: width
                    radius: width * 0.40
                    x: (shell.width - width) / 2 + 4
                    y: -2
                    color: Theme.alpha(tank.liquid, 0.65)
                    RotationAnimation on rotation { from: 360; to: 0; duration: 7000; loops: Animation.Infinite }
                }
            }

            // Scale marks
            Repeater {
                model: 3
                Rectangle {
                    required property int index
                    x: 0; width: 8; height: 1
                    y: shell.height * (index + 1) / 4
                    color: Theme.alpha(Theme.text, 0.25)
                }
            }
        }
    }
    Text {
        Layout.alignment: Qt.AlignHCenter
        text: isNaN(tank.level) ? "—" : Math.round(tank.shown * 100) + "%"
        color: tank.alarm ? Theme.warn : Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 18
        font.weight: Font.Light
        font.features: { "tnum": 1 }
    }
    Text {
        Layout.alignment: Qt.AlignHCenter
        text: tank.label + (isNaN(tank.capacityL) || isNaN(tank.level) ? "" : "\n" + Math.round(tank.level * tank.capacityL) + " / " + Math.round(tank.capacityL) + " L")
        horizontalAlignment: Text.AlignHCenter
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: 11
    }
}
