import QtQuick
import QtQuick.Layouts
import Fernedda

// Zooms a dashboard card up into a full history chart. `open(item, config)`
// grows the panel out of the item's rectangle; closing shrinks it back.
//
// config: { title, icon, color, series: [{ path, label, unit, scale, offset,
//           decimals, angle, includeZero }] }
Item {
    id: overlay
    property var config: null
    property rect from: Qt.rect(0, 0, 0, 0)
    property int seriesIndex: 0
    property int windowSeconds: 900
    readonly property bool isOpen: state === "open"
    readonly property var series: config && config.series ? config.series[Math.min(seriesIndex, config.series.length - 1)] : null
    readonly property color tone: config && config.color ? config.color : Theme.accent

    function open(item, cfg) {
        config = cfg
        seriesIndex = 0
        from = item.mapToItem(overlay, 0, 0, item.width, item.height)
        state = "open"
    }
    function close() { state = "" }

    visible: backdrop.opacity > 0.01

    SignalKValue { id: live; path: overlay.series ? overlay.series.path : "" }

    Shortcut { sequence: "Esc"; enabled: overlay.isOpen; onActivated: overlay.close() }

    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Theme.alpha(Theme.bg, 0.72)
        opacity: 0
        TapHandler { onTapped: overlay.close() }
    }

    Rectangle {
        id: panel
        x: overlay.from.x; y: overlay.from.y
        width: overlay.from.width; height: overlay.from.height
        radius: Theme.radius + 4
        color: Theme.surface
        border.color: Theme.alpha(overlay.tone, 0.45)
        border.width: 1
        opacity: 0
        clip: true

        // Swallow clicks so they don't reach the backdrop.
        TapHandler {}

        ColumnLayout {
            id: contents
            anchors.fill: parent
            anchors.margins: 24
            spacing: 18
            opacity: 0

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Rectangle {
                    width: 40; height: 40; radius: 12
                    color: Theme.alpha(overlay.tone, 0.15)
                    Icon { anchors.centerIn: parent; name: overlay.config ? overlay.config.icon : "dot"; color: overlay.tone; size: 22 }
                }
                Column {
                    Layout.fillWidth: true
                    Text {
                        text: overlay.config ? overlay.config.title : ""
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 22
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: overlay.series ? overlay.series.path : ""
                        color: Theme.textFaint
                        font.family: Theme.monoFamily
                        font.pixelSize: 12
                    }
                }
                Repeater {
                    model: [[300, "5m"], [900, "15m"], [3600, "1h"], [3 * 3600, "3h"], [6 * 3600, "6h"]]
                    Chip {
                        required property var modelData
                        text: modelData[1]
                        compact: true
                        accent: overlay.tone
                        checked: overlay.windowSeconds === modelData[0]
                        onClicked: overlay.windowSeconds = modelData[0]
                    }
                }
                Item { width: 8 }
                Rectangle {
                    width: 36; height: 36; radius: 18
                    color: closeHover.hovered ? Theme.surfaceHi : "transparent"
                    border.color: Theme.border
                    Icon { anchors.centerIn: parent; name: "close"; size: 16; color: Theme.textDim }
                    HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: overlay.close() }
                    readonly property bool hintable: true
                    function hintActivate() { overlay.close() }
                }
            }

            // Series tabs
            Flow {
                Layout.fillWidth: true
                spacing: 8
                visible: overlay.config && overlay.config.series.length > 1
                Repeater {
                    model: overlay.config ? overlay.config.series : []
                    Chip {
                        required property var modelData
                        required property int index
                        text: modelData.label
                        accent: overlay.tone
                        checked: overlay.seriesIndex === index
                        onClicked: overlay.seriesIndex = index
                    }
                }
            }

            // Stats
            RowLayout {
                Layout.fillWidth: true
                spacing: 36
                BigNumber {
                    label: qsTr("Now")
                    value: overlay.series && live.valid ? live.number * overlay.series.scale + overlay.series.offset : NaN
                    decimals: overlay.series ? overlay.series.decimals : 1
                    unit: overlay.series ? overlay.series.unit : ""
                    angle: overlay.series ? overlay.series.angle : false
                    color: overlay.tone
                    size: 46
                }
                Rectangle { width: 1; Layout.preferredHeight: 56; color: Theme.border }
                BigNumber { label: qsTr("Min"); value: plot.minimum; decimals: overlay.series ? overlay.series.decimals : 1; unit: overlay.series ? overlay.series.unit : ""; size: 28 }
                BigNumber { label: qsTr("Average"); value: plot.average; decimals: overlay.series ? overlay.series.decimals : 1; unit: overlay.series ? overlay.series.unit : ""; size: 28 }
                BigNumber { label: qsTr("Max"); value: plot.maximum; decimals: overlay.series ? overlay.series.decimals : 1; unit: overlay.series ? overlay.series.unit : ""; size: 28 }
                Item { Layout.fillWidth: true }
            }

            HistoryPlot {
                id: plot
                Layout.fillWidth: true
                Layout.fillHeight: true
                path: overlay.series ? overlay.series.path : ""
                windowSeconds: overlay.windowSeconds
                valueScale: overlay.series ? overlay.series.scale : 1
                valueOffset: overlay.series ? overlay.series.offset : 0
                angle: overlay.series ? overlay.series.angle : false
                includeZero: overlay.series ? !!overlay.series.includeZero : false
                decimals: overlay.series ? overlay.series.decimals : 1
                unit: overlay.series ? overlay.series.unit : ""
                color: overlay.tone
                gridColor: Theme.alpha(Theme.textFaint, 0.6)
                textColor: Theme.textDim
                surfaceColor: Theme.surfaceHi
                lineWidth: 2.2
                fillOpacity: 0.30
                property real revealTo: 0
                reveal: revealTo
                // Switching series replays the draw-in.
                onPathChanged: if (overlay.isOpen) replay.restart()
                NumberAnimation {
                    id: replay
                    target: plot; property: "revealTo"
                    from: 0; to: 1; duration: 700; easing.type: Easing.OutCubic
                }
            }

            Text {
                Layout.fillWidth: true
                text: live.valid ? qsTr("Source %1 · updated %2").arg(live.source || "—").arg(live.timestamp.toLocaleTimeString(Qt.locale(), "HH:mm:ss"))
                                 : qsTr("No data yet")
                color: Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }
        }
    }

    states: State {
        name: "open"
        PropertyChanges { backdrop.opacity: 1 }
        PropertyChanges {
            panel.x: 20; panel.y: 12
            panel.width: overlay.width - 40; panel.height: overlay.height - 32
            panel.opacity: 1
            contents.opacity: 1
            plot.revealTo: 1
        }
    }
    transitions: [
        Transition {
            to: "open"
            ParallelAnimation {
                NumberAnimation { target: backdrop; property: "opacity"; duration: 300 }
                NumberAnimation { target: panel; property: "opacity"; duration: 140 }
                NumberAnimation { target: panel; properties: "x,y,width,height"; duration: 520; easing.type: Easing.OutQuint }
                SequentialAnimation {
                    PauseAnimation { duration: 220 }
                    NumberAnimation { target: contents; property: "opacity"; duration: 260 }
                }
                SequentialAnimation {
                    PauseAnimation { duration: 280 }
                    NumberAnimation { target: plot; property: "revealTo"; duration: 900; easing.type: Easing.OutCubic }
                }
            }
        },
        Transition {
            from: "open"
            SequentialAnimation {
                ParallelAnimation {
                    NumberAnimation { target: contents; property: "opacity"; duration: 120 }
                    NumberAnimation { target: panel; properties: "x,y,width,height"; duration: 380; easing.type: Easing.InOutCubic }
                    NumberAnimation { target: backdrop; property: "opacity"; duration: 360 }
                    SequentialAnimation {
                        PauseAnimation { duration: 260 }
                        NumberAnimation { target: panel; property: "opacity"; duration: 120 }
                    }
                }
                ScriptAction { script: overlay.config = null }
            }
        }
    ]
}
