import QtQuick

// A top-level page. Only the active one is visible; switching pages fades
// and drifts the old one away while the new one rises into place.
Item {
    id: page
    property bool active: false
    property string title
    // Pages use this to restart entrance animations (e.g. card stagger).
    property bool entered: false

    visible: opacity > 0.001
    opacity: 0
    scale: 0.97
    property real drift: 30
    transform: Translate { y: page.drift }

    states: State {
        name: "active"; when: page.active
        PropertyChanges { page.opacity: 1; page.scale: 1; page.drift: 0 }
    }
    transitions: [
        Transition {
            to: "active"
            SequentialAnimation {
                PauseAnimation { duration: 90 }
                ScriptAction { script: page.entered = true }
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; duration: 380; easing.type: Easing.OutCubic }
                    NumberAnimation { properties: "scale,drift"; duration: 520; easing.type: Easing.OutQuint }
                }
            }
        },
        Transition {
            from: "active"
            SequentialAnimation {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; to: 0; duration: 180; easing.type: Easing.InCubic }
                    NumberAnimation { property: "scale"; to: 1.02; duration: 220; easing.type: Easing.InCubic }
                    NumberAnimation { property: "drift"; to: -16; duration: 220; easing.type: Easing.InCubic }
                }
                ScriptAction { script: { page.entered = false; page.scale = 0.97; page.drift = 30 } }
            }
        }
    ]
}
