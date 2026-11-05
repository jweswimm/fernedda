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
    property bool menuOpen: false         // the category menu on the selected part
    property bool zoom: true              // zoom the drawing into the selected part
    property bool paneShown: true         // the Neovim pane
    property real paneShare: 0.45         // its share of the page's width
    Settings {
        category: "notes"
        property alias boatView: page.boatView
        property alias folder: page.location
        property alias zoom: page.zoom
        property alias pane: page.paneShown
        property alias paneShare: page.paneShare
    }
    readonly property bool compact: boatPanel.width < 1000

    Component.onCompleted: {
        const zones = []
        for (const v of Boat.views)
            for (const z of v.zones) zones.push(z.path)
        BoatFolder.setZones(zones)
        if (location && !BoatFolder.isFolder(location)) location = ""
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
        if (!fromNvim && Nvim.running) Nvim.reveal(BoatFolder.absPath(loc))
    }
    function up() {
        if (menuOpen) { menuOpen = false; return }
        if (!location) return
        setLocation(location.includes("/") ? location.slice(0, location.lastIndexOf("/")) : "")
    }

    // Oil moved (or a file was opened) in Neovim.
    Connections {
        target: Nvim
        function onRunningChanged() { if (!Nvim.running && nvimView.activeFocus) Keyboard.release() }
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
        menuOpen = false
        boatView = Boat.views[i].id
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
        ["1 2 3", qsTr("Outside / Deck / Below")], ["H / L, gT / gt", qsTr("previous / next view")],
        ["z", qsTr("zoom into parts on / off")],
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
        case "1": setView(0); return true
        case "2": setView(1); return true
        case "3": setView(2); return true
        case "L": case "gt": cycleView(1); return true
        case "H": case "gT": cycleView(-1); return true
        case "z": zoom = !zoom; return true
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

        NvimView {
            id: nvimView
            anchors.fill: parent
            anchors.margins: 8
            visible: Nvim.running
            font.family: "monospace"
            font.pixelSize: 14
            // Light text on a light panel is unreadable, so day mode stays dark here.
            hostBackground: Theme.dark ? Theme.surface : Theme.palettes.night.surface
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
        border.color: Theme.border

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
                readonly property var info: page.locInfo(page.location)
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
            Repeater {
                model: Boat.views
                Chip {
                    required property var modelData
                    required property int index
                    compact: page.compact
                    text: modelData.label
                    icon: ({ outside: "boat", deck: "hull", below: "home" })[modelData.id] || "boat"
                    checked: page.boatView === modelData.id
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
            text: qsTr("hjkl  move around the boat  ·  Enter  folders  ·  f  hints  ·  1 2 3  views  ·  ?  all keys")
            color: Theme.textFaint
            font.family: Theme.fontFamily
            font.pixelSize: 11
        }
    }
}
