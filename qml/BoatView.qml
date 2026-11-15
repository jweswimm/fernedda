import QtQuick
import QtQuick.Shapes
import Fernedda
import "BoatS235C.js" as Boat

// One view of the boat (outside / deck / below), scaled to fit. Parts of the
// boat are tappable zones (folders boat/<view>/<zone>/).
//
//   tap a zone          → selected(folder path)
//   tap empty water     → selected("")
//
// `drawZone` set: drawing a new border for that zone instead. Taps place
// corners; tapping the first corner again (or finish()) closes it.
//   done                → drawn(points in metres)
//   cancel / reset      → drawCancelled() / drawReset()
Item {
    id: root
    property var view: Boat.views[0]
    property string selection: ""       // folder path, e.g. "below/engine/Plans"
    property var zones: view.zones      // the parts shown: the view's own, or a layer's
    signal selected(string location)
    // Bumps when zones change (renamed, redrawn), so bindings re-read them.
    property int rev: 0
    property string drawZone: ""          // zone path whose border is being drawn
    property bool drawLine: false         // drawing a line (open), not an area
    property bool drawEdited: false       // it has a border of yours (offer Reset)
    property var drawPts: []              // corners so far, metres
    property point drawHover: Qt.point(-1, -1)
    signal drawn(var points)
    signal drawCancelled()
    signal drawReset()
    // Leaving draw mode puts the camera back where it belongs.
    onDrawZoneChanged: { drawPts = []; if (!drawZone) aim() }
    function undoPoint() { drawPts = drawPts.slice(0, -1) }
    readonly property int drawMin: drawLine ? 2 : 3
    function finish() { if (drawPts.length >= drawMin) drawn(drawPts) }
    // Pixels on the right covered by something floating over the view; the
    // boat fits (and zooms) in the space left of it.
    property real reserveRight: 0
    clip: true

    readonly property real pad: 18
    readonly property real fitW: Math.max(1, width - reserveRight)
    property bool zoom: true                // zoom into the selected part of the boat

    // Camera: the rectangle of the view (metres) fitted to the screen. It
    // eases in to the selected zone and back out to the whole view; switching
    // views snaps. Everything is re-projected from it, so lines stay crisp.
    readonly property var target: {
        const z = rev >= 0 && selectedZone ? Boat.zoneByPath[selectedZone] : null
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

    // Zooming and panning by hand (while drawing a border). Scaling the camera
    // rectangle about a point keeps that point where it is on screen.
    // f > 1 zooms out.
    function zoomAt(p, f) {
        camAnim.stop()
        const m = toBoat(p)
        const w = c2 - c0, vb = view.bounds
        f = Math.max(0.25 / w, Math.min(f, (vb[2] - vb[0]) * 1.5 / w))   // from ~25 cm across to the whole view
        c0 = m[0] + (c0 - m[0]) * f; c2 = m[0] + (c2 - m[0]) * f
        c1 = m[1] + (c1 - m[1]) * f; c3 = m[1] + (c3 - m[1]) * f
    }
    function zoomBy(f) { zoomAt(Qt.point(fitW / 2, (height - 28) / 2), f) }
    function panBy(dx, dy) {
        camAnim.stop()
        const a = dx / s, b = dy / s
        c0 -= a; c2 -= a; c1 += b; c3 += b
    }
    // Back to the part being drawn (as the camera had it).
    function refit() {
        const t = target
        a0.to = t[0]; a1.to = t[1]; a2.to = t[2]; a3.to = t[3]
        camAnim.restart()
    }
    Component.onCompleted: aim()
    ParallelAnimation {
        id: camAnim
        NumberAnimation { id: a0; target: root; property: "c0"; duration: 520; easing.type: Easing.InOutCubic }
        NumberAnimation { id: a1; target: root; property: "c1"; duration: 520; easing.type: Easing.InOutCubic }
        NumberAnimation { id: a2; target: root; property: "c2"; duration: 520; easing.type: Easing.InOutCubic }
        NumberAnimation { id: a3; target: root; property: "c3"; duration: 520; easing.type: Easing.InOutCubic }
    }

    readonly property var b: [c0, c1, c2, c3]
    readonly property real s: Math.max(1, Math.min((fitW - 2 * pad) / (b[2] - b[0]), (height - 2 * pad - 28) / (b[3] - b[1])))
    readonly property real ox: (fitW - (b[2] - b[0]) * s) / 2 - b[0] * s
    readonly property real oy: (height - 28 - (b[3] - b[1]) * s) / 2 + b[3] * s
    function px(x) { return ox + x * s }
    function py(y) { return oy - y * s }

    // Radial tree of a zone's folder, in pixels around the zone's point:
    // { nodes: [{ x, y, dir, depth }], edges: "M … L …" }. Each node gets a
    // slice of the circle sized by how many leaves hang under it.
    function folderGraph(rel) {
        const ring = d => d === 0 ? 0 : 15 + (d - 1) * 11
        const rootNode = { path: rel, dir: true, depth: 0, kids: [] }
        const byPath = { [rel]: rootNode }
        for (const e of BoatFolder.entries(rel)) {
            const n = { path: e.path, dir: e.dir, depth: e.depth, kids: [] }
            byPath[e.path] = n
            const parent = byPath[e.path.slice(0, e.path.lastIndexOf("/"))]
            if (parent) parent.kids.push(n)
        }
        const leaves = n => n.leaves = n.kids.length ? n.kids.reduce((a, k) => a + leaves(k), 0) : 1
        leaves(rootNode)

        const nodes = []
        let edges = ""
        const f = v => Math.round(v * 10) / 10
        const place = (n, a0, a1, px, py) => {
            const a = (a0 + a1) / 2, r = ring(n.depth)
            n.x = r * Math.cos(a); n.y = r * Math.sin(a)
            if (n.depth > 0) edges += "M " + f(px) + " " + f(py) + " L " + f(n.x) + " " + f(n.y) + " "
            nodes.push({ x: n.x, y: n.y, dir: n.dir, depth: n.depth })
            let start = a0
            for (const k of n.kids) {
                const span = (a1 - a0) * k.leaves / n.leaves
                place(k, start, start + span, n.x, n.y)
                start += span
            }
        }
        place(rootNode, -1.5 * Math.PI, 0.5 * Math.PI, 0, 0)  // a lone child points up
        // Draw the root last so it sits on top of its edges.
        nodes.push(nodes.shift())
        return { nodes: nodes, edges: edges }
    }
    function toBoat(p) { return [(p.x - ox) / s, (oy - p.y) / s] }

    // The zone folder the selection is in (or "").
    readonly property string selectedZone: { const z = rev >= 0 ? Boat.zoneOf(selection) : null; return z ? z.path : "" }
    property string hoverZone: ""

    // Things hint mode can label: every zone in this view.
    function hintTargets() {
        return zones.map(z => ({ item: root, x: px(z.at[0]), y: py(z.at[1]), activate: () => root.selected(z.path) }))
    }

    // hjkl: the nearest part of this view in a direction
    // ("h" left, "j" down, "k" up, "l" right), from the selected one — or
    // from the middle of the view when nothing here is selected.
    function neighbor(dir) {
        const d = ({ h: [-1, 0], l: [1, 0], k: [0, 1], j: [0, -1] })[dir]
        const places = zones.map(z => ({ path: z.path, x: z.at[0], y: z.at[1] }))
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
        const z = Boat.hit(zones, m[0], m[1], 12 / s)     // lines: within 12 px
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
        sail:      { fill: Theme.alpha(Theme.text, 0.05), stroke: Theme.alpha(Theme.text, 0.3), w: 1 }
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

        // Zones: invisible until hovered or selected. Lines always show, faintly.
        Repeater {
            model: root.rev >= 0 ? root.zones.slice() : []
            Shape {
                id: zoneShape
                required property var modelData
                readonly property bool sel: root.selectedZone === modelData.path
                readonly property bool hot: root.hoverZone === modelData.path
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                readonly property bool line: !!modelData.line
                ShapePath {
                    fillColor: zoneShape.line ? "transparent"
                             : zoneShape.sel ? Theme.alpha(Theme.accent, 0.22 + 0.08 * pulse.v)
                             : zoneShape.hot ? Theme.alpha(Theme.accent, 0.14) : Theme.alpha(Theme.accent, 0)
                    strokeColor: zoneShape.sel ? Theme.accent : zoneShape.hot ? Theme.alpha(Theme.accent, 0.8)
                               : Theme.alpha(Theme.accent, zoneShape.line ? 0.45 : hover.hovered ? 0.16 : 0)
                    strokeWidth: zoneShape.line ? (zoneShape.sel ? 4 + pulse.v : zoneShape.hot ? 4 : 3) : zoneShape.sel ? 1.8 : 1.2
                    capStyle: ShapePath.RoundCap
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

        // Each zone's folder as a little node graph: the zone in the middle,
        // its folders and files fanned out around it (a radial tree).
        Repeater {
            model: root.rev >= 0 ? root.zones.slice() : []
            Item {
                id: graph
                required property var modelData
                readonly property var g: BoatFolder.revision >= 0 ? root.folderGraph(modelData.path) : ({ nodes: [], edges: "" })
                readonly property bool show: root.hoverZone !== modelData.path && root.selectedZone !== modelData.path
                x: root.px(modelData.at[0])
                y: root.py(modelData.at[1])
                opacity: show ? 1 : 0
                scale: show ? 1 : 0.6
                Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutBack } }

                Shape {
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: Theme.alpha(Theme.accent, 0.75)
                        strokeWidth: 1.3
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        PathSvg { path: graph.g.edges }
                    }
                }
                Repeater {
                    model: graph.g.nodes
                    Rectangle {
                        required property var modelData
                        readonly property real d: modelData.depth === 0 ? 8 : modelData.dir ? 6 : 4
                        x: modelData.x - d / 2
                        y: modelData.y - d / 2
                        width: d
                        height: d
                        radius: d / 2
                        color: modelData.depth === 0 ? Theme.bg : modelData.dir ? Theme.accent : Theme.text
                        border.width: modelData.depth === 0 ? 1.5 : 0
                        border.color: Theme.accent
                    }
                }
            }
        }

        // Label on the hovered / selected zone.
        Rectangle {
            id: zoneLabel
            readonly property var zone: root.rev >= 0 && !root.drawZone ? Boat.zoneByPath[root.hoverZone || root.selectedZone] : null
            readonly property bool show: !!zone && zone.view === root.view.id
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
                    text: root.rev >= 0 && zoneLabel.zone ? zoneLabel.zone.name : ""
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
        cursorShape: root.drawZone ? Qt.CrossCursor : root.hoverZone ? Qt.PointingHandCursor : Qt.ArrowCursor
        onPointChanged: {
            root.drawHover = point.position
            root.hoverZone = root.drawZone ? "" : root.zoneAt(point.position)
        }
        onHoveredChanged: if (!hovered) { root.hoverZone = ""; root.drawHover = Qt.point(-1, -1) }
    }
    TapHandler {
        // Tapping the part you're in keeps you there (a double-click is just
        // two taps); only empty water goes back to the whole boat.
        // Whether this press began in draw mode. The tap on a button that
        // starts drawing (+ Part, Redraw border) can land here too, after the
        // button has turned drawing on; it isn't a corner.
        property bool pressedDrawing: false
        onPressedChanged: if (pressed) pressedDrawing = !!root.drawZone
        onTapped: ev => {
            if (!root.drawZone) { root.selected(root.zoneAt(ev.position)); return }
            if (!pressedDrawing) return
            // Drawing: tapping near the first corner closes the shape.
            const pts = root.drawPts
            if (!root.drawLine && pts.length >= 3 && Math.hypot(ev.position.x - root.px(pts[0][0]), ev.position.y - root.py(pts[0][1])) < 18) {
                root.finish()
                return
            }
            const m = root.toBoat(ev.position)
            root.drawPts = pts.concat([[Math.round(m[0] * 1000) / 1000, Math.round(m[1] * 1000) / 1000]])
        }
    }

    // ---- drawing a border ----------------------------------------------------
    // Wheel or pinch zooms, dragging pans (a drag isn't a tap, so it places no corner).
    WheelHandler {
        enabled: !!root.drawZone
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: ev => root.zoomAt(point.position, Math.pow(0.85, ev.angleDelta.y / 120))
    }
    PinchHandler {
        enabled: !!root.drawZone
        target: null
        property real lastScale: 1
        property point lastCentre
        onActiveChanged: if (active) { lastScale = activeScale; lastCentre = centroid.position }
        onActiveScaleChanged: {
            if (!active) return
            root.zoomAt(centroid.position, lastScale / activeScale)
            lastScale = activeScale
        }
        onCentroidChanged: {
            if (!active) return
            root.panBy(centroid.position.x - lastCentre.x, centroid.position.y - lastCentre.y)
            lastCentre = centroid.position
        }
    }
    DragHandler {
        enabled: !!root.drawZone
        target: null
        property point last
        onActiveChanged: if (active) last = centroid.position
        onCentroidChanged: {
            if (!active) return
            root.panBy(centroid.position.x - last.x, centroid.position.y - last.y)
            last = centroid.position
        }
    }

    Item {
        anchors.fill: parent
        visible: !!root.drawZone
        z: 5
        // Dim the drawing a little so the new border stands out.
        Rectangle { anchors.fill: parent; color: Theme.alpha(Theme.bg, 0.25) }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            // The border so far, filled once it has an area.
            ShapePath {
                strokeColor: Theme.accent
                strokeWidth: 2
                fillColor: Theme.alpha(Theme.accent, !root.drawLine && root.drawPts.length >= 3 ? 0.15 : 0)
                joinStyle: ShapePath.RoundJoin
                capStyle: ShapePath.RoundCap
                PathSvg {
                    path: {
                        const p = root.drawPts
                        if (p.length < 2) return ""
                        let d = "M " + root.px(p[0][0]) + " " + root.py(p[0][1])
                        for (let i = 1; i < p.length; ++i) d += " L " + root.px(p[i][0]) + " " + root.py(p[i][1])
                        return d
                    }
                }
            }
            // Where the next corner would go, and the closing edge.
            ShapePath {
                strokeColor: Theme.alpha(Theme.accent, 0.55)
                strokeWidth: 1.5
                strokeStyle: ShapePath.DashLine
                dashPattern: [4, 4]
                fillColor: "transparent"
                PathSvg {
                    path: {
                        const p = root.drawPts
                        if (!p.length) return ""
                        const last = p[p.length - 1], first = p[0]
                        let d = ""
                        if (root.drawHover.x >= 0)
                            d += "M " + root.px(last[0]) + " " + root.py(last[1]) + " L " + root.drawHover.x + " " + root.drawHover.y
                        if (p.length >= 3 && !root.drawLine)
                            d += " M " + root.px(last[0]) + " " + root.py(last[1]) + " L " + root.px(first[0]) + " " + root.py(first[1])
                        return d
                    }
                }
            }
        }
        Repeater {
            model: root.drawPts
            Rectangle {
                required property var modelData
                required property int index
                // The first corner is bigger: tap it to close the border.
                readonly property real d: index === 0 && !root.drawLine && root.drawPts.length >= 3 ? 16 : 9
                x: root.px(modelData[0]) - d / 2
                y: root.py(modelData[1]) - d / 2
                width: d; height: d; radius: d / 2
                color: index === 0 ? Theme.bg : Theme.accent
                border.color: Theme.accent
                border.width: 2
            }
        }

        // What to do, and the buttons for it, along the top.
        Rectangle {
            id: drawBar
            anchors { top: parent.top; topMargin: 10 }
            x: Math.max(8, (root.fitW - width) / 2)
            width: drawRow.implicitWidth + 16
            height: 48
            radius: 14
            color: Theme.surfaceHi
            border.color: Theme.alpha(Theme.accent, 0.6)
            MouseArea { anchors.fill: parent }   // taps here aren't corners
            Row {
                id: drawRow
                anchors.centerIn: parent
                spacing: 6
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    rightPadding: 6
                    leftPadding: 6
                    readonly property var zone: root.rev >= 0 ? Boat.zoneByPath[root.drawZone] : null
                    text: root.drawLine
                        ? (root.drawPts.length >= 2 ? qsTr("Tap more points, or Done")
                                                    : qsTr("Tap the points of %1").arg(zone ? zone.name : qsTr("the new line")))
                        : root.drawPts.length >= 3 ? qsTr("Tap the first corner, or Done")
                        : qsTr("Tap the corners of %1").arg(zone ? zone.name : qsTr("the new part"))
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                }
                Chip { icon: "minus"; onClicked: root.zoomBy(1.4) }
                Chip { icon: "plus"; onClicked: root.zoomBy(1 / 1.4) }
                Chip { icon: "expand"; text: qsTr("Fit"); onClicked: root.refit() }
                Chip { icon: "back"; text: qsTr("Undo"); enabled: root.drawPts.length > 0; opacity: enabled ? 1 : 0.4; onClicked: root.undoPoint() }
                Chip { visible: root.drawEdited; text: qsTr("Reset"); onClicked: root.drawReset() }
                Chip { icon: "close"; text: qsTr("Cancel"); onClicked: root.drawCancelled() }
                Chip { icon: "check"; text: qsTr("Done"); checked: true; enabled: root.drawPts.length >= root.drawMin; opacity: enabled ? 1 : 0.4; onClicked: root.finish() }
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
