import QtQuick
import QtQuick.Layouts
import Fernedda

// Page title, vessel name, connection status, clock and theme switch.
Item {
    id: bar
    property string title
    implicitHeight: 64

    SignalKValue { id: name; path: "name" }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 28
        anchors.rightMargin: 24
        spacing: 16

        Column {
            Layout.alignment: Qt.AlignVCenter
            spacing: 0
            Text {
                id: titleText
                text: bar.title
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 24
                font.weight: Font.DemiBold
                // Little slide-in whenever the title changes
                onTextChanged: titleAnim.restart()
                SequentialAnimation {
                    id: titleAnim
                    PropertyAction { target: titleText; property: "opacity"; value: 0 }
                    PropertyAction { target: titleShift; property: "x"; value: -12 }
                    PauseAnimation { duration: 80 }
                    ParallelAnimation {
                        NumberAnimation { target: titleText; property: "opacity"; to: 1; duration: 300 }
                        NumberAnimation { target: titleShift; property: "x"; to: 0; duration: 420; easing.type: Easing.OutCubic }
                    }
                }
                transform: Translate { id: titleShift }
            }
            Text {
                text: name.valid ? String(name.value) : qsTr("No vessel")
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }
        }

        Item { Layout.fillWidth: true }

        // Connection status pill
        Rectangle {
            id: status
            readonly property bool ok: Connection.state === Connection.Connected
            readonly property bool busy: Connection.state === Connection.Connecting
            readonly property color tone: ok ? (Connection.mode === Connection.Simulated ? Theme.accent2 : Theme.good)
                                             : busy ? Theme.warn : Connection.state === Connection.Error ? Theme.danger : Theme.textFaint
            Layout.preferredHeight: 34
            Layout.preferredWidth: statusRow.implicitWidth + 26
            Layout.maximumWidth: 420
            radius: 17
            color: Theme.alpha(tone, 0.10)
            border.color: Theme.alpha(tone, 0.35)
            Behavior on color { ColorAnimation { duration: Theme.normal } }

            RowLayout {
                id: statusRow
                anchors.fill: parent
                anchors.leftMargin: 13
                anchors.rightMargin: 13
                spacing: 9
                Item {
                    width: 10; height: 10
                    Rectangle {
                        id: ping
                        anchors.centerIn: parent
                        width: 10; height: 10; radius: 5
                        color: status.tone
                        SequentialAnimation on scale {
                            running: status.ok || status.busy
                            loops: Animation.Infinite
                            NumberAnimation { from: 1; to: 2.4; duration: 1400; easing.type: Easing.OutCubic }
                            PauseAnimation { duration: 400 }
                        }
                        SequentialAnimation on opacity {
                            running: status.ok || status.busy
                            loops: Animation.Infinite
                            NumberAnimation { from: 0.6; to: 0; duration: 1400; easing.type: Easing.OutCubic }
                            PauseAnimation { duration: 400 }
                        }
                    }
                    Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: status.tone }
                }
                Text {
                    Layout.fillWidth: true
                    text: Connection.statusText
                    elide: Text.ElideRight
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                }
                Text {
                    visible: status.ok
                    text: qsTr("%1/s").arg(Boat.updatesPerSecond)
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.features: { "tnum": 1 }
                }
            }
        }

        // Clock
        Column {
            Layout.alignment: Qt.AlignVCenter
            spacing: 0
            Text {
                id: clock
                anchors.right: parent.right
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 20
                font.weight: Font.Light
                font.features: { "tnum": 1 }
            }
            Text {
                id: utc
                anchors.right: parent.right
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.features: { "tnum": 1 }
            }
            Timer {
                interval: 1000; running: true; repeat: true; triggeredOnStart: true
                onTriggered: {
                    const d = new Date()
                    clock.text = d.toLocaleTimeString(Qt.locale(), "HH:mm:ss")
                    utc.text = d.toISOString().substr(11, 5) + " UTC · " + d.toLocaleDateString(Qt.locale(), "ddd d MMM")
                }
            }
        }

        // Theme switch
        Rectangle {
            Layout.preferredWidth: 38
            Layout.preferredHeight: 38
            radius: 19
            color: themeHover.hovered ? Theme.surfaceHi : "transparent"
            border.color: Theme.border
            Icon {
                id: themeIcon
                anchors.centerIn: parent
                name: Theme.mode === "night" ? "moon" : Theme.mode === "red" ? "eye" : "sun"
                color: Theme.mode === "red" ? Theme.accent : Theme.textDim
                size: 18
                Behavior on rotation { NumberAnimation { duration: 500; easing.type: Easing.OutBack } }
            }
            HoverHandler { id: themeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { themeIcon.rotation += 360; Theme.cycle() } }
        }
    }
}
