import QtQuick
import QtQuick.Window
import QtQuick.Shapes
import QtCore
import Fernedda

Window {
    id: window
    width: 1440
    height: 900
    minimumWidth: 760
    minimumHeight: 460
    visible: true
    title: "fernedda"
    color: Theme.bg

    property int pageIndex: 0
    readonly property var pages: [
        { icon: "dashboard", label: qsTr("Dashboard") },
        { icon: "data", label: qsTr("Data") },
        { icon: "notes", label: qsTr("Notes") },
        { icon: "settings", label: qsTr("Settings") }
    ]

    Settings {
        category: "ui"
        property alias theme: themeHolder.mode
        property alias page: window.pageIndex
    }
    // Settings needs a writable alias target; mirror Theme.mode through this.
    QtObject {
        id: themeHolder
        property string mode: Theme.mode
        onModeChanged: Theme.mode = mode
    }
    Connections { target: Theme; function onModeChanged() { themeHolder.mode = Theme.mode } }

    // Keyboard: Ctrl+1..4 switch pages, F11 full screen (for a mounted display).
    Shortcut { sequence: "Ctrl+1"; onActivated: window.pageIndex = 0 }
    Shortcut { sequence: "Ctrl+2"; onActivated: window.pageIndex = 1 }
    Shortcut { sequence: "Ctrl+3"; onActivated: window.pageIndex = 2 }
    Shortcut { sequence: "Ctrl+4"; onActivated: window.pageIndex = 3 }
    Shortcut { sequence: "F11"; onActivated: window.visibility = window.visibility === Window.FullScreen ? Window.Windowed : Window.FullScreen }

    // ---- Background: gradient plus two slow, drifting glows -------------
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.bg2 }
            GradientStop { position: 1; color: Theme.bg }
        }
    }
    Shape {
        id: glows
        anchors.fill: parent
        property real t: 0
        NumberAnimation on t { from: 0; to: Math.PI * 2; duration: 60000; loops: Animation.Infinite }
        readonly property real ax: width * (0.78 + 0.08 * Math.cos(t))
        readonly property real ay: height * (0.12 + 0.08 * Math.sin(t))
        readonly property real bx: width * (0.18 + 0.1 * Math.sin(t))
        readonly property real by: height * (0.95 + 0.05 * Math.cos(t))
        readonly property real rad: Math.max(width, height) * 0.55
        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: glows.ax; centerY: glows.ay; centerRadius: glows.rad
                focalX: centerX; focalY: centerY
                GradientStop { position: 0; color: Theme.alpha(Theme.glowA, 0.9) }
                GradientStop { position: 1; color: "transparent" }
            }
            PathRectangle { x: 0; y: 0; width: glows.width; height: glows.height }
        }
        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: glows.bx; centerY: glows.by; centerRadius: glows.rad * 0.8
                focalX: centerX; focalY: centerY
                GradientStop { position: 0; color: Theme.alpha(Theme.glowB, 0.7) }
                GradientStop { position: 1; color: "transparent" }
            }
            PathRectangle { x: 0; y: 0; width: glows.width; height: glows.height }
        }
    }

    // ---- Chrome ----------------------------------------------------------
    NavRail {
        id: rail
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        items: window.pages
        currentIndex: window.pageIndex
        onSelected: index => window.pageIndex = index
    }

    TopBar {
        id: topBar
        anchors { left: rail.right; right: parent.right; top: parent.top }
        title: window.pages[window.pageIndex].label
    }

    Item {
        id: content
        anchors { left: rail.right; right: parent.right; top: topBar.bottom; bottom: parent.bottom; topMargin: 6 }

        DashboardPage {
            anchors.fill: parent
            active: window.pageIndex === 0
            onOpenDetail: (item, config) => detail.open(item, config)
        }
        DataPage {
            anchors.fill: parent
            active: window.pageIndex === 1
            onOpenDetail: (item, config) => detail.open(item, config)
        }
        NotesPage {
            anchors.fill: parent
            active: window.pageIndex === 2
        }
        SettingsPage {
            anchors.fill: parent
            active: window.pageIndex === 3
        }

        DetailOverlay {
            id: detail
            anchors.fill: parent
        }
    }

    onPageIndexChanged: if (detail.isOpen) detail.close()
}
