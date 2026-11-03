import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtCore
import Fernedda
import "BoatS235C.js" as Boat

// Notes, organised two ways:
//   Boat    — list | boat drawing. Tap a part of the boat to see and file
//             notes there; opening a note swaps the drawing for the editor.
//   Systems — systems | list | editor.
// Edits save automatically shortly after you stop typing.
Page {
    id: page
    title: qsTr("Notes")

    property string currentId: ""
    property string mode: "boat"          // "boat" | "systems"
    property string boatView: "outside"
    property string location: ""          // remembered boat selection
    property bool boatShown: true         // boat mode: drawing (true) or editor
    // Reopen the note you were on last time.
    Settings {
        category: "notes"
        property alias current: page.currentId
        property alias mode: page.mode
        property alias boatView: page.boatView
        property alias boatLocation: page.location
    }
    Component.onCompleted: {
        if (currentId && !Notes.get(currentId).noteId) currentId = ""
        if (location && !locInfo(location)) location = ""
        applyMode()
        boatShown = true
        Qt.callLater(editor.load)
    }
    readonly property bool compact: width < 1000
    readonly property bool boatMode: mode === "boat"
    readonly property bool boatVisible: boatMode && boatShown

    function applyMode() {
        if (boatMode) { Notes.systemFilter = ""; Notes.locationFilter = location }
        else Notes.locationFilter = ""
    }
    onModeChanged: applyMode()
    function setLocation(loc) { location = loc; Notes.locationFilter = loc }

    // Location = boat zone id or spot id. Returns { name, zone, view, system, spot } or null.
    function locInfo(loc) {
        if (!loc) return null
        const z = Boat.zoneById[loc]
        if (z) return { name: z.name, zone: z.id, view: z.view, system: z.system, spot: false }
        const sp = Notes.spots.find(x => x.spotId === loc)
        if (!sp) return null
        const sz = Boat.zoneById[sp.zone]
        return { name: sp.name, zone: sp.zone, view: sp.view, system: sz ? sz.system : "", spot: true }
    }
    function locLabel(loc) { const i = locInfo(loc); return i ? i.name : "" }
    // Jump to a location on the drawing.
    function showOnBoat(loc) {
        editor.flush()
        mode = "boat"
        const i = locInfo(loc)
        if (i) boatView = i.view
        setLocation(loc)
        boatShown = true
    }
    // Choices for the editor's location picker.
    readonly property var locationChoices: {
        const out = [{ text: qsTr("Not on the boat"), value: "", icon: "note" }]
        for (const v of Boat.views)
            for (const z of v.zones) {
                out.push({ text: v.label + " · " + z.name, value: z.id, icon: "boat" })
                for (const sp of Notes.spots)
                    if (sp.zone === z.id) out.push({ text: "      " + sp.name, value: sp.spotId, icon: "pin" })
            }
        for (const sp of Notes.spots)
            if (!Boat.zoneById[sp.zone]) out.push({ text: Boat.viewLabel(sp.view) + " · " + sp.name, value: sp.spotId, icon: "pin" })
        return out
    }

    function sysIcon(s) {
        return ({ "": "list", Engine: "engine", Electrical: "bolt", Rigging: "rigging", Sails: "sail",
                  "Hull & Deck": "hull", Plumbing: "drop", Navigation: "compass", Safety: "lifebuoy",
                  Interior: "home", General: "note" })[s] || "tag"
    }

    function newNote() {
        const loc = boatMode ? Notes.locationFilter : ""
        const info = locInfo(loc)
        const id = Notes.create(boatMode ? (info ? info.system : "") : Notes.systemFilter, loc)
        Notes.search = ""
        select(id)
        editor.focusTitle()
    }
    function select(id) {
        if (boatMode) boatShown = false
        if (id === currentId) return
        editor.flush()
        currentId = id
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

    // Styled combo box used for the system picker.
    component SysCombo: ComboBox {
        id: combo
        property var iconFor: page.sysIcon
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
            Icon { name: combo.iconFor(combo.currentValue || ""); size: 14; color: Theme.accent }
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
            contentItem: RowLayout {
                spacing: 8
                Icon { name: combo.iconFor(d.modelData.value !== undefined ? d.modelData.value : d.modelData); size: 14; color: Theme.textDim }
                Text {
                    Layout.fillWidth: true
                    text: d.modelData.text !== undefined ? d.modelData.text : d.modelData
                    color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 13
                }
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
                ScrollIndicator.vertical: ScrollIndicator {}
            }
            background: Rectangle { color: Theme.surfaceHi; radius: 12; border.color: Theme.border }
            enter: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140 }
                NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 180; easing.type: Easing.OutCubic }
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
                    readonly property int n: (Notes.total, Notes.countFor(modelData))
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
                    TapHandler { onTapped: Notes.systemFilter = sysRow.modelData }
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
                            required property var modelData
                            readonly property bool on: page.mode === modelData.id
                            width: parent.width / 2
                            height: parent.height
                            Row {
                                anchors.centerIn: parent
                                spacing: 7
                                Icon { name: parent.parent.modelData.icon; size: 15; color: parent.parent.on ? Theme.accent : Theme.textDim; anchors.verticalCenter: parent.verticalCenter }
                                Text {
                                    text: parent.parent.modelData.label
                                    color: parent.parent.on ? Theme.text : Theme.textDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.weight: parent.parent.on ? Font.DemiBold : Font.Normal
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { editor.flush(); page.mode = parent.modelData.id; page.boatShown = true } }
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
                readonly property var info: page.locInfo(Notes.locationFilter)
                property bool renaming: false
                property bool confirmDelete: false
                onInfoChanged: { renaming = false; confirmDelete = false }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 6
                    spacing: 6
                    Icon { name: whereBar.info && whereBar.info.spot ? "pin" : "boat"; size: 16; color: whereBar.info ? Theme.accent : Theme.textDim }
                    Column {
                        Layout.fillWidth: true
                        visible: !whereBar.renaming
                        Text {
                            width: parent.width
                            text: whereBar.info ? Boat.viewLabel(whereBar.info.view).toUpperCase()
                                                  + (whereBar.info.spot && Boat.zoneById[whereBar.info.zone] ? "  ›  " + Boat.zoneById[whereBar.info.zone].name.toUpperCase() : "")
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
                        onAccepted: { Notes.updateSpot(Notes.locationFilter, { name: text }); whereBar.renaming = false }
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
                            const id = Notes.locationFilter
                            Notes.removeSpot(id)       // its notes move up to the zone
                            page.setLocation(Notes.locationFilter)
                        }
                        Timer { id: spotConfirm; interval: 3000; onTriggered: whereBar.confirmDelete = false }
                    }
                    Chip {
                        visible: !!whereBar.info && !whereBar.renaming
                        compact: true
                        icon: "close"
                        onClicked: page.setLocation(whereBar.info.spot ? whereBar.info.zone : "")
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
                            placeholderText: qsTr("Search, or #tag")
                            placeholderTextColor: Theme.textFaint
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            background: null
                            text: Notes.search
                            onTextEdited: Notes.search = text
                        }
                    }
                }
                Rectangle {
                    Layout.preferredWidth: 38
                    Layout.preferredHeight: 38
                    radius: 19
                    gradient: Gradient {
                        GradientStop { position: 0; color: Theme.accent }
                        GradientStop { position: 1; color: Theme.accent2 }
                    }
                    scale: newTap.pressed ? 0.92 : newHover.hovered ? 1.06 : 1
                    Behavior on scale { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutBack } }
                    Icon { anchors.centerIn: parent; name: "plus"; size: 18; color: Theme.bg; stroke: 2.4 }
                    HoverHandler { id: newHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { id: newTap; onTapped: page.newNote() }
                    ToolTip.visible: newHover.hovered
                    ToolTip.text: qsTr("New note (Ctrl+N)")
                    ToolTip.delay: 600
                }
            }
            Shortcut { sequences: [StandardKey.New]; enabled: page.active; onActivated: page.newNote() }
            Shortcut { sequences: [StandardKey.Find]; enabled: page.active; onActivated: searchField.forceActiveFocus() }

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
                remove: Transition {
                    NumberAnimation { property: "opacity"; to: 0; duration: 200 }
                    NumberAnimation { property: "x"; to: -40; duration: 200 }
                }
                move: Transition { NumberAnimation { properties: "y"; duration: 380; easing.type: Easing.OutCubic } }
                displaced: Transition { NumberAnimation { properties: "y"; duration: 380; easing.type: Easing.OutCubic } }
                populate: Transition {
                    id: pop
                    SequentialAnimation {
                        PropertyAction { property: "opacity"; value: 0 }
                        PauseAnimation { duration: pop.ViewTransition.index * 40 }
                        ParallelAnimation {
                            NumberAnimation { property: "opacity"; to: 1; duration: 260 }
                            NumberAnimation { property: "y"; from: pop.ViewTransition.destination.y + 16; duration: 360; easing.type: Easing.OutCubic }
                        }
                    }
                }

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
                            Chip { compact: true; visible: text.length > 0; text: (Notes.spots, page.locLabel(noteCard.location))
                                   icon: Boat.zoneById[noteCard.location] ? "boat" : "pin"; accent: Theme.accent2; checked: true
                                   onClicked: page.showOnBoat(noteCard.location) }
                            Repeater {
                                model: noteCard.tags
                                Chip { required property string modelData; compact: true; text: "#" + modelData
                                       onClicked: { Notes.search = "#" + modelData } }
                            }
                        }
                    }
                    HoverHandler { id: cardHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: page.select(noteCard.noteId) }
                }

                Column {
                    anchors.centerIn: parent
                    visible: noteList.count === 0
                    spacing: 10
                    Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "notes"; size: 40; color: Theme.textFaint; stroke: 1.4 }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Notes.search ? qsTr("No notes match")
                          : page.boatMode && Notes.locationFilter ? qsTr("Nothing filed here yet") : qsTr("No notes here yet")
                        color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: 14
                    }
                    Chip { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("New note"); icon: "plus"; onClicked: page.newNote() }
                }
            }
        }

        // ---- Boat drawing / editor ---------------------------------------
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
                            compact: page.compact
                            text: modelData.label
                            icon: ({ outside: "boat", deck: "hull", below: "home" })[modelData.id] || "boat"
                            checked: page.boatView === modelData.id
                            onClicked: page.boatView = modelData.id
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
                }

                BoatView {
                    id: boatCanvas
                    anchors { left: parent.left; right: parent.right; top: boatBar.bottom; bottom: parent.bottom; margins: 6 }
                    view: Boat.views.find(v => v.id === page.boatView) || Boat.views[0]
                    selection: Notes.locationFilter
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
                    text: qsTr("Tap a part to file notes there · double-tap or long-press to drop a spot · drag spots to move them")
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
            }

            // ---- Editor ----------------------------------------------------
            Rectangle {
                id: editor
                anchors.fill: parent
                opacity: page.boatVisible ? 0 : 1
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                transform: Translate { x: page.boatVisible ? 24 : 0; Behavior on x { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } } }
                radius: Theme.radius
                color: Theme.surface
                border.color: Theme.border

                property var note: ({})
                property bool loading: false
                property bool preview: false
                property bool dirty: false
                property string savedAt: ""
                property bool confirmDelete: false
                property string locValue: ""

                function load() {
                    loading = true
                    note = page.currentId ? Notes.get(page.currentId) : ({})
                    titleField.text = note.title || ""
                    body.text = note.body || ""
                    tagsField.text = (note.tags || []).join(", ")
                    systemBox.currentIndex = Math.max(0, systemBox.indexOfValue(note.system || "General"))
                    locValue = note.location || ""
                    preview = page.currentId !== "" && (note.body || "").length > 0
                    dirty = false
                    savedAt = ""
                    confirmDelete = false
                    loading = false
                    switchAnim.restart()
                }
                function changed() { if (!loading && page.currentId) { dirty = true; saveTimer.restart() } }
                function flush() {
                    if (!dirty || !page.currentId) return
                    saveTimer.stop()
                    Notes.save(page.currentId, { title: titleField.text || qsTr("Untitled note"), body: body.text,
                                                 tags: tagsField.text, system: systemBox.currentValue,
                                                 location: locValue })
                    dirty = false
                    savedAt = new Date().toLocaleTimeString(Qt.locale(), "HH:mm")
                }
                function focusTitle() { preview = false; titleField.forceActiveFocus(); titleField.selectAll() }

                Connections {
                    target: page
                    function onCurrentIdChanged() {
                        editor.load()
                        if (!page.currentId && page.boatMode) page.boatShown = true
                    }
                }
                Timer { id: saveTimer; interval: 700; onTriggered: editor.flush() }

                SequentialAnimation {
                    id: switchAnim
                    PropertyAction { target: editorBody; property: "opacity"; value: 0 }
                    PropertyAction { target: editorShift; property: "x"; value: 18 }
                    ParallelAnimation {
                        NumberAnimation { target: editorBody; property: "opacity"; to: 1; duration: 260 }
                        NumberAnimation { target: editorShift; property: "x"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                    }
                }

                // Empty state
                Column {
                    anchors.centerIn: parent
                    visible: page.currentId === ""
                    spacing: 14
                    Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "boat"; size: 56; color: Theme.textFaint; stroke: 1.2 }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qsTr("Pick a note, or start a new one")
                        color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: 16
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qsTr("%1 notes · saved as Markdown in %2").arg(Notes.total).arg(Notes.folder)
                        color: Theme.textFaint; font.family: Theme.fontFamily; font.pixelSize: 12
                    }
                }

                ColumnLayout {
                    id: editorBody
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 12
                    visible: page.currentId !== ""
                    transform: Translate { id: editorShift }

                    TextField {
                        id: titleField
                        Layout.fillWidth: true
                        placeholderText: qsTr("Title")
                        placeholderTextColor: Theme.textFaint
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 26
                        font.weight: Font.DemiBold
                        background: null
                        leftPadding: 0
                        onTextEdited: editor.changed()
                        Keys.onReturnPressed: { editor.preview = false; body.forceActiveFocus() }
                    }

                    // Meta: system and place on the boat; then tags, pin, delete.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        SysCombo {
                            id: systemBox
                            Layout.preferredWidth: 170
                            model: Notes.systems
                            onActivated: editor.changed()
                        }
                        SysCombo {
                            id: locBox
                            Layout.fillWidth: true
                            Layout.minimumWidth: 120
                            textRole: "text"
                            valueRole: "value"
                            model: page.locationChoices
                            iconFor: v => (page.locationChoices.find(c => c.value === v) || { icon: "note" }).icon
                            displayText: editor.locValue ? page.locLabel(editor.locValue) : qsTr("Not on the boat")
                            currentIndex: page.locationChoices.findIndex(c => c.value === editor.locValue)
                            onActivated: index => {
                                editor.locValue = page.locationChoices[index].value
                                currentIndex = Qt.binding(() => page.locationChoices.findIndex(c => c.value === editor.locValue))
                                editor.changed()
                            }
                        }
                        Chip {
                            visible: editor.locValue !== ""
                            icon: "boat"
                            compact: true
                            accent: Theme.accent2
                            onClicked: page.showOnBoat(editor.locValue)
                            ToolTip.visible: showHover.hovered
                            ToolTip.text: qsTr("Show on the boat")
                            ToolTip.delay: 600
                            HoverHandler { id: showHover }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            radius: 16
                            color: "transparent"
                            border.color: tagsField.activeFocus ? Theme.accent : Theme.border
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 8
                                Icon { name: "tag"; size: 14; color: Theme.textDim }
                                TextField {
                                    id: tagsField
                                    Layout.fillWidth: true
                                    placeholderText: qsTr("tags, comma separated")
                                    placeholderTextColor: Theme.textFaint
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    background: null
                                    onTextEdited: editor.changed()
                                }
                            }
                        }
                        Chip {
                            icon: "pin"
                            text: editor.note.pinned ? qsTr("Pinned") : qsTr("Pin")
                            checked: !!editor.note.pinned
                            accent: Theme.warn
                            onClicked: {
                                editor.flush()
                                Notes.save(page.currentId, { pinned: !editor.note.pinned })
                                editor.note = Notes.get(page.currentId)
                            }
                        }
                        Chip {
                            icon: "trash"
                            text: editor.confirmDelete ? qsTr("Delete?") : ""
                            accent: Theme.danger
                            checked: editor.confirmDelete
                            onClicked: {
                                if (!editor.confirmDelete) { editor.confirmDelete = true; confirmTimer.restart(); return }
                                const id = page.currentId
                                editor.dirty = false
                                page.currentId = ""
                                Notes.remove(id)
                            }
                            Timer { id: confirmTimer; interval: 3000; onTriggered: editor.confirmDelete = false }
                        }
                    }

                    // Toolbar
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Chip {
                            visible: page.boatMode
                            icon: "back"
                            text: qsTr("Boat")
                            accent: Theme.accent2
                            onClicked: { editor.flush(); page.boatShown = true }
                        }
                        Row {
                            spacing: 0
                            Chip { text: qsTr("Edit"); icon: "edit"; checked: !editor.preview; onClicked: { editor.preview = false; body.forceActiveFocus() } }
                            Item { width: 6; height: 1 }
                            Chip { text: qsTr("Preview"); icon: "eye"; checked: editor.preview; onClicked: { editor.flush(); editor.preview = true } }
                        }
                        Item { width: 8 }
                        Chip {
                            text: qsTr("Insert readings")
                            icon: "gauge"
                            accent: Theme.accent2
                            onClicked: {
                                editor.preview = false
                                body.insert(body.cursorPosition, page.readingsMarkdown())
                                body.forceActiveFocus()
                            }
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: editor.dirty ? qsTr("Editing…") : editor.savedAt ? qsTr("Saved %1").arg(editor.savedAt)
                                  : editor.note.updated ? qsTr("Updated %1").arg(Units.relativeTime(editor.note.updated)) : ""
                            color: editor.dirty ? Theme.textDim : Theme.textFaint
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

                    // Body: editor and rendered preview cross-fade.
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ScrollView {
                            id: editScroll
                            anchors.fill: parent
                            opacity: editor.preview ? 0 : 1
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: 220 } }
                            TextArea {
                                id: body
                                wrapMode: TextEdit.Wrap
                                color: Theme.text
                                selectionColor: Theme.alpha(Theme.accent, 0.35)
                                selectedTextColor: Theme.text
                                font.family: Theme.monoFamily
                                font.pixelSize: 14
                                placeholderText: qsTr("Write in Markdown…  # heading, **bold**, - [ ] checklist")
                                placeholderTextColor: Theme.textFaint
                                background: null
                                leftPadding: 0
                                onTextChanged: editor.changed()
                            }
                        }

                        Flickable {
                            id: previewFlick
                            anchors.fill: parent
                            opacity: editor.preview ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: 220 } }
                            contentHeight: rendered.implicitHeight + 20
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar {}
                            Text {
                                id: rendered
                                width: previewFlick.width - 12
                                text: body.text
                                textFormat: Text.MarkdownText
                                wrapMode: Text.WordWrap
                                color: Theme.text
                                linkColor: Theme.accent2
                                font.family: Theme.fontFamily
                                font.pixelSize: 15
                                lineHeight: 1.15
                                onLinkActivated: link => Qt.openUrlExternally(link)
                            }
                            TapHandler { onDoubleTapped: { editor.preview = false; body.forceActiveFocus() } }
                        }
                    }
                }
            }
        }
    }

    onActiveChanged: if (!active) editor.flush()
    Shortcut { sequence: "Escape"; enabled: page.active && page.boatMode && !page.boatShown; onActivated: { editor.flush(); page.boatShown = true } }
}
