import QtQuick
import QtQuick.Layouts
import QtCore
import Fernedda
import "BoatS235C.js" as Boat

// The page is the boat drawing, with Neovim in a pane beside it. Each part of
// the boat is a folder (boat/<view>/<zone>/) with category folders inside.
//
// Tap a part of the boat for a small menu of its categories; picking one (and
// creating it if it's missing) opens its folder in Neovim. The app and Neovim
// follow each other: moving in oil focuses that part of the boat here, and
// choosing something here moves oil's cursor to it.
Page {
    id: page
    title: qsTr("Notes")

    property string boatView: "outside"
    property string location: ""          // folder path, e.g. "below/engine"
    property bool overview: true          // in the boat folder itself: the turning 3D model, not a drawing
    property bool menuOpen: false         // the category menu on the selected part
    property bool zoom: true              // zoom the drawing into the selected part
    property bool paneShown: true         // the Neovim pane
    property real paneShare: 0.45         // its share of the page's width
    property bool tiles: true             // touch boxes over oil's entries in Neovim
    property var tileState: null          // where they go, from fernedda.lua
    Settings {
        category: "notes"
        property alias boatView: page.boatView
        property alias folder: page.location
        property alias zoom: page.zoom
        property alias pane: page.paneShown
        property alias paneShare: page.paneShare
        property alias tiles: page.tiles
    }
    readonly property bool compact: boatPanel.width < 1000
    readonly property bool tight: boatPanel.width < 460   // view chips are icons only

    Component.onCompleted: {
        const zones = []
        for (const v of Boat.views)
            for (const z of v.zones) zones.push(z.path)
        BoatFolder.setZones(zones)
        if (location && !BoatFolder.isFolder(location)) location = ""
        overview = !location.includes("/")
    }
    // The first time this page opens, bring up Neovim in its pane.
    property bool launched: false
    onActiveChanged: {
        if (active && !launched) { launched = true; if (!Nvim.running) Nvim.launch(BoatFolder.root) }
        if (!active) {
            menuOpen = false
            if (nvimView.activeFocus) Keyboard.release()   // don't type into a hidden pane
        }
    }

    // ---- locations -----------------------------------------------------------

    function pretty(s) { return s.replace(/[-_]+/g, " ") }
    // { name, crumbs, view, zone } for a folder path, or null.
    function locInfo(loc) {
        if (!loc) return null
        const parts = loc.split("/")
        const v = Boat.viewById(parts[0])
        const z = parts.length >= 2 ? Boat.zoneByPath[parts[0] + "/" + parts[1]] : null
        const crumbs = [v ? v.label : pretty(parts[0])]
        if (parts.length >= 2) crumbs.push(z ? z.name : pretty(parts[1]))
        for (let i = 2; i < parts.length; ++i) crumbs.push(pretty(parts[i]))
        return { name: crumbs[crumbs.length - 1], crumbs: crumbs, view: v ? v.id : "", zone: z ? z.path : "" }
    }

    // Go to a folder. `fromNvim` is set when oil asked for it, so we don't echo back.
    function setLocation(loc, fromNvim) {
        location = loc
        const i = locInfo(loc)
        if (i && i.view) boatView = i.view
        if (!i || !i.zone) menuOpen = false
        // In oil, the boat folder's own listing has the cursor on a view's folder.
        if (loc.includes("/")) overview = false
        else if (fromNvim) overview = true
        if (!fromNvim && Nvim.running) Nvim.reveal(BoatFolder.absPath(loc))
    }
    function up() {
        if (menuOpen) { menuOpen = false; return }
        if (location.includes("/")) setLocation(location.slice(0, location.lastIndexOf("/")))
        else showOverview()
    }
    function showOverview() {
        overview = true
        setLocation("")
    }

    // Oil moved (or a file was opened) in Neovim.
    Connections {
        target: Nvim
        function onRunningChanged() {
            if (!Nvim.running && nvimView.activeFocus) Keyboard.release()
            if (!Nvim.running) page.tileState = null
        }
        function onTiles(json) {
            try { page.tileState = JSON.parse(json) } catch (e) { page.tileState = null }
        }
        function onFocused(absPath) {
            const rel = BoatFolder.relPath(absPath)
            if (rel === "") return                       // outside the boat folder
            if (rel === ".") page.setLocation("", true)
            else if (BoatFolder.isFolder(rel)) page.setLocation(rel, true)
            else page.setLocation(rel.includes("/") ? rel.slice(0, rel.lastIndexOf("/")) : "", true)
        }
    }

    // ---- categories ----------------------------------------------------------

    // Open a category of the selected part in Neovim, creating its folder if needed.
    function openCategory(name) {
        const i = locInfo(location)
        if (!i || !i.zone) return
        const folder = i.zone + "/" + name
        if (!BoatFolder.makeFolder(folder)) return
        menuOpen = false
        setLocation(folder, true)                    // openFolder moves oil
        if (!Nvim.running) Nvim.launch(BoatFolder.root)
        Nvim.openFolder(BoatFolder.absPath(folder))  // waits for a just-launched nvim
        focusEditor()
    }
    function toggleMenu() {
        const i = locInfo(location)
        menuOpen = !menuOpen && !!i && !!i.zone
    }

    function insertReadings() {
        if (!Nvim.running) return
        Nvim.insert(readingsMarkdown())
        focusEditor()
    }
    // Move the keyboard to Neovim, starting it if needed. The page may still be
    // hidden, just switched to, and an invisible item can't take focus.
    property bool focusWhenShown: false
    onVisibleChanged: if (visible && focusWhenShown) focusEditor()
    function focusEditor() {
        if (!Nvim.running) Nvim.launch(BoatFolder.root)
        paneShown = true
        focusWhenShown = !visible
        if (visible) nvimView.forceActiveFocus()
    }
    // Hide the pane, or bring it up ready to type. If Neovim has quit, an open
    // pane is only showing "Ctrl+T to start it", so start it.
    function togglePane() {
        if (paneShown && Nvim.running) {
            if (nvimView.activeFocus) Keyboard.release()   // don't type into a hidden pane
            paneShown = false
        } else {
            focusEditor()
        }
    }
    function switchPane() {
        if (nvimView.activeFocus) Keyboard.release()
        else focusEditor()
    }

    // Boat views and zones from the keyboard.
    function setView(i) {
        if (i < 0 || i >= Boat.views.length) return
        overview = false
        setLocation(Boat.views[i].id)
    }
    function cycleView(d) {
        const i = Boat.views.findIndex(v => v.id === boatView)
        setView((i + d + Boat.views.length) % Boat.views.length)
    }
    // hjkl: move to the neighbouring part of the boat on screen. An open menu follows.
    function step(dir) {
        const next = boatCanvas.neighbor(dir)
        if (next) setLocation(next)
    }

    // Live values for "Insert readings"
    SignalKValue { id: rHours; path: "propulsion.main.runTime" }
    SignalKValue { id: rHouseV; path: "electrical.batteries.house.voltage" }
    SignalKValue { id: rSoc; path: "electrical.batteries.house.stateOfCharge" }
    SignalKValue { id: rPos; path: "navigation.position" }
    SignalKValue { id: rDepth; path: "environment.depth.belowTransducer" }
    SignalKValue { id: rBaro; path: "environment.outside.pressure" }
    SignalKValue { id: rFuel; path: "tanks.fuel.0.currentLevel" }

    function readingsMarkdown() {
        const parts = []
        if (rHours.valid) parts.push(qsTr("Engine **%1 h**").arg(Units.hours(rHours.number).toFixed(1)))
        if (rHouseV.valid) parts.push(qsTr("House %1 V").arg(rHouseV.number.toFixed(2)) + (rSoc.valid ? " (" + Math.round(rSoc.number * 100) + "%)" : ""))
        if (rFuel.valid) parts.push(qsTr("Fuel %1%").arg(Math.round(rFuel.number * 100)))
        if (rDepth.valid) parts.push(qsTr("Depth %1 m").arg(rDepth.number.toFixed(1)))
        if (rBaro.valid) parts.push(qsTr("Baro %1 hPa").arg(Units.hPa(rBaro.number).toFixed(1)))
        if (rPos.valid) parts.push(Units.latLon(rPos.value.latitude, true) + " " + Units.latLon(rPos.value.longitude, false))
        const when = new Date().toLocaleString(Qt.locale(), "yyyy-MM-dd HH:mm")
        return "\n> **Readings · " + when + "**  \n> " + (parts.length ? parts.join(" · ") : qsTr("no data")) + "\n"
    }

    // ---- keys ----------------------------------------------------------------
    // Normal-mode keys while this page is showing; Main.qml routes them here.
    readonly property var keymap: [
        ["h j k l", qsTr("move to the part of the boat left / below / above / right")],
        ["Enter", qsTr("show / hide the part's folders")],
        ["d p r", qsTr("open Documentation / Plans / Research (in the menu)")],
        ["Space h, - / Backspace", qsTr("back / up a folder, out to the whole boat")],
        ["0", qsTr("the whole boat in 3D")],
        ["1 2 3", qsTr("Outside / Deck / Below")], ["H / L, gT / gt", qsTr("previous / next view")],
        ["z", qsTr("zoom into parts on / off")],
        ["t", qsTr("touch mode (bigger text, tappable files) on / off")],
        ["i", qsTr("insert readings into the open file")]
    ]
    function handleKey(seq) {
        if (menuOpen) {
            const category = boatCanvas.categories.find(c => c.key === seq)
            if (category) { openCategory(category.name); return true }
        }
        switch (seq) {
        case "h": case "j": case "k": case "l": step(seq); return true
        case "Enter": toggleMenu(); return true
        case "Spaceh": case "-": case "Backspace": up(); return true
        case "0": showOverview(); return true
        case "1": setView(0); return true
        case "2": setView(1); return true
        case "3": setView(2); return true
        case "L": case "gt": cycleView(1); return true
        case "H": case "gT": cycleView(-1); return true
        case "z": zoom = !zoom; return true
        case "t": tiles = !tiles; return true
        case "i": insertReadings(); return true
        case "Escape":
            if (menuOpen) { menuOpen = false; return true }
            return false
        }
        return false
    }
    // Keys that start a longer sequence here.
    readonly property var prefixes: ["g", "Space"]

    // ---- Neovim -------------------------------------------------------------
    Rectangle {
        id: nvimPane
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom; rightMargin: 24; bottomMargin: 16 }
        width: Math.max(320, Math.min(page.width - 400, page.width * page.paneShare))
        visible: page.paneShown
        radius: 12
        color: nvimView.background
        border.width: nvimView.activeFocus ? 2 : 1
        border.color: nvimView.activeFocus ? Theme.accent : Theme.border
        clip: true
        readonly property bool hintable: true
        function hintActivate() { page.focusEditor() }

        // Touch mode: each file and folder oil shows is a button. Drawn under
        // Neovim, whose text shows through (it paints no default background);
        // the tap targets sit on top of Neovim, further down.
        Item {
            id: touch
            anchors.fill: nvimView
            readonly property var st: page.tiles && Nvim.running ? page.tileState : null
            readonly property var targets: !st ? [] : st.status
                ? st.boxes.concat([Object.assign({ name: "..", status: true }, st.status)]) : st.boxes
            property string pressed: ""       // the name whose target is held down
            // The pane stays dark in day mode, so draw with the night colours then.
            readonly property var pal: Theme.dark ? Theme.p : Theme.palettes.night
            function rectOf(b) {
                // Re-read whenever the cell size changes.
                return nvimView.cellHeight > 0 && nvimView.footerRows >= 0
                    ? nvimView.cellsRect(b.row - 1, b.col - 1, b.width) : Qt.rect(0, 0, 0, 0)
            }
            Repeater {
                model: touch.st ? touch.st.boxes : []
                Item {
                    id: button
                    required property var modelData
                    readonly property rect at: touch.rectOf(modelData)
                    readonly property real cellW: at.width / Math.max(1, modelData.width)
                    readonly property bool down: touch.pressed === modelData.name
                    x: at.x - 7
                    y: at.y + 3
                    // To the window's right edge, less a cell.
                    width: Math.max(at.width + 14, (modelData.span - 1) * cellW + 7)
                    height: at.height - 6
                    // A darker edge under the face, which the face sinks into when pressed.
                    Rectangle {
                        anchors.fill: parent
                        anchors.topMargin: 2
                        radius: 8
                        color: Qt.darker(touch.pal.surfaceHi, 1.6)
                    }
                    Rectangle {
                        width: parent.width
                        height: parent.height - 2
                        y: button.down ? 2 : 0
                        radius: 8
                        color: button.down ? Theme.alpha(touch.pal.accent, 0.3)
                             : button.modelData.cur ? Qt.lighter(touch.pal.surfaceHi, 1.25) : touch.pal.surfaceHi
                        border.width: button.modelData.cur ? 1.5 : 1
                        border.color: button.modelData.cur || button.down ? touch.pal.accent : touch.pal.border
                        Icon {
                            visible: button.modelData.dir
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            name: "chevron"
                            size: 16
                            color: button.modelData.cur ? touch.pal.accent : touch.pal.textDim
                        }
                    }
                }
            }
        }

        NvimView {
            id: nvimView
            anchors.fill: parent
            anchors.margins: 8
            visible: Nvim.running
            font.family: "monospace"
            // Touch mode: bigger text and taller rows are easier to tap.
            font.pixelSize: page.tiles ? 18 : 14
            lineSpacing: page.tiles ? 12 : 0
            // ...but the path at the bottom and the command line stay as they were.
            footerRows: page.tiles && page.tileState ? page.tileState.footer || 0 : 0
            footerPixelSize: 14
            // Light text on a light panel is unreadable, so day mode stays dark here.
            hostBackground: Theme.dark ? Theme.surface : Theme.palettes.night.surface

            // Tap targets over the buttons below (Neovim is drawn between them),
            // and an outline on the status line's name: up a folder, or back to
            // the folder from a file. Taps drive oil, so the keys work as ever.
            Repeater {
                model: touch.targets
                Item {
                    id: target
                    required property var modelData
                    readonly property bool status: modelData.name === ".." && modelData.status === true
                    readonly property rect at: touch.rectOf(modelData)
                    readonly property real cellW: at.width / Math.max(1, modelData.width)
                    x: at.x - 6
                    y: at.y
                    width: Math.max(at.width, modelData.span * cellW) + 6
                    height: at.height
                    Rectangle {
                        visible: target.status
                        x: 2; y: 1
                        width: target.at.width + 8
                        height: parent.height - 2
                        radius: 4
                        color: tap.pressed ? Theme.alpha(touch.pal.accent, 0.3) : "transparent"
                        border.color: Theme.alpha(touch.pal.accent, tap.pressed ? 0.9 : 0.45)
                    }
                    MouseArea {
                        id: tap
                        anchors.fill: parent
                        onPressedChanged: touch.pressed = pressed ? target.modelData.name : ""
                        onClicked: {
                            Nvim.tap(target.modelData.name)
                            page.focusEditor()
                        }
                    }
                }
            }
        }
        Text {
            anchors.centerIn: parent
            visible: !Nvim.running
            text: qsTr("Neovim isn't running · Ctrl+T to start it")
            color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: 14
        }
    }
    // Drag the gap between the panels to resize.
    MouseArea {
        anchors { right: nvimPane.left; top: nvimPane.top; bottom: nvimPane.bottom }
        width: 12
        visible: page.paneShown
        cursorShape: Qt.SplitHCursor
        onPositionChanged: mouse => {
            const x = mapToItem(page, mouse.x, 0).x
            page.paneShare = Math.max(0.2, Math.min(0.8, (page.width - 24 - x) / page.width))
        }
    }

    // ---- Boat drawing -------------------------------------------------------
    Rectangle {
        id: boatPanel
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: page.paneShown ? nvimPane.left : parent.right }
        anchors.leftMargin: 24
        anchors.rightMargin: page.paneShown ? 12 : 24
        anchors.bottomMargin: 16
        radius: Theme.radius
        color: Theme.surface
        // Marks where the keyboard is, like the Neovim pane; pointless with one pane.
        readonly property bool active: page.paneShown && !nvimView.activeFocus
        border.width: active ? 2 : 1
        border.color: active ? Theme.accent : Theme.border

        RowLayout {
            id: boatBar
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
            spacing: 6

            // Where on the boat: breadcrumb, back.
            Rectangle {
                id: whereBar
                Layout.preferredWidth: Math.min(360, implicitWidth)
                implicitWidth: whereRow.implicitWidth + 24
                Layout.preferredHeight: 40
                radius: 12
                color: Theme.surfaceHi
                border.color: info ? Theme.alpha(Theme.accent, 0.45) : Theme.border
                readonly property var info: page.overview ? null : page.locInfo(page.location)
                RowLayout {
                    id: whereRow
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 6
                    spacing: 6
                    Icon { name: "boat"; size: 16; color: whereBar.info ? Theme.accent : Theme.textDim }
                    Column {
                        Layout.fillWidth: true
                        Text {
                            width: Math.min(implicitWidth, 260)
                            text: whereBar.info ? whereBar.info.crumbs.slice(0, -1).join("  ›  ").toUpperCase() || Boat.name.toUpperCase()
                                                : Boat.name.toUpperCase()
                            color: Theme.textFaint
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.letterSpacing: 1.2
                        }
                        Text {
                            width: Math.min(implicitWidth, 260)
                            text: whereBar.info ? whereBar.info.name : qsTr("Whole boat")
                            color: Theme.text
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }
                    }
                    Chip {
                        visible: !!whereBar.info
                        compact: true
                        icon: "back"
                        onClicked: page.up()
                    }
                }
            }
            Item { Layout.fillWidth: true }
            Chip {
                compact: page.compact
                text: qsTr("3D")
                checked: page.overview
                onClicked: page.showOverview()
            }
            Repeater {
                model: Boat.views
                Chip {
                    required property var modelData
                    required property int index
                    compact: page.compact
                    text: page.tight ? "" : modelData.label
                    icon: ({ outside: "boat", deck: "hull", below: "home" })[modelData.id] || "boat"
                    checked: !page.overview && page.boatView === modelData.id
                    onClicked: page.setView(index)
                }
            }
            Item { Layout.fillWidth: true }
            Chip {
                icon: "data"
                compact: page.compact
                text: page.compact ? "" : qsTr("Neovim")
                accent: Theme.good
                checked: Nvim.running
                onClicked: page.focusEditor()
            }
        }

        BoatView {
            id: boatCanvas
            anchors { left: parent.left; right: parent.right; top: boatBar.bottom; bottom: parent.bottom; margins: 6 }
            visible: !page.overview
            view: Boat.viewById(page.boatView) || Boat.views[0]
            selection: page.location
            zoom: page.zoom
            menuOpen: page.menuOpen
            onSelected: loc => {
                page.setLocation(loc)
                page.menuOpen = !!loc
            }
            onCategoryChosen: name => page.openCategory(name)
            onViewChanged: viewIn.restart()
            ParallelAnimation {
                id: viewIn
                NumberAnimation { target: boatCanvas; property: "opacity"; from: 0; to: 1; duration: 260 }
                NumberAnimation { target: boatCanvas; property: "scale"; from: 0.97; to: 1; duration: 420; easing.type: Easing.OutCubic }
            }
        }

        // The whole boat in 3D. Built the first time it's shown, then kept.
        Loader {
            id: boat3D
            anchors { left: parent.left; right: parent.right; top: boatBar.bottom; bottom: parent.bottom; margins: 6 }
            active: page.overview || status === Loader.Ready
            source: "Boat3D.qml"
            opacity: page.overview ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 260 } }
        }
        Text {
            anchors.centerIn: boat3D
            visible: page.overview && boat3D.status === Loader.Error
            text: qsTr("The 3D view needs Qt Quick 3D (qt6-qtquick3d)")
            color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: 14
        }

        Text {
            anchors { left: parent.left; bottom: parent.bottom; margins: 16 }
            text: Boat.name + "  ·  " + Boat.specs
            color: Theme.textFaint
            font.family: Theme.fontFamily
            font.pixelSize: 11
        }
        Text {
            visible: !page.compact
            anchors { right: parent.right; bottom: parent.bottom; margins: 16 }
            text: qsTr("hjkl  move around the boat  ·  Enter  folders  ·  f  hints  ·  0 1 2 3  views  ·  ?  all keys")
            color: Theme.textFaint
            font.family: Theme.fontFamily
            font.pixelSize: 11
        }
    }
}
