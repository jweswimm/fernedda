import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import Fernedda

// Every Signal K path the boat is reporting, live, grouped by top-level
// branch. The place to see what a new sensor is actually sending.
Page {
    id: page
    title: qsTr("Data")

    signal openDetail(Item item, var config)

    property string filter: ""

    ListModel { id: rows }

    function rebuild() {
        const q = filter.toLowerCase()
        const want = Boat.paths.filter(p => !q || p.toLowerCase().indexOf(q) >= 0)
        // Diff instead of reset so existing rows (and their animations) stay put.
        let i = 0
        while (i < rows.count) {
            if (want.indexOf(rows.get(i).path) < 0) rows.remove(i)
            else i++
        }
        for (let j = 0; j < want.length; j++) {
            if (j < rows.count && rows.get(j).path === want[j]) continue
            rows.insert(j, { path: want[j], group: want[j].split(".")[0] })
        }
    }
    Connections { target: Boat; function onPathsChanged() { page.rebuild() } }
    onFilterChanged: rebuild()
    Component.onCompleted: rebuild()

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        anchors.bottomMargin: 16
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Rectangle {
                Layout.preferredWidth: 360
                Layout.preferredHeight: 38
                radius: 19
                color: Theme.surface
                border.color: search.activeFocus ? Theme.accent : Theme.border
                Behavior on border.color { ColorAnimation { duration: Theme.fast } }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 10
                    Icon { name: "search"; size: 16; color: Theme.textDim }
                    TextField {
                        id: search
                        Layout.fillWidth: true
                        placeholderText: qsTr("Filter paths…  e.g. battery, wind")
                        placeholderTextColor: Theme.textFaint
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        background: null
                        onTextChanged: page.filter = text
                    }
                }
            }
            Text {
                text: qsTr("%1 paths · %2 updates/s").arg(rows.count).arg(Boat.updatesPerSecond)
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 13
            }
            Item { Layout.fillWidth: true }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: rows
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            section.property: "group"
            section.delegate: Item {
                required property string section
                width: list.width
                height: 44
                Text {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8
                    text: section.toUpperCase()
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.letterSpacing: 1.6
                    font.weight: Font.DemiBold
                }
            }

            add: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 300 }
                NumberAnimation { property: "x"; from: -20; to: 0; duration: 380; easing.type: Easing.OutCubic }
            }
            displaced: Transition { NumberAnimation { properties: "y"; duration: 260; easing.type: Easing.OutCubic } }

            delegate: Rectangle {
                id: row
                required property string path
                required property int index
                width: list.width
                height: 52
                radius: 12
                color: rowHover.hovered ? Theme.surfaceHi : Theme.surface
                border.color: Theme.border
                Behavior on color { ColorAnimation { duration: Theme.fast } }

                SignalKValue { id: v; path: row.path }
                readonly property var d: Units.describe(row.path)
                readonly property bool numeric: v.valid && !isNaN(v.number)

                // Brief flash whenever a value arrives
                Rectangle {
                    id: flash
                    anchors.fill: parent
                    radius: parent.radius
                    color: Theme.accent
                    opacity: 0
                    NumberAnimation on opacity { id: flashAnim; running: false; from: 0.10; to: 0; duration: 600 }
                }
                Connections { target: v; function onChanged() { if (page.active) flashAnim.restart() } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 16
                    Text {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 3
                        text: row.path.substring(row.path.indexOf(".") + 1) || row.path
                        elide: Text.ElideMiddle
                        color: Theme.text
                        font.family: Theme.monoFamily
                        font.pixelSize: 13
                    }
                    HistoryPlot {
                        Layout.preferredWidth: 160
                        Layout.preferredHeight: 30
                        visible: row.numeric
                        path: row.numeric ? row.path : ""
                        windowSeconds: 600
                        valueScale: row.d.scale; valueOffset: row.d.offset; angle: row.d.angle
                        showAxes: false; color: Theme.accent2; lineWidth: 1.4; fillOpacity: 0.2
                    }
                    Item { visible: !row.numeric; Layout.preferredWidth: 160 }
                    Text {
                        Layout.preferredWidth: 220
                        horizontalAlignment: Text.AlignRight
                        text: Units.display(row.path, v.value)
                        elide: Text.ElideRight
                        color: v.stale ? Theme.textFaint : Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        font.features: { "tnum": 1 }
                    }
                    Text {
                        Layout.preferredWidth: 110
                        text: v.source
                        elide: Text.ElideRight
                        color: Theme.textFaint
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                }
                HoverHandler { id: rowHover; cursorShape: row.numeric ? Qt.PointingHandCursor : Qt.ArrowCursor }
                readonly property bool hintable: row.numeric
                function hintActivate() { tapRow.tapped(null, Qt.LeftButton) }
                TapHandler {
                    id: tapRow
                    enabled: row.numeric
                    onTapped: page.openDetail(row, {
                        title: row.path.split(".").slice(-2).join(" › "), icon: "data", color: Theme.accent2,
                        series: [{ path: row.path, label: row.path, unit: row.d.unit, scale: row.d.scale,
                                   offset: row.d.offset, decimals: row.d.decimals, angle: row.d.angle }] })
                }
            }

            Text {
                anchors.centerIn: parent
                visible: rows.count === 0
                text: Boat.paths.length === 0 ? qsTr("Waiting for data…") : qsTr("Nothing matches “%1”").arg(page.filter)
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 15
            }
        }
    }
}
