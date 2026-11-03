import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtCore
import Fernedda
import "BoatS235C.js" as Boat

// Notes live in the boat folder (boat/<view>/<zone>/[spot]/*.md) and are
// edited in Neovim, in a terminal beside the app. Two ways to browse:
//   Boat    — list | boat drawing. Tap a part of the boat to see its notes;
//             picking a note swaps the drawing for a preview.
//   Systems — systems | list | preview.
// The app and Neovim follow each other: moving in oil focuses that part of the
// boat here, and choosing something here moves oil's cursor to it.
Page {
    id: page
    title: qsTr("Notes")

    property string currentId: ""        // note id = path relative to the boat folder
    property string mode: "boat"          // "boat" | "systems"
    property string boatView: "outside"
    property string location: ""          // folder path, e.g. "below/engine"
    property bool boatShown: true         // boat mode: drawing (true) or preview
    Settings {
        category: "notes"
        property alias note: page.currentId
        property alias mode: page.mode
        property alias boatView: page.boatView
        property alias folder: page.location
    }
    readonly property bool compact: width < 1000
    readonly property bool boatMode: mode === "boat"
    readonly property bool boatVisible: boatMode && boatShown
    readonly property var current: (Notes.revision, currentId ? Notes.get(currentId) : ({}))

    Component.onCompleted: {
        const zones = {}
        for (const v of Boat.views)
            for (const z of v.zones) zones[z.path] = z.system
        Notes.setZones(zones)
        if (currentId && !Notes.get(currentId).noteId) currentId = ""
        if (location && !Notes.isFolder(location)) location = ""
        applyMode()
        boatShown = true
    }
    // The first time Notes opens, bring up Neovim beside the app.
    property bool launched: false
    onActiveChanged: if (active && !launched) { launched = true; if (!Nvim.running) Nvim.launch(Notes.root) }

    function sysIcon(s) {
        return ({ "": "list", Engine: "engine", Electrical: "bolt", Rigging: "rigging", Sails: "sail",
                  "Hull & Deck": "hull", Plumbing: "drop", Navigation: "compass", Safety: "lifebuoy",
                  Interior: "home", General: "note" })[s] || "tag"
    }

    // ---- locations -----------------------------------------------------------

    function applyMode() {
        if (boatMode) { Notes.systemFilter = ""; Notes.locationFilter = location }
        else Notes.locationFilter = ""
    }
    onModeChanged: applyMode()

    function pretty(s) { return s.replace(/[-_]+/g, " ") }
    // { name, crumbs, view, zone, spot, depth, system } for a folder path, or null.
    function locInfo(loc) {
        if (!loc) return null
        const parts = loc.split("/")
        const v = Boat.viewById(parts[0])
        const z = parts.length >= 2 ? Boat.zoneByPath[parts[0] + "/" + parts[1]] : null
        const crumbs = [v ? v.label : pretty(parts[0])]
        if (parts.length >= 2) crumbs.push(z ? z.name : pretty(parts[1]))
        for (let i = 2; i < parts.length; ++i) crumbs.push(pretty(parts[i]))
        return { name: crumbs[crumbs.length - 1], crumbs: crumbs, view: v ? v.id : "", zone: z ? z.path : "",
                 spot: parts.length === 3, depth: parts.length, system: z ? z.system : "" }
    }
    function locLabel(loc) { const i = locInfo(loc); return i ? i.name : "" }

    // Go to a folder. `fromNvim` is set when oil asked for it, so we don't echo back.
    function setLocation(loc, fromNvim) {
        location = loc
        Notes.locationFilter = boatMode ? loc : ""
        const i = locInfo(loc)
        if (i && i.view) boatView = i.view
        if (!fromNvim && Nvim.running) Nvim.reveal(Notes.absPath(loc))
    }
    function showOnBoat(loc) {
        mode = "boat"
        setLocation(loc)
        boatShown = true
    }
    function up() {
        if (boatMode && !boatShown) { boatShown = true; return }
        if (!location) return
        setLocation(location.includes("/") ? location.slice(0, location.lastIndexOf("/")) : "")
    }

    // Oil moved (or a file was opened) in Neovim.
    Connections {
        target: Nvim
        function onFocused(absPath) {
            const rel = Notes.relPath(absPath)
            if (rel === "") return                       // outside the boat folder
            if (rel === "." ) { page.setLocation("", true); page.boatShown = true; return }
            if (Notes.isFolder(rel)) {
                page.mode = "boat"
                page.setLocation(rel, true)
                page.boatShown = true
            } else if (Notes.get(rel).noteId) {
                page.mode = "boat"
                page.setLocation(rel.includes("/") ? rel.slice(0, rel.lastIndexOf("/")) : "", true)
                page.currentId = rel
                page.boatShown = false
            }
        }
    }

    // ---- notes ---------------------------------------------------------------

    function select(id, fromKeys) {
        currentId = id
        if (boatMode) boatShown = false
        const row = Notes.indexOf(id)
        if (row >= 0) noteList.positionViewAtIndex(row, ListView.Contain)
        if (Nvim.running && id) Nvim.reveal(Notes.absPath(id))
    }
    function move(delta) {
        if (Notes.count === 0) return
        const row = Notes.indexOf(currentId)
        const next = row < 0 ? (delta > 0 ? 0 : Notes.count - 1) : Math.max(0, Math.min(Notes.count - 1, row + delta))
        select(Notes.idAt(next))
    }
    function first() { if (Notes.count) select(Notes.idAt(0)) }
    function last() { if (Notes.count) select(Notes.idAt(Notes.count - 1)) }
    function editCurrent() {
        if (!currentId) return
        if (!Nvim.running) Nvim.launch(Notes.root)
        Nvim.edit(Notes.absPath(currentId))          // waits for a just-launched nvim
    }
    function togglePin() { if (currentId) Notes.setPinned(currentId, !current.pinned) }
    function deleteCurrent() {
        if (!currentId) return
        if (!preview.confirmDelete) { preview.confirmDelete = true; confirmTimer.restart(); return }
        const id = currentId
        const row = Notes.indexOf(id)
        currentId = ""
        Notes.remove(id)
        preview.confirmDelete = false
        if (Notes.count) select(Notes.idAt(Math.min(row, Notes.count - 1)))
        else if (boatMode) boatShown = true
    }
    Timer { id: confirmTimer; interval: 3000; onTriggered: preview.confirmDelete = false }
    function newNote() { newPrompt.open() }
    function insertReadings() {
        if (!Nvim.running) return
        Nvim.insert(readingsMarkdown())
        Nvim.focusTerminal()
    }
    function terminal() { Nvim.running ? Nvim.focusTerminal() : Nvim.launch(Notes.root) }

    // Boat views and zones from the keyboard.
    function setView(i) { if (i >= 0 && i < Boat.views.length) { mode = "boat"; boatShown = true; boatView = Boat.views[i].id } }
    function cycleView(d) {
        const i = Boat.views.findIndex(v => v.id === boatView)
        setView((i + d + Boat.views.length) % Boat.views.length)
    }
    function cycleZone(d) {
        mode = "boat"; boatShown = true
        const v = Boat.viewById(boatView)
        const cur = locInfo(location)
        let i = v.zones.findIndex(z => cur && z.path === cur.zone)
        i = i < 0 ? (d > 0 ? 0 : v.zones.length - 1) : (i + d + v.zones.length) % v.zones.length
        setLocation(v.zones[i].path)
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
        ["j / k", qsTr("next / previous note")], ["gg / G", qsTr("first / last note")],
        ["Enter / e", qsTr("edit note in Neovim")], ["o", qsTr("new note here")],
        ["- / h", qsTr("up a folder (back to the boat)")], ["J / K", qsTr("next / previous part of the boat")],
        ["1 2 3", qsTr("Outside / Deck / Below")], ["gt / gT", qsTr("next / previous view")],
        ["s", qsTr("Boat ↔ Systems")], ["/", qsTr("search")], ["p", qsTr("pin")], ["dd", qsTr("delete note")],
        ["a", qsTr("add a spot (then f / click to place)")], ["i", qsTr("insert readings into the note")],
        ["t", qsTr("open / focus Neovim")]
    ]
    function handleKey(seq) {
        switch (seq) {
        case "j": move(1); return true
        case "k": move(-1); return true
        case "gg": first(); return true
        case "G": last(); return true
        case "Enter": case "e": editCurrent(); return true
        case "o": newNote(); return true
        case "-": case "h": case "Backspace": up(); return true
        case "J": cycleZone(1); return true
        case "K": cycleZone(-1); return true
        case "1": setView(0); return true
        case "2": setView(1); return true
        case "3": setView(2); return true
        case "gt": cycleView(1); return true
        case "gT": cycleView(-1); return true
        case "s": mode = boatMode ? "systems" : "boat"; return true
        case "/": searchField.forceActiveFocus(); return true
        case "p": togglePin(); return true
        case "dd": deleteCurrent(); return true
        case "a": mode = "boat"; boatShown = true; boatCanvas.placing = true; return true
        case "i": insertReadings(); return true
        case "t": terminal(); return true
        case "Escape":
            if (boatCanvas.placing) { boatCanvas.placing = false; return true }
            if (boatMode && !boatShown) { boatShown = true; return true }
            return false
        }
        return false
    }
    // Keys that start a longer sequence here.
    readonly property var prefixes: ["g", "d"]

    // ---- pieces --------------------------------------------------------------

    // Styled combo box used for the system picker (compact layout).
    component SysCombo: ComboBox {
        id: combo
        implicitHeight: 32
        font.family: Theme.fontFamily
        font.pixelSize: 13
        background: Rectangle {
            radius: 16
            color: combo.hovered ? Theme.surfaceHi : "transparent"
            border.color: combo.activeFocus ? Theme.accent : Theme.border
        }
        contentItem: RowLayout {
            spacing: 6
            Item { width: 6 }
            Icon { name: page.sysIcon(combo.currentValue || ""); size: 14; color: Theme.accent }
            Text {
                Layout.fillWidth: true
                text: combo.displayText
                color: Theme.text
                font: combo.font
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
        }
        indicator: Icon {
            x: combo.width - width - 10; y: (combo.height - height) / 2
            name: "chevron"; size: 12; rotation: 90; color: Theme.textDim
        }
        delegate: ItemDelegate {
            id: d
            required property var modelData
            required property int index
            width: ListView.view.width
            highlighted: combo.highlightedIndex === index
            contentItem: Text {
                text: d.modelData.text !== undefined ? d.modelData.text : d.modelData
                color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 13
            }
            background: Rectangle { color: d.highlighted ? Theme.alpha(Theme.accent, 0.15) : "transparent"; radius: 8 }
        }
        popup: Popup {
            y: combo.height + 4
            width: Math.max(combo.width, 200)
            implicitHeight: Math.min(contentItem.implicitHeight + 12, 380)
            padding: 6
            contentItem: ListView {
                clip: true
                implicitHeight: contentHeight
                model: combo.popup.visible ? combo.delegateModel : null
                currentIndex: combo.highlightedIndex
            }
            background: Rectangle { color: Theme.surfaceHi; radius: 12; border.color: Theme.border }
        }
    }

    // New note: ask for a title, create the file, open it in Neovim.
    Popup {
        id: newPrompt
        parent: Overlay.overlay
        x: (parent.width - width) / 2
        y: parent.height * 0.25
        width: Math.min(440, parent.width - 40)
        padding: 18
        modal: true
        focus: true
        onOpened: { titleField.text = ""; titleField.forceActiveFocus() }
        background: Rectangle { color: Theme.surfaceHi; radius: 14; border.color: Theme.alpha(Theme.accent, 0.6) }
        Overlay.modal: Rectangle { color: Theme.alpha(Theme.bg, 0.55) }
        function commit() {
            const loc = page.boatMode ? page.location : ""
            const id = Notes.create(loc, titleField.text)
            close()
            if (!id) return
            page.select(id)
            page.editCurrent()
        }
        contentItem: Column {
            spacing: 10
            Text {
                text: page.boatMode && page.location ? qsTr("New note in %1").arg(page.locInfo(page.location).crumbs.join(" › "))
                                                     : qsTr("New note (top of the boat folder)")
                color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: 13
                width: parent.width; elide: Text.ElideRight
            }
            TextField {
                id: titleField
                width: parent.width
                placeholderText: qsTr("Title, e.g. Impeller change")
                placeholderTextColor: Theme.textFaint
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 16
                background: Rectangle { radius: 8; color: Theme.surface; border.color: titleField.activeFocus ? Theme.accent : Theme.border }
                onAccepted: newPrompt.commit()
            }
            Text {
                text: qsTr("Enter creates it and opens it in Neovim · Esc cancels")
                color: Theme.textFaint; font.family: Theme.fontFamily; font.pixelSize: 11
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        anchors.bottomMargin: 16
        spacing: Theme.gap

        // ---- Systems sidebar -------------------------------------------
        Rectangle {
            visible: !page.compact && !page.boatMode
            Layout.preferredWidth: 220
            Layout.fillHeight: true
            radius: Theme.radius
            color: Theme.surface
            border.color: Theme.border

            ListView {
                id: systemList
                anchors.fill: parent
                anchors.margins: 8
                clip: true
                spacing: 2
                model: [""].concat(Notes.systems)
                currentIndex: Math.max(0, model.indexOf(Notes.systemFilter))
                highlightMoveDuration: 260
                highlightMoveVelocity: -1
                highlight: Rectangle {
                    radius: 10
                    color: Theme.alpha(Theme.accent, 0.13)
                    border.color: Theme.alpha(Theme.accent, 0.3)
                }
                header: Text {
                    width: systemList.width
                    height: 34
                    leftPadding: 10
                    verticalAlignment: Text.AlignVCenter
                    text: qsTr("SYSTEMS")
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.letterSpacing: 1.6
                }
                delegate: Item {
                    id: sysRow
                    required property var modelData
                    required property int index
                    readonly property bool current: ListView.isCurrentItem
                    readonly property int n: (Notes.revision, Notes.countFor(modelData))
                    readonly property bool hintable: true
                    function hintActivate() { Notes.systemFilter = modelData }
                    width: systemList.width
                    height: 38
                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: sysHover.hovered && !sysRow.current ? Theme.surfaceHi : "transparent"
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 12
                        spacing: 10
                        Icon { name: page.sysIcon(sysRow.modelData); size: 16; color: sysRow.current ? Theme.accent : Theme.textDim }
                        Text {
                            Layout.fillWidth: true
                            text: sysRow.modelData === "" ? qsTr("All notes") : sysRow.modelData
                            color: sysRow.current ? Theme.text : Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.weight: sysRow.current ? Font.DemiBold : Font.Normal
                        }
                        Text {
                            text: sysRow.n
                            visible: sysRow.n > 0
                            color: Theme.textFaint
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }
                    }
                    HoverHandler { id: sysHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: sysRow.hintActivate() }
                }
            }
        }

        // ---- Note list -------------------------------------------------
        ColumnLayout {
            Layout.preferredWidth: page.compact ? 300 : 340
            Layout.maximumWidth: Layout.preferredWidth
            Layout.fillWidth: false
            Layout.fillHeight: true
            spacing: 10

            // Boat / Systems
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                radius: 18
                color: Theme.surface
                border.color: Theme.border
                Rectangle { // sliding highlight
                    x: 3 + (page.boatMode ? 0 : (parent.width - 6) / 2)
                    y: 3
                    width: (parent.width - 6) / 2
                    height: parent.height - 6
                    radius: height / 2
                    color: Theme.alpha(Theme.accent, 0.16)
                    border.color: Theme.alpha(Theme.accent, 0.5)
                    Behavior on x { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
                }
                Row {
                    anchors.fill: parent
                    Repeater {
                        model: [{ id: "boat", icon: "boat", label: qsTr("Boat") }, { id: "systems", icon: "list", label: qsTr("Systems") }]
                        Item {
                            id: modeItem
                            required property var modelData
                            readonly property bool on: page.mode === modelData.id
                            readonly property bool hintable: true
                            function hintActivate() { page.mode = modelData.id; page.boatShown = true }
                            width: parent.width / 2
                            height: parent.height
                            Row {
                                anchors.centerIn: parent
                                spacing: 7
                                Icon { name: modeItem.modelData.icon; size: 15; color: modeItem.on ? Theme.accent : Theme.textDim; anchors.verticalCenter: parent.verticalCenter }
                                Text {
                                    text: modeItem.modelData.label
                                    color: modeItem.on ? Theme.text : Theme.textDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.weight: modeItem.on ? Font.DemiBold : Font.Normal
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: modeItem.hintActivate() }
                        }
                    }
                }
            }

            // Where on the boat (boat mode): breadcrumb, spot rename / delete.
            Rectangle {
                id: whereBar
                visible: page.boatMode
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                radius: 12
                color: Theme.surface
                border.color: info ? Theme.alpha(Theme.accent, 0.45) : Theme.border
                readonly property var info: (Notes.revision, page.locInfo(page.location))
                property bool renaming: false
                property bool confirmDelete: false
                onInfoChanged: { renaming = false; confirmDelete = false }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 6
                    spacing: 6
                    Icon { name: whereBar.info && whereBar.info.depth >= 3 ? "pin" : "boat"; size: 16; color: whereBar.info ? Theme.accent : Theme.textDim }
                    Column {
                        Layout.fillWidth: true
                        visible: !whereBar.renaming
                        Text {
                            width: parent.width
                            text: whereBar.info ? whereBar.info.crumbs.slice(0, -1).join("  ›  ").toUpperCase() || Boat.name.toUpperCase()
                                                : Boat.name.toUpperCase()
                            color: Theme.textFaint
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.letterSpacing: 1.2
                        }
                        Text {
                            width: parent.width
                            text: whereBar.info ? whereBar.info.name : qsTr("Whole boat · %1 notes").arg(Notes.total)
                            color: Theme.text
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }
                    }
                    TextField {
                        id: renameField
                        visible: whereBar.renaming
                        Layout.fillWidth: true
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        background: Rectangle { radius: 8; color: Theme.surfaceHi; border.color: Theme.accent }
                        onAccepted: { page.setLocation(Notes.renameSpot(page.location, text)); whereBar.renaming = false }
                        Keys.onEscapePressed: whereBar.renaming = false
                    }
                    Chip {
                        visible: !!whereBar.info && whereBar.info.spot
                        compact: true
                        icon: whereBar.renaming ? "check" : "edit"
                        onClicked: {
                            if (whereBar.renaming) { renameField.accepted(); return }
                            renameField.text = whereBar.info.name
                            whereBar.renaming = true
                            renameField.forceActiveFocus()
                            renameField.selectAll()
                        }
                    }
                    Chip {
                        visible: !!whereBar.info && whereBar.info.spot && !whereBar.renaming
                        compact: true
                        icon: "trash"
                        text: whereBar.confirmDelete ? qsTr("Remove spot?") : ""
                        accent: Theme.danger
                        checked: whereBar.confirmDelete
                        onClicked: {
                            if (!whereBar.confirmDelete) { whereBar.confirmDelete = true; spotConfirm.restart(); return }
                            const parent = page.location.slice(0, page.location.lastIndexOf("/"))
                            Notes.removeSpot(page.location)      // its notes move up to the zone
                            page.setLocation(parent)
                        }
                        Timer { id: spotConfirm; interval: 3000; onTriggered: whereBar.confirmDelete = false }
                    }
                    Chip {
                        visible: !!whereBar.info && !whereBar.renaming
                        compact: true
                        icon: "back"
                        onClicked: page.up()
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    radius: 19
                    color: Theme.surface
                    border.color: searchField.activeFocus ? Theme.accent : Theme.border
                    Behavior on border.color { ColorAnimation { duration: Theme.fast } }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 8
                        Icon { name: "search"; size: 16; color: Theme.textDim }
                        TextField {
                            id: searchField
                            Layout.fillWidth: true
                            placeholderText: qsTr("Search, or #tag   ( / )")
                            placeholderTextColor: Theme.textFaint
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            background: null
                            text: Notes.search
                            onTextEdited: Notes.search = text
                            Keys.onReturnPressed: { Keyboard.release(); if (Notes.count) page.first() }
                        }
                    }
                }
                Rectangle {
                    id: newButton
                    Layout.preferredWidth: 38
                    Layout.preferredHeight: 38
                    radius: 19
                    gradient: Gradient {
                        GradientStop { position: 0; color: Theme.accent }
                        GradientStop { position: 1; color: Theme.accent2 }
                    }
                    scale: newTap.pressed ? 0.92 : newHover.hovered ? 1.06 : 1
                    Behavior on scale { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutBack } }
                    readonly property bool hintable: true
                    function hintActivate() { page.newNote() }
                    Icon { anchors.centerIn: parent; name: "plus"; size: 18; color: Theme.bg; stroke: 2.4 }
                    HoverHandler { id: newHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { id: newTap; onTapped: page.newNote() }
                    ToolTip.visible: newHover.hovered
                    ToolTip.text: qsTr("New note here (o)")
                    ToolTip.delay: 600
                }
            }

            SysCombo {
                visible: page.compact && !page.boatMode
                Layout.fillWidth: true
                textRole: "text"
                valueRole: "value"
                model: [{ text: qsTr("All notes"), value: "" }].concat(Notes.systems.map(s => ({ text: s, value: s })))
                currentIndex: Math.max(0, indexOfValue(Notes.systemFilter))
                onActivated: Notes.systemFilter = currentValue
            }

            ListView {
                id: noteList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 8
                model: Notes
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}

                add: Transition {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 260 }
                    NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: 320; easing.type: Easing.OutBack }
                }
                move: Transition { NumberAnimation { properties: "y"; duration: 380; easing.type: Easing.OutCubic } }
                displaced: Transition { NumberAnimation { properties: "y"; duration: 380; easing.type: Easing.OutCubic } }

                delegate: Rectangle {
                    id: noteCard
                    required property string noteId
                    required property string title
                    required property string system
                    required property var tags
                    required property bool pinned
                    required property var updated
                    required property string preview
                    required property string location
                    readonly property bool current: page.currentId === noteId
                    readonly property bool hintable: true
                    function hintActivate() { page.select(noteId) }
                    width: noteList.width
                    height: col.implicitHeight + 24
                    radius: 14
                    color: current ? Theme.alpha(Theme.accent, 0.10) : cardHover.hovered ? Theme.surfaceHi : Theme.surface
                    border.color: current ? Theme.alpha(Theme.accent, 0.55) : Theme.border
                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                    Behavior on border.color { ColorAnimation { duration: Theme.fast } }

                    Rectangle { // accent edge on the selected note
                        x: 0; y: 12; width: 3; height: parent.height - 24; radius: 2
                        color: Theme.accent
                        opacity: noteCard.current ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                    }

                    ColumnLayout {
                        id: col
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12; leftMargin: 14 }
                        spacing: 4
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Icon { visible: noteCard.pinned; name: "pin"; size: 13; color: Theme.warn }
                            Text {
                                Layout.fillWidth: true
                                text: noteCard.title
                                elide: Text.ElideRight
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: Units.relativeTime(noteCard.updated)
                                color: Theme.textFaint
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: noteCard.preview || qsTr("Empty note")
                            visible: text.length > 0
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                        }
                        Flow {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            spacing: 6
                            Chip { compact: true; text: noteCard.system; icon: page.sysIcon(noteCard.system); accent: Theme.accent; checked: true
                                   onClicked: { page.mode = "systems"; Notes.systemFilter = noteCard.system } }
                            Chip { compact: true; visible: noteCard.location !== ""; text: page.locLabel(noteCard.location)
                                   icon: noteCard.location.split("/").length >= 3 ? "pin" : "boat"; accent: Theme.accent2; checked: true
                                   onClicked: page.showOnBoat(noteCard.location) }
                            Repeater {
                                model: noteCard.tags
                                Chip { required property string modelData; compact: true; text: "#" + modelData
                                       onClicked: { Notes.search = "#" + modelData } }
                            }
                        }
                    }
                    HoverHandler { id: cardHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: page.select(noteCard.noteId)
                        onDoubleTapped: { page.select(noteCard.noteId); page.editCurrent() }
                    }
                }

                Column {
                    anchors.centerIn: parent
                    visible: noteList.count === 0
                    spacing: 10
                    Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "notes"; size: 40; color: Theme.textFaint; stroke: 1.4 }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Notes.search ? qsTr("No notes match")
                              : page.boatMode && page.location ? qsTr("Nothing filed here yet") : qsTr("No notes yet")
                        color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: 14
                    }
                    Chip { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("New note  (o)"); icon: "plus"; onClicked: page.newNote() }
                }
            }
        }

        // ---- Boat drawing / preview ---------------------------------------
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Rectangle {
                id: boatPanel
                anchors.fill: parent
                radius: Theme.radius
                color: Theme.surface
                border.color: Theme.border
                opacity: page.boatVisible ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                transform: Translate { x: page.boatVisible ? 0 : -24; Behavior on x { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } } }

                RowLayout {
                    id: boatBar
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                    spacing: 6
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
                        icon: "pin"
                        compact: page.compact
                        text: boatCanvas.placing ? qsTr("Tap the boat…") : page.compact ? "" : qsTr("Add spot")
                        accent: Theme.warn
                        checked: boatCanvas.placing
                        onClicked: boatCanvas.placing = !boatCanvas.placing
                    }
                    Chip {
                        icon: "data"
                        compact: page.compact
                        text: page.compact ? "" : qsTr("Neovim")
                        accent: Theme.good
                        checked: Nvim.running
                        onClicked: page.terminal()
                    }
                }

                BoatView {
                    id: boatCanvas
                    anchors { left: parent.left; right: parent.right; top: boatBar.bottom; bottom: parent.bottom; margins: 6 }
                    view: Boat.viewById(page.boatView) || Boat.views[0]
                    selection: page.location
                    onSelected: loc => page.setLocation(loc)
                    onSpotCreated: id => page.setLocation(id)
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
                    text: qsTr("f  hints  ·  J/K  parts of the boat  ·  1 2 3  views  ·  a  add spot  ·  ?  all keys")
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
            }

            // Read-only preview; editing happens in Neovim.
            Rectangle {
                id: preview
                anchors.fill: parent
                opacity: page.boatVisible ? 0 : 1
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                transform: Translate { x: page.boatVisible ? 24 : 0; Behavior on x { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } } }
                radius: Theme.radius
                color: Theme.surface
                border.color: Theme.border
                property bool confirmDelete: false

                Column {
                    anchors.centerIn: parent
                    visible: !page.current.noteId
                    spacing: 14
                    Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "boat"; size: 56; color: Theme.textFaint; stroke: 1.2 }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qsTr("Pick a note (j / k), or start one (o)")
                        color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: 16
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qsTr("%1 notes in %2").arg(Notes.total).arg(Notes.root)
                        color: Theme.textFaint; font.family: Theme.fontFamily; font.pixelSize: 12
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 12
                    visible: !!page.current.noteId

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Chip {
                            visible: page.boatMode
                            icon: "back"
                            text: qsTr("Boat")
                            accent: Theme.accent2
                            onClicked: page.boatShown = true
                        }
                        Text {
                            Layout.fillWidth: true
                            text: page.current.title || ""
                            elide: Text.ElideRight
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 24
                            font.weight: Font.DemiBold
                        }
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Chip { compact: true; text: page.current.system || ""; icon: page.sysIcon(page.current.system || ""); checked: true
                               onClicked: { page.mode = "systems"; Notes.systemFilter = page.current.system } }
                        Chip { compact: true; visible: !!page.current.location; text: (page.locInfo(page.current.location) || { crumbs: [] }).crumbs.join(" › ")
                               icon: "boat"; accent: Theme.accent2; checked: true; onClicked: page.showOnBoat(page.current.location) }
                        Repeater {
                            model: page.current.tags || []
                            Chip { required property string modelData; compact: true; text: "#" + modelData; onClicked: Notes.search = "#" + modelData }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Chip { icon: "edit"; text: qsTr("Edit in Neovim  e"); accent: Theme.good; checked: true; onClicked: page.editCurrent() }
                        Chip { icon: "pin"; text: page.current.pinned ? qsTr("Pinned") : qsTr("Pin  p"); checked: !!page.current.pinned; accent: Theme.warn; onClicked: page.togglePin() }
                        Chip { visible: !page.compact; icon: "gauge"; text: qsTr("Insert readings  i"); accent: Theme.accent2; onClicked: page.insertReadings() }
                        Item { Layout.fillWidth: true }
                        Chip {
                            icon: "trash"
                            text: preview.confirmDelete ? qsTr("Delete? dd") : ""
                            accent: Theme.danger
                            checked: preview.confirmDelete
                            onClicked: page.deleteCurrent()
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "boat/" + (page.current.noteId || "") + "  ·  " + qsTr("updated %1").arg(Units.relativeTime(page.current.updated))
                        color: Theme.textFaint
                        elide: Text.ElideMiddle
                        font.family: Theme.monoFamily
                        font.pixelSize: 11
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

                    Flickable {
                        id: previewFlick
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: rendered.implicitHeight + 20
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar {}
                        Text {
                            id: rendered
                            width: previewFlick.width - 12
                            text: page.current.body || ""
                            textFormat: Text.MarkdownText
                            wrapMode: Text.WordWrap
                            color: Theme.text
                            linkColor: Theme.accent2
                            font.family: Theme.fontFamily
                            font.pixelSize: 15
                            lineHeight: 1.15
                            onLinkActivated: link => Qt.openUrlExternally(link)
                        }
                        TapHandler { onDoubleTapped: page.editCurrent() }
                    }
                }
            }
        }
    }
}
