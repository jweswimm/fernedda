import QtQuick
import QtQuick.Shapes
import Fernedda
import "BoatS235C.js" as Boat

// One view of the boat (outside / deck / below), scaled to fit. Parts of the
// boat are tappable zones (folders boat/<view>/<zone>/). `menuOpen` shows a
// small menu on the selected zone with its category folders.
//
//   tap a zone          → selected(folder path)
//   tap empty water     → selected("")
//   pick from the menu  → categoryChosen(name)
Item {
    id: root
    property var view: Boat.views[0]
    property string selection: ""       // folder path, e.g. "below/engine/Plans"
    property bool menuOpen: false
    signal selected(string location)
    signal categoryChosen(string name)
    // The folders every part of the boat can have, and the keys that pick them.
    readonly property var categories: [
        { name: "Documentation", key: "d", icon: "note" },
        { name: "Plans", key: "p", icon: "list" },
        { name: "Research", key: "r", icon: "search" }
    ]
    clip: true

    readonly property real pad: 18
    property bool zoom: true                // zoom into the selected part of the boat

    // Camera: the rectangle of the view (metres) fitted to the screen. It
    // eases in to the selected zone and back out to the whole view; switching
    // views snaps. Everything is re-projected from it, so lines stay crisp.
    readonly property var target: {
        const z = selectedZone ? Boat.zoneByPath[selectedZone] : null
        const vb = view.bounds
        if (!zoom || !z || z.view !== view.id) return vb
        const bb = z.bbox
        const vw = vb[2] - vb[0], vh = vb[3] - vb[1]
        // Leave room around the part, and don't zoom in past ~2.5× (keep some context).
        const w = Math.min(vw, Math.max((bb[2] - bb[0]) * 1.8, vw * 0.4))
        const h = Math.min(vh, Math.max((bb[3] - bb[1]) * 1.8, vh * 0.4))
        const cx = (bb[0] + bb[2]) / 2, cy = (bb[1] + bb[3]) / 2
        return [cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2]
    }
    readonly property bool zoomed: target !== view.bounds
    property real c0: 0
    property real c1: 0
    property real c2: 1
    property real c3: 1
    property string camView: ""
    function aim() {
        const t = target
        const smooth = camView === view.id
        camView = view.id
        camAnim.stop()
        if (!smooth) { c0 = t[0]; c1 = t[1]; c2 = t[2]; c3 = t[3]; return }
        a0.to = t[0]; a1.to = t[1]; a2.to = t[2]; a3.to = t[3]
        camAnim.start()
    }
    onTargetChanged: aim()
    Component.onCompleted: aim()
    ParallelAnimation {
        id: camAnim
        NumberAnimation { id: a0; target: root; property: "c0"; duration: 520; easing.type: Easing.InOutCubic }
        NumberAnimation { id: a1; target: root; property: "c1"; duration: 520; easing.type: Easing.InOutCubic }
        NumberAnimation { id: a2; target: root; property: "c2"; duration: 520; easing.type: Easing.InOutCubic }
        NumberAnimation { id: a3; target: root; property: "c3"; duration: 520; easing.type: Easing.InOutCubic }
    }

    readonly property var b: [c0, c1, c2, c3]
    readonly property real s: Math.max(1, Math.min((width - 2 * pad) / (b[2] - b[0]), (height - 2 * pad - 28) / (b[3] - b[1])))
    readonly property real ox: (width - (b[2] - b[0]) * s) / 2 - b[0] * s
    readonly property real oy: (height - 28 - (b[3] - b[1]) * s) / 2 + b[3] * s
    function px(x) { return ox + x * s }
    function py(y) { return oy - y * s }
    function toBoat(p) { return [(p.x - ox) / s, (oy - p.y) / s] }

    // The zone folder the selection is in (or "").
    readonly property var selParts: selection ? selection.split("/") : []
    readonly property string selectedZone: selParts.length >= 2 && Boat.zoneByPath[selParts[0] + "/" + selParts[1]] ? selParts[0] + "/" + selParts[1] : ""
    property string hoverZone: ""

    // Things hint mode can label: every zone in this view.
    function hintTargets() {
        return view.zones.map(z => ({ item: root, x: px(z.at[0]), y: py(z.at[1]), activate: () => root.selected(z.path) }))
    }

    // hjkl: the nearest part of this view in a direction
    // ("h" left, "j" down, "k" up, "l" right), from the selected one — or
    // from the middle of the view when nothing here is selected.
    function neighbor(dir) {
        const d = ({ h: [-1, 0], l: [1, 0], k: [0, 1], j: [0, -1] })[dir]
        const places = view.zones.map(z => ({ path: z.path, x: z.at[0], y: z.at[1] }))
        const here = places.find(q => q.path === selectedZone)
        const vb = view.bounds
        const p = here ? [here.x, here.y] : [(vb[0] + vb[2]) / 2, (vb[1] + vb[3]) / 2]
        let best = null, bestScore = Infinity, loose = null, looseScore = Infinity
        for (const q of places) {
            if (here && q.path === here.path) continue
            const vx = q.x - p[0], vy = q.y - p[1]
            const along = vx * d[0] + vy * d[1]
            const across = Math.abs(vx * d[1] - vy * d[0])
            if (along <= 0.05) continue
            const score = along + 2 * across            // straight ahead beats off to the side
            if (along >= across * 0.5) { if (score < bestScore) { best = q; bestScore = score } }
            else if (score < looseScore) { loose = q; looseScore = score }
        }
        const pick = best || loose
        return pick ? pick.path : ""
    }

    function zoneAt(p) {
        const m = toBoat(p)
        const z = Boat.hit(view, m[0], m[1])
        return z ? z.path : ""
    }

    // ---- art ---------------------------------------------------------------
    readonly property var styles: ({
        water:     { fill: Theme.alpha(Theme.accent2, 0.07), stroke: "transparent", w: 0 },
        hull:      { fill: Theme.surfaceHi, stroke: Theme.textDim, w: 1.4 },
        bottom:    { fill: Theme.alpha(Theme.depth, 0.20), stroke: Theme.alpha(Theme.textDim, 0.8), w: 1.2 },
        house:     { fill: Theme.surface, stroke: Theme.textDim, w: 1.1 },
        deck:      { fill: Theme.surfaceHi, stroke: Theme.textDim, w: 1.5 },
        nonskid:   { fill: Theme.alpha(Theme.textFaint, 0.16), stroke: "transparent", w: 0 },
        interior:  { fill: Theme.alpha(Theme.surfaceHi, 0.9), stroke: Theme.textDim, w: 1.3 },
        ghost:     { fill: "transparent", stroke: Theme.alpha(Theme.textFaint, 0.7), w: 1 },
        sole:      { fill: Theme.alpha(Theme.warn, 0.07), stroke: "transparent", w: 0 },
        cushion:   { fill: Theme.alpha(Theme.accent2, 0.13), stroke: Theme.alpha(Theme.accent2, 0.45), w: 1 },
        furniture: { fill: Theme.alpha(Theme.textDim, 0.14), stroke: Theme.alpha(Theme.textDim, 0.7), w: 1 },
        fixture:   { fill: "transparent", stroke: Theme.textDim, w: 1 },
        machine:   { fill: Theme.alpha(Theme.engine, 0.16), stroke: Theme.engine, w: 1.2 },
        wall:      { fill: "transparent", stroke: Theme.textDim, w: 2.2 },
        glass:     { fill: Theme.alpha(Theme.accent2, 0.32), stroke: "transparent", w: 0 },
        stripe:    { fill: "transparent", stroke: Theme.accent, w: 2 },
        line:      { fill: "transparent", stroke: Theme.textDim, w: 1.3 },
        detail:    { fill: "transparent", stroke: Theme.textFaint, w: 1 },
        rig:       { fill: "transparent", stroke: Theme.textDim, w: 1 },
        spar:      { fill: Theme.textDim, stroke: "transparent", w: 0 },
        sail:      { fill: Theme.alpha(Theme.text, 0.05), stroke: Theme.alpha(Theme.text, 0.3), w: 1 },
        canvas:    { fill: Theme.alpha(Theme.textDim, 0.22), stroke: Theme.alpha(Theme.textDim, 0.6), w: 1 }
    })

    Item {
        id: scene
        anchors.fill: parent

        Repeater {
            model: root.view.art
            Shape {
                id: artShape
                required property var modelData
                readonly property var st: root.styles[modelData.style] || root.styles.line
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: artShape.st.fill
                    strokeColor: artShape.st.stroke
                    strokeWidth: artShape.st.w
                    fillRule: ShapePath.WindingFill
                    joinStyle: ShapePath.RoundJoin
                    capStyle: ShapePath.RoundCap
                    PathSvg { path: Boat.project(artShape.modelData.d, root.s, root.ox, root.oy) }
                }
            }
        }

        // Zones: invisible until hovered or selected.
        Repeater {
            model: root.view.zones
            Shape {
                id: zoneShape
                required property var modelData
                readonly property bool sel: root.selectedZone === modelData.path
                readonly property bool hot: root.hoverZone === modelData.path
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: zoneShape.sel ? Theme.alpha(Theme.accent, 0.22 + 0.08 * pulse.v)
                             : zoneShape.hot ? Theme.alpha(Theme.accent, 0.14) : Theme.alpha(Theme.accent, 0)
                    strokeColor: zoneShape.sel ? Theme.accent : zoneShape.hot ? Theme.alpha(Theme.accent, 0.7)
                               : Theme.alpha(Theme.accent, hover.hovered ? 0.16 : 0)
                    strokeWidth: zoneShape.sel ? 1.8 : 1.2
                    fillRule: ShapePath.WindingFill
                    joinStyle: ShapePath.RoundJoin
                    Behavior on fillColor { ColorAnimation { duration: Theme.fast } }
                    Behavior on strokeColor { ColorAnimation { duration: Theme.fast } }
                    PathSvg { path: Boat.project(zoneShape.modelData.d, root.s, root.ox, root.oy) }
                }
            }
        }
        QtObject {
            id: pulse
            property real v: 0
            SequentialAnimation on v {
                running: root.selectedZone !== "" && root.visible
                loops: Animation.Infinite
                NumberAnimation { to: 1; duration: 1100; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0; duration: 1100; easing.type: Easing.InOutSine }
            }
        }

        // File counts per zone.
        Repeater {
            model: root.view.zones
            Rectangle {
                required property var modelData
                readonly property int n: BoatFolder.revision >= 0 ? BoatFolder.fileCount(modelData.path) : 0
                readonly property bool show: n > 0 && root.hoverZone !== modelData.path && root.selectedZone !== modelData.path
                x: root.px(modelData.at[0]) - width / 2
                y: root.py(modelData.at[1]) - height / 2
                width: Math.max(20, countText.implicitWidth + 10)
                height: 20
                radius: 10
                color: Theme.alpha(Theme.accent, 0.9)
                opacity: show ? 1 : 0
                scale: show ? 1 : 0.6
                Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutBack } }
                Text {
                    id: countText
                    anchors.centerIn: parent
                    text: parent.n
                    color: Theme.bg
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.Bold
                }
            }
        }

        // Label on the hovered / selected zone.
        Rectangle {
            id: zoneLabel
            readonly property var zone: Boat.zoneByPath[root.hoverZone || root.selectedZone]
            readonly property bool show: !!zone && zone.view === root.view.id && zone !== menu.zone  // the menu has its name
            visible: opacity > 0
            opacity: show ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.fast } }
            x: show ? Math.max(4, Math.min(root.width - width - 4, root.px(zone.at[0]) - width / 2)) : x
            y: show ? Math.max(4, root.py(zone.at[1]) - height / 2) : y
            Behavior on x { enabled: zoneLabel.opacity > 0.5; NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
            Behavior on y { enabled: zoneLabel.opacity > 0.5; NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
            width: labelRow.implicitWidth + 20
            height: 26
            radius: 13
            color: Theme.surfaceHi
            border.color: Theme.alpha(Theme.accent, 0.6)
            Row {
                id: labelRow
                anchors.centerIn: parent
                spacing: 6
                Text {
                    text: zoneLabel.zone ? zoneLabel.zone.name : ""
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
                Text {
                    readonly property int n: zoneLabel.zone && BoatFolder.revision >= 0 ? BoatFolder.fileCount(zoneLabel.zone.path) : 0
                    visible: n > 0
                    text: n
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.Bold
                }
            }
        }

    }

    // ---- input -------------------------------------------------------------
    HoverHandler {
        id: hover
        cursorShape: root.hoverZone ? Qt.PointingHandCursor : Qt.ArrowCursor
        onPointChanged: {
            const m = menu.mapFromItem(root, point.position)
            root.hoverZone = menu.show && menu.contains(m) ? "" : root.zoneAt(point.position)
        }
        onHoveredChanged: if (!hovered) root.hoverZone = ""
    }
    TapHandler {
        // Tapping the part you're in keeps you there (a double-click is just
        // two taps); only empty water goes back to the whole boat.
        onTapped: ev => root.selected(root.zoneAt(ev.position))
    }

    // ---- category menu -------------------------------------------------------
    // Sits by the selected zone and follows it as the camera moves.
    Rectangle {
        id: menu
        readonly property var zone: root.menuOpen ? Boat.zoneByPath[root.selectedZone] : null
        readonly property bool show: !!zone && zone.view === root.view.id
        z: 10
        width: 250
        height: menuCol.implicitHeight + 16
        radius: 12
        color: Theme.surfaceHi
        border.color: Theme.alpha(Theme.accent, 0.6)
        visible: opacity > 0
        opacity: show ? 1 : 0
        scale: show ? 1 : 0.95
        Behavior on opacity { NumberAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
        x: show ? Math.max(8, Math.min(root.width - width - 8, root.px(zone.at[0]) - width / 2)) : x
        y: {
            if (!show) return y
            const at = root.py(zone.at[1])
            const below = at + 16
            return below + height <= root.height - 8 ? below : Math.max(8, at - height - 16)
        }
        MouseArea { anchors.fill: parent }   // clicks here aren't clicks on the boat

        Column {
            id: menuCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
            spacing: 2
            Text {
                leftPadding: 8
                bottomPadding: 4
                text: menu.zone ? menu.zone.name : ""
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
            Repeater {
                model: root.categories
                Rectangle {
                    id: menuRow
                    required property var modelData
                    readonly property string path: menu.zone ? menu.zone.path + "/" + modelData.name : ""
                    readonly property bool exists: BoatFolder.revision >= 0 && !!path && BoatFolder.isFolder(path)
                    readonly property int files: exists && BoatFolder.revision >= 0 ? BoatFolder.fileCount(path) : 0
                    readonly property bool hintable: true
                    function hintActivate() { root.categoryChosen(modelData.name) }
                    width: menuCol.width
                    height: 36
                    radius: 8
                    color: rowArea.containsMouse ? Theme.alpha(Theme.accent, 0.14) : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                    Row {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 8 }
                        spacing: 8
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: menuRow.modelData.icon
                            size: 15
                            color: menuRow.exists ? Theme.accent : Theme.textFaint
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: menuRow.modelData.name
                            color: menuRow.exists ? Theme.text : Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                        }
                    }
                    Row {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 8 }
                        spacing: 8
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !menuRow.exists
                            name: "plus"
                            size: 12
                            color: Theme.accent
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: !menuRow.exists ? qsTr("Create")
                                : menuRow.files === 1 ? qsTr("1 file")
                                : menuRow.files ? qsTr("%1 files").arg(menuRow.files) : qsTr("Empty")
                            color: menuRow.exists ? Theme.textFaint : Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: menuRow.modelData.key
                            color: Theme.textFaint
                            font.family: Theme.monoFamily
                            font.pixelSize: 12
                        }
                    }
                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.categoryChosen(menuRow.modelData.name)
                    }
                }
            }
        }
    }

    // Orientation hints for the plan views.
    Text {
        visible: root.view.id !== "outside" && !root.zoomed
        x: root.px(root.b[0]) + 2; y: root.py(1.85) - 2
        text: qsTr("PORT"); color: Theme.port; opacity: 0.7
        font.family: Theme.fontFamily; font.pixelSize: 10; font.letterSpacing: 1.4
    }
    Text {
        visible: root.view.id !== "outside" && !root.zoomed
        x: root.px(root.b[0]) + 2; y: root.py(-1.85) - height + 2
        text: qsTr("STBD"); color: Theme.starboard; opacity: 0.7
        font.family: Theme.fontFamily; font.pixelSize: 10; font.letterSpacing: 1.4
    }
    Text {
        visible: !root.zoomed
        x: root.px(root.b[2]) - width - 2
        y: root.view.id === "outside" ? root.py(0) - height - 4 : root.py(1.85) - 2
        text: qsTr("BOW ›"); color: Theme.textFaint
        font.family: Theme.fontFamily; font.pixelSize: 10; font.letterSpacing: 1.4
    }
}
