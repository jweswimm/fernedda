import QtQuick
import QtQuick.Layouts

// Left navigation. The selection pill springs between items.
Rectangle {
    id: rail
    property int currentIndex: 0
    property var items: []   // [{ icon, label }]
    signal selected(int index)

    implicitWidth: 84
    color: Theme.alpha(Theme.surface, 0.6)
    border.width: 0

    Rectangle {
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
        width: 1
        color: Theme.border
    }

    // Logo mark
    Item {
        id: logo
        anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: 18 }
        width: 44; height: 44
        Rectangle {
            anchors.fill: parent
            radius: 14
            gradient: Gradient {
                GradientStop { position: 0; color: Theme.accent }
                GradientStop { position: 1; color: Theme.accent2 }
            }
            opacity: 0.9
        }
        Icon { anchors.centerIn: parent; name: "boat"; size: 24; color: Theme.bg; stroke: 2.2 }
    }

    Column {
        id: col
        anchors { top: logo.bottom; topMargin: 26; left: parent.left; right: parent.right }
        spacing: 6

        Repeater {
            model: rail.items
            Item {
                id: item
                required property int index
                required property var modelData
                width: col.width
                height: 64
                readonly property bool current: rail.currentIndex === index

                Column {
                    anchors.centerIn: parent
                    spacing: 4
                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: item.modelData.icon
                        size: 22
                        color: item.current ? Theme.accent : hh.hovered ? Theme.text : Theme.textDim
                        Behavior on color { ColorAnimation { duration: Theme.fast } }
                        scale: item.current ? 1.08 : 1
                        Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutBack } }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: item.modelData.label
                        color: item.current ? Theme.text : Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: item.current ? Font.DemiBold : Font.Normal
                    }
                }
                HoverHandler { id: hh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: rail.selected(item.index) }
                readonly property bool hintable: true
                function hintActivate() { rail.selected(item.index) }
            }
        }
    }

    // Moving selection pill + edge marker
    Rectangle {
        id: pill
        x: 10
        width: rail.width - 20
        height: 64
        radius: 14
        color: Theme.alpha(Theme.accent, 0.10)
        border.color: Theme.alpha(Theme.accent, 0.25)
        y: col.y + rail.currentIndex * (64 + col.spacing)
        Behavior on y { SpringAnimation { spring: 4; damping: 0.32; epsilon: 0.25 } }
    }
    Rectangle {
        x: 0
        width: 3
        radius: 2
        height: 28
        color: Theme.accent
        y: pill.y + (pill.height - height) / 2
    }
}
