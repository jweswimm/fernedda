import QtQuick
import QtQuick.Layouts

// Dashboard tile: header (icon, title, optional badge) over free content.
// Slides in with a stagger when its page appears (`order`), lifts on hover,
// and emits `opened` when clicked so the page can zoom it into a detail view.
Item {
    id: card
    property string title
    property string icon: "dot"
    property color accent: Theme.accent
    property string badge
    property color badgeColor: Theme.textDim
    property bool interactive: true
    property int order: 0
    property bool revealed: true
    property alias hovered: hover.hovered
    default property alias content: body.data

    signal opened()
    readonly property bool hintable: interactive
    function hintActivate() { opened() }

    // Entrance
    opacity: 0
    property real lift: 26
    transform: Translate { y: card.lift }
    states: State {
        name: "in"; when: card.revealed
        PropertyChanges { card.opacity: 1; card.lift: 0 }
    }
    transitions: [
        Transition {
            to: "in"
            SequentialAnimation {
                PauseAnimation { duration: 70 * card.order }
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; duration: 420; easing.type: Easing.OutCubic }
                    NumberAnimation { property: "lift"; duration: 620; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
                }
            }
        },
        Transition {
            from: "in"
            NumberAnimation { properties: "opacity,lift"; duration: 160 }
        }
    ]

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: Theme.radius
        color: Theme.surface
        border.width: 1
        border.color: hover.hovered && card.interactive ? Theme.alpha(card.accent, 0.55) : Theme.border
        Behavior on border.color { ColorAnimation { duration: Theme.fast } }

        scale: tap.pressed && card.interactive ? 0.985 : 1
        Behavior on scale { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic } }
    }

    // Top highlight line
    Rectangle {
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.radius }
        height: 1
        color: Theme.alpha(card.accent, hover.hovered ? 0.6 : 0.25)
        Behavior on color { ColorAnimation { duration: Theme.normal } }
    }

    RowLayout {
        id: header
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
        spacing: 8
        Icon { name: card.icon; color: card.accent; size: 17 }
        Text {
            text: card.title.toUpperCase()
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.letterSpacing: 1.4
            font.weight: Font.DemiBold
            Layout.fillWidth: true
            elide: Text.ElideRight
        }
        Text {
            visible: card.badge.length > 0
            text: card.badge
            color: card.badgeColor
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.features: { "tnum": 1 }
        }
        Icon {
            name: "expand"; size: 14; color: Theme.textFaint
            visible: card.interactive
            opacity: hover.hovered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.fast } }
        }
    }

    Item {
        id: body
        anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: parent.bottom
                  leftMargin: 16; rightMargin: 16; topMargin: 8; bottomMargin: 14 }
    }

    HoverHandler { id: hover; cursorShape: card.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler { id: tap; enabled: card.interactive; onTapped: card.opened() }
}
