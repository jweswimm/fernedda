import QtQuick
import QtQuick.Shapes
import QtQuick.Controls.Basic
import Fernedda
import "BoatS235C.js" as Boat

// One view of the boat (outside / deck / below), scaled to fit. Parts of the
// boat are tappable zones; user spots are pins that can be dragged.
//
//   tap a zone or pin   → selected(location)
//   tap empty water     → selected("")
//   double-tap / long-press, or tap while `placing` → name a new spot there
Item {
    id: root
    property var view: Boat.views[0]
    property string selection: ""       // zone or spot id
    property bool placing: false
    signal selected(string location)
    signal spotCreated(string spotId)
    clip: true

    readonly property real pad: 18
    readonly property var b: view.bounds
    readonly property real s: Math.max(1, Math.min((width - 2 * pad) / (b[2] - b[0]), (height - 2 * pad - 28) / (b[3] - b[1])))
    readonly property real ox: (width - (b[2] - b[0]) * s) / 2 - b[0] * s
    readonly property real oy: (height - 28 - (b[3] - b[1]) * s) / 2 + b[3] * s
    function px(x) { return ox + x * s }
    function py(y) { return oy - y * s }
    function toBoat(p) { return [(p.x - ox) / s, (oy - p.y) / s] }

    // The zone a location belongs to (a spot's zone, or the zone itself).
    readonly property string selectedZone: {
        if (!selection) return ""
        if (Boat.zoneById[selection]) return selection
        const sp = Notes.spots.find(x => x.spotId === selection)
        return sp ? sp.zone : ""
    }
    property string hoverZone: ""
    property string hoverSpot: ""

    readonly property var spots: Notes.spots.filter(x => x.view === view.id)

    function spotAt(p) {
        let best = "", bd = 18
        for (const sp of spots) {
            const d = Math.hypot(px(sp.x) - p.x, py(sp.y) - p.y)
            if (d < bd) { bd = d; best = sp.spotId }
        }
        return best
    }
    function zoneAt(p) {
        const m = toBoat(p)
        const z = Boat.hit(view, m[0], m[1])
        return z ? z.id : ""
    }

    function startPlacing(p) {
        const m = toBoat(p)
        namer.boatPt = m
        namer.zone = Boat.hit(view, m[0], m[1])
        namer.x = Math.max(8, Math.min(width - namer.width - 8, p.x - namer.width / 2))
        namer.y = p.y + 18 + namer.height > height ? p.y - namer.height - 18 : p.y + 18
        namer.open()
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
                readonly property bool sel: root.selectedZone === modelData.id
                readonly property bool hot: root.hoverZone === modelData.id
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: zoneShape.sel ? Theme.alpha(Theme.accent, 0.22 + 0.08 * pulse.v)
                             : zoneShape.hot ? Theme.alpha(Theme.accent, 0.14) : Theme.alpha(Theme.accent, 0)
                    strokeColor: zoneShape.sel ? Theme.accent : zoneShape.hot ? Theme.alpha(Theme.accent, 0.7)
                               : Theme.alpha(Theme.accent, hover.hovered || root.placing ? 0.16 : 0)
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

        // Note counts per zone.
        Repeater {
            model: root.view.zones
            Rectangle {
                required property var modelData
                readonly property int n: (Notes.revision, Notes.countForLocation(modelData.id))
                readonly property bool show: n > 0 && root.hoverZone !== modelData.id && root.selectedZone !== modelData.id
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
            readonly property var zone: Boat.zoneById[root.hoverZone || root.selection]  // a selected spot labels itself
            readonly property bool show: !!zone && zone.view === root.view.id && !root.hoverSpot
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
                    readonly property int n: zoneLabel.zone ? (Notes.revision, Notes.countForLocation(zoneLabel.zone.id)) : 0
                    visible: n > 0
                    text: n
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.Bold
                }
            }
        }

        // Spots: pins you can drag to a new place.
        Repeater {
            model: root.spots
            Item {
                id: pin
                required property var modelData
                readonly property bool sel: root.selection === modelData.spotId
                readonly property bool hot: root.hoverSpot === modelData.spotId || drag.active
                readonly property int n: (Notes.revision, Notes.countForLocation(modelData.spotId))
                x: root.px(modelData.x) - 13
                y: root.py(modelData.y) - 13
                width: 26
                height: 26
                z: sel || hot ? 2 : 1

                Rectangle {
                    anchors.centerIn: parent
                    width: 26; height: 26; radius: 13
                    color: pin.sel ? Theme.accent : Theme.surfaceHi
                    border.color: Theme.accent
                    border.width: 1.5
                    scale: pin.hot ? 1.18 : 1
                    Behavior on scale { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutBack } }
                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                    Icon { anchors.centerIn: parent; name: "pin"; size: 14; stroke: 2; color: pin.sel ? Theme.bg : Theme.accent }
                }
                Rectangle { // count
                    visible: pin.n > 0
                    x: 17; y: -5
                    width: Math.max(16, pinCount.implicitWidth + 8); height: 16; radius: 8
                    color: Theme.warn
                    Text { id: pinCount; anchors.centerIn: parent; text: pin.n; color: Theme.bg; font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.Bold }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 28
                    text: pin.modelData.name
                    color: pin.sel || pin.hot ? Theme.text : Theme.textDim
                    style: Text.Outline
                    styleColor: Theme.bg
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: pin.sel ? Font.DemiBold : Font.Normal
                }
                DragHandler {
                    id: drag
                    target: pin
                    cursorShape: Qt.ClosedHandCursor
                    onActiveChanged: if (!active) {
                        const m = root.toBoat(Qt.point(pin.x + 13, pin.y + 13))
                        const z = Boat.hit(root.view, m[0], m[1])
                        Notes.updateSpot(pin.modelData.spotId, { x: m[0], y: m[1], zone: z ? z.id : pin.modelData.zone })
                    }
                }
            }
        }
    }

    // ---- input -------------------------------------------------------------
    HoverHandler {
        id: hover
        cursorShape: root.placing ? Qt.CrossCursor : (root.hoverZone || root.hoverSpot) ? Qt.PointingHandCursor : Qt.ArrowCursor
        onPointChanged: {
            root.hoverSpot = root.spotAt(point.position)
            root.hoverZone = root.hoverSpot ? "" : root.zoneAt(point.position)
        }
        onHoveredChanged: if (!hovered) { root.hoverZone = ""; root.hoverSpot = "" }
    }
    TapHandler {
        onTapped: (ev) => {
            if (namer.opened) { namer.close(); return }
            if (root.placing) { root.startPlacing(ev.position); return }
            const sp = root.spotAt(ev.position)
            if (sp) { root.selected(sp); return }
            const z = root.zoneAt(ev.position)
            root.selected(z === root.selection ? "" : z)
        }
        onDoubleTapped: (ev) => { if (!root.spotAt(ev.position)) root.startPlacing(ev.position) }
        onLongPressed: if (!root.spotAt(point.position)) root.startPlacing(point.position)
    }

    // ---- name a new spot -----------------------------------------------------
    Popup {
        id: namer
        property var boatPt: [0, 0]
        property var zone: null
        width: 260
        padding: 12
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
        onOpened: { nameField.text = ""; nameField.forceActiveFocus() }
        onClosed: root.placing = false
        background: Rectangle { color: Theme.surfaceHi; radius: 12; border.color: Theme.alpha(Theme.accent, 0.6) }
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140 }
            NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: 200; easing.type: Easing.OutBack }
        }
        function commit() {
            if (!nameField.text.trim()) return
            const id = Notes.addSpot({ name: nameField.text, view: root.view.id, x: boatPt[0], y: boatPt[1], zone: zone ? zone.id : "" })
            close()
            root.spotCreated(id)
        }
        contentItem: Column {
            spacing: 8
            Text {
                text: namer.zone ? qsTr("New spot in %1").arg(namer.zone.name) : qsTr("New spot")
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }
            TextField {
                id: nameField
                width: parent.width
                placeholderText: qsTr("e.g. Raw water strainer")
                placeholderTextColor: Theme.textFaint
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 14
                background: Rectangle { radius: 8; color: Theme.surface; border.color: nameField.activeFocus ? Theme.accent : Theme.border }
                onAccepted: namer.commit()
            }
            Row {
                spacing: 6
                anchors.right: parent.right
                Chip { text: qsTr("Cancel"); compact: true; onClicked: namer.close() }
                Chip { text: qsTr("Add spot"); icon: "pin"; compact: true; checked: true; onClicked: namer.commit() }
            }
        }
    }

    // Orientation hints for the plan views.
    Text {
        visible: root.view.id !== "outside"
        x: root.px(root.b[0]) + 2; y: root.py(1.85) - 2
        text: qsTr("PORT"); color: Theme.port; opacity: 0.7
        font.family: Theme.fontFamily; font.pixelSize: 10; font.letterSpacing: 1.4
    }
    Text {
        visible: root.view.id !== "outside"
        x: root.px(root.b[0]) + 2; y: root.py(-1.85) - height + 2
        text: qsTr("STBD"); color: Theme.starboard; opacity: 0.7
        font.family: Theme.fontFamily; font.pixelSize: 10; font.letterSpacing: 1.4
    }
    Text {
        x: root.px(root.b[2]) - width - 2
        y: root.view.id === "outside" ? root.py(0) - height - 4 : root.py(1.85) - 2
        text: qsTr("BOW ›"); color: Theme.textFaint
        font.family: Theme.fontFamily; font.pixelSize: 10; font.letterSpacing: 1.4
    }
}
