import QtQuick
import QtQuick.Layouts

// Label over a large animated value with its unit.
ColumnLayout {
    id: root
    property string label
    property real value: NaN
    property int decimals: 1
    property string unit
    property bool angle: false
    property bool pad3: false
    property int size: 40
    property color color: Theme.text
    property bool stale: false
    spacing: 0

    Text {
        text: root.label
        visible: root.label.length > 0
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: Math.max(11, root.size * 0.28)
    }
    RowLayout {
        spacing: 4
        AnimatedNumber {
            value: root.value
            decimals: root.decimals
            angle: root.angle
            pad3: root.pad3
            color: root.stale ? Theme.textFaint : root.color
            font.pixelSize: root.size
            font.weight: Font.Light
            Layout.alignment: Qt.AlignBaseline
            Behavior on color { ColorAnimation { duration: Theme.normal } }
        }
        Text {
            text: root.unit
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(11, root.size * 0.34)
            Layout.alignment: Qt.AlignBaseline
        }
    }
}
