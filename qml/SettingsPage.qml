import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import Fernedda

// Data source, appearance and where things are stored.
Page {
    id: page
    title: qsTr("Settings")

    component Section: Rectangle {
        default property alias content: inner.data
        property string heading
        property string icon
        property int order: 0
        Layout.fillWidth: true
        implicitHeight: inner.implicitHeight + 64
        radius: Theme.radius
        color: Theme.surface
        border.color: Theme.border

        opacity: page.entered ? 1 : 0
        Behavior on opacity { SequentialAnimation { PauseAnimation { duration: order * 80 } NumberAnimation { duration: 360 } } }

        RowLayout {
            id: head
            x: 20; y: 18
            spacing: 10
            Icon { name: icon; size: 18; color: Theme.accent }
            Text { text: heading; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 16; font.weight: Font.DemiBold }
        }
        ColumnLayout {
            id: inner
            anchors { left: parent.left; right: parent.right; top: head.bottom; margins: 20; topMargin: 14 }
            spacing: 12
        }
    }

    component Label: Text {
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: 13
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }

    Flickable {
        anchors.fill: parent
        contentHeight: column.implicitHeight + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        ColumnLayout {
            id: column
            x: 24
            width: Math.min(parent.width - 48, 820)
            spacing: Theme.gap

            Section {
                heading: qsTr("Data source")
                icon: "plug"
                order: 0

                RowLayout {
                    spacing: 8
                    Chip {
                        text: qsTr("Simulated boat"); icon: "boat"
                        checked: Connection.mode === Connection.Simulated
                        onClicked: Connection.mode = Connection.Simulated
                    }
                    Chip {
                        text: qsTr("Signal K server"); icon: "plug"
                        checked: Connection.mode === Connection.Live
                        onClicked: Connection.mode = Connection.Live
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    opacity: Connection.mode === Connection.Live ? 1 : 0.45
                    Behavior on opacity { NumberAnimation { duration: Theme.normal } }

                    Label { text: qsTr("Server address") }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 40
                            radius: 10
                            color: Theme.bg2
                            border.color: serverField.activeFocus ? Theme.accent : Theme.border
                            TextField {
                                id: serverField
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                text: Connection.server
                                placeholderText: "raspberrypi.local:3000"
                                placeholderTextColor: Theme.textFaint
                                color: Theme.text
                                font.family: Theme.monoFamily
                                font.pixelSize: 14
                                background: null
                                onAccepted: { Connection.server = text; Connection.mode = Connection.Live }
                            }
                        }
                        Chip {
                            text: qsTr("Connect"); icon: "check"; accent: Theme.good; checked: true
                            onClicked: { Connection.server = serverField.text; Connection.mode = Connection.Live; Connection.reconnect() }
                        }
                    }
                    Label {
                        text: qsTr("Stream: %1").arg(Connection.streamUrl)
                        font.family: Theme.monoFamily
                        font.pixelSize: 12
                        color: Theme.textFaint
                    }
                    Label {
                        text: Connection.statusText + (Connection.selfId ? "  ·  " + Connection.selfId : "")
                        color: Connection.state === Connection.Error ? Theme.danger
                             : Connection.state === Connection.Connected ? Theme.good : Theme.textDim
                    }
                }
            }

            Section {
                heading: qsTr("Getting sensors onto the network")
                icon: "wind"
                order: 1
                Label {
                    textFormat: Text.MarkdownText
                    text: qsTr(
"fernedda reads boat data from a **Signal K** server, the open standard for marine data.\n\n" +
"1. Run **signalk-server** on a Raspberry Pi aboard (or on this laptop to try it: `npx signalk-server --sample-nmea0183-data`).\n" +
"2. Feed it your instruments: NMEA 2000 via a CAN HAT or USB gateway, NMEA 0183 via serial/USB.\n" +
"3. For DIY Wi‑Fi sensors (tank levels, temperatures, bilge, voltages), flash an ESP32 with **SensESP** — it publishes straight to the server.\n" +
"4. Put the server's address above (default port 3000). Everything it reports shows up under **Data**; the dashboard picks up the standard paths automatically.")
                }
            }

            Section {
                heading: qsTr("Appearance")
                icon: "sun"
                order: 2
                RowLayout {
                    spacing: 8
                    Chip { text: qsTr("Night"); icon: "moon"; checked: Theme.mode === "night"; onClicked: Theme.mode = "night" }
                    Chip { text: qsTr("Night vision (red)"); icon: "eye"; checked: Theme.mode === "red"; onClicked: Theme.mode = "red" }
                    Chip { text: qsTr("Day"); icon: "sun"; checked: Theme.mode === "day"; onClicked: Theme.mode = "day" }
                }
                Label { text: qsTr("Red mode keeps your night vision intact on watch. The moon/sun button in the top bar cycles modes too.") }
            }

            Section {
                heading: qsTr("Storage")
                icon: "folder"
                order: 3
                Label { text: qsTr("Notes are Markdown files — sync or back up this folder however you like:") }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Text { Layout.fillWidth: true; text: Notes.folder; elide: Text.ElideMiddle; color: Theme.text; font.family: Theme.monoFamily; font.pixelSize: 13 }
                    Chip { text: qsTr("Open folder"); icon: "folder"; compact: true; onClicked: Qt.openUrlExternally("file://" + Notes.folder) }
                }
            }
        }
    }
}
