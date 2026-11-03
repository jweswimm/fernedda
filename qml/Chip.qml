import QtQuick
import QtQuick.Layouts

// Small pill button / toggle.
Rectangle {
    id: chip
    property string text
    property string icon
    property bool checked: false
    property color accent: Theme.accent
    property bool compact: false
    signal clicked()
    // Hint mode (f) labels every visible chip.
    readonly property bool hintable: true
    function hintActivate() { clicked() }

    implicitHeight: compact ? 24 : 30
    implicitWidth: row.implicitWidth + (compact ? 16 : 22)
    radius: height / 2
    color: checked ? Theme.alpha(accent, 0.18) : hover.hovered ? Theme.surfaceHi : "transparent"
    border.width: 1
    border.color: checked ? Theme.alpha(accent, 0.7) : Theme.border
    Behavior on color { ColorAnimation { duration: Theme.fast } }
    Behavior on border.color { ColorAnimation { duration: Theme.fast } }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Icon { visible: chip.icon.length > 0; name: chip.icon; size: chip.compact ? 12 : 14; color: chip.checked ? chip.accent : Theme.textDim }
        Text {
            text: chip.text
            visible: text.length > 0
            color: chip.checked ? chip.accent : Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: chip.compact ? 11 : 13
            font.weight: chip.checked ? Font.DemiBold : Font.Normal
        }
    }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: chip.clicked() }
}
