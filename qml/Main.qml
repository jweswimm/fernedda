import QtQuick
import QtQuick.Window
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
            id: notesPage
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

    // ---- Keyboard: vim-style normal mode ---------------------------------
    //   f      hints: label everything clickable, type the label to click it
    //   ?      all keys          H / L   previous / next page
    // Page-specific keys come from the page's handleKey(seq); multi-key
    // sequences (gg, dd, gt) are collected here.
    Component.onCompleted: Keyboard.attach(window)
    property string pending: ""
    Timer { id: pendingTimer; interval: 900; onTriggered: window.pending = "" }
    Connections {
        target: Keyboard
        function onKey(token) { if (window.handleKey(token)) Keyboard.accept() }
        function onSwitchPane() { window.pageIndex = 2; notesPage.switchPane() }
        function onTogglePane() {
            if (window.pageIndex === 2) { notesPage.togglePane(); return }
            window.pageIndex = 2            // it lives on Notes: go there and show it
            notesPage.focusEditor()
        }
    }
    // Neovim closes with the app, and may have unsaved notes to ask about first.
    onClosing: close => close.accepted = Nvim.requestQuit()
    Connections {
        target: Nvim
        function onAttention() { window.pageIndex = 2; notesPage.focusEditor() }
    }
    function currentPage() { return window.pageIndex === 2 ? notesPage : null }
    function handleKey(t) {
        if (hints.active) return hints.key(t)
        if (help.shown) { if (t === "Escape" || t === "?" || t === "q") { help.shown = false; return true } }
        if (detail.isOpen && t === "Escape") return false          // its own shortcut closes it
        const seq = pending + t
        const hadPending = pending !== ""
        pending = ""
        pendingTimer.stop()
        if (seq === "f") { hints.start(); return true }
        if (seq === "?") { help.shown = !help.shown; return true }
        const page = currentPage()
        if (page && page.handleKey(seq)) return true
        if (seq === "H") { pageIndex = (pageIndex + pages.length - 1) % pages.length; return true }
        if (seq === "L") { pageIndex = (pageIndex + 1) % pages.length; return true }
        if (page && page.prefixes.includes(seq)) { pending = seq; pendingTimer.restart(); return true }
        if (hadPending) return handleKey(t)                         // "gx" isn't a thing: try "x"
        return false
    }

    // Mode line: insert mode and any half-typed sequence.
    Rectangle {
        anchors { left: parent.left; bottom: parent.bottom; margins: 10 }
        z: 900
        visible: Keyboard.insertMode || Keyboard.editorMode || window.pending !== "" || hints.active
        width: modeText.implicitWidth + 18
        height: 24
        radius: 6
        color: Theme.surfaceHi
        border.color: Theme.alpha(Keyboard.insertMode ? Theme.good : Theme.accent, 0.6)
        Text {
            id: modeText
            anchors.centerIn: parent
            text: hints.active ? qsTr("-- HINT --  %1").arg(hints.typed)
                  : Keyboard.insertMode ? qsTr("-- INSERT --  Esc to leave")
                  : Keyboard.editorMode ? qsTr("-- NEOVIM --  Alt+Tab to leave") : window.pending
            color: Keyboard.insertMode ? Theme.good : Theme.accent
            font.family: Theme.monoFamily
            font.pixelSize: 12
        }
    }

    // ---- Hint mode ---------------------------------------------------------
    Item {
        id: hints
        anchors.fill: parent
        z: 1000
        property bool active: false
        property string typed: ""
        property var targets: []
        readonly property string alphabet: "asdfghjkl"

        function start() {
            const found = collect()
            if (!found.length) return
            const n = alphabet.length
            const len = found.length <= n ? 1 : found.length <= n * n ? 2 : 3
            for (let i = 0; i < found.length; ++i) {
                let label = "", k = i
                for (let d = 0; d < len; ++d) { label = alphabet[k % n] + label; k = Math.floor(k / n) }
                found[i].label = label
            }
            typed = ""
            targets = found
            active = true
        }
        function stop() { active = false; targets = []; typed = "" }
        function key(t) {
            if (t === "Escape" || t === "f" && typed === "") { stop(); return true }
            if (t === "Backspace") { typed = typed.slice(0, -1); return true }
            if (t.length !== 1 || !alphabet.includes(t)) return true
            typed += t
            const left = targets.filter(h => h.label.startsWith(typed))
            if (left.length === 0) { stop(); return true }
            if (left.length === 1 && left[0].label === typed) {
                const hit = left[0]
                stop()
                Qt.callLater(hit.activate)
            }
            return true
        }

        // Everything on screen that can be clicked: items with hintable +
        // hintActivate(), text fields, and hintTargets() from the boat drawing.
        function collect() {
            const out = []
            const W = window.width, Hh = window.height
            function clipTo(a, b) {
                const x = Math.max(a.x, b.x), y = Math.max(a.y, b.y)
                return { x: x, y: y, w: Math.min(a.x + a.w, b.x + b.width) - x, h: Math.min(a.y + a.h, b.y + b.height) - y }
            }
            function inside(c, x, y) { return x >= c.x && y >= c.y && x <= c.x + c.w && y <= c.y + c.h }
            function add(c, x, y, fn) {
                if (inside(c, x, y)) out.push({ x: Math.max(c.x, x), y: Math.max(c.y, y), activate: fn })
            }
            function walk(item, c, op) {
                if (!item || !item.visible || item === hints) return
                op *= item.opacity
                if (op < 0.05) return
                const r = item.mapToItem(null, 0, 0, item.width, item.height)
                if (item.clip) {
                    c = clipTo(c, r)
                    if (c.w <= 0 || c.h <= 0) return
                }
                if (item.hintable === true && typeof item.hintActivate === "function") {
                    const it = item
                    add(c, r.x + Math.min(6, r.width / 2), r.y + Math.min(6, r.height / 2), () => it.hintActivate())
                } else if (item.placeholderText !== undefined && item.activeFocusOnPress !== undefined && item.width > 0) {
                    const it = item
                    add(c, r.x + 4, r.y + Math.min(6, r.height / 2), () => it.forceActiveFocus())
                }
                if (typeof item.hintTargets === "function") {
                    for (const t of item.hintTargets()) {
                        const p = item.mapToItem(null, t.x, t.y)
                        add(c, p.x, p.y, t.activate)
                    }
                }
                for (let i = 0; i < item.children.length; ++i) walk(item.children[i], c, op)
            }
            walk(window.contentItem, { x: 0, y: 0, w: W, h: Hh }, 1)
            return out
        }

        Repeater {
            model: hints.active ? hints.targets : []
            Rectangle {
                required property var modelData
                readonly property bool live: modelData.label.startsWith(hints.typed)
                visible: live
                x: Math.min(hints.width - width, Math.max(0, modelData.x - 4))
                y: Math.min(hints.height - height, Math.max(0, modelData.y - 4))
                width: hintRow.implicitWidth + 8
                height: 18
                radius: 4
                color: Theme.warn
                border.color: Theme.alpha(Theme.bg, 0.6)
                Row {
                    id: hintRow
                    anchors.centerIn: parent
                    Text { text: hints.typed; color: Theme.alpha(Theme.bg, 0.45); font.family: Theme.monoFamily; font.pixelSize: 12; font.weight: Font.Bold }
                    Text { text: parent.parent.modelData.label.slice(hints.typed.length); color: Theme.bg; font.family: Theme.monoFamily; font.pixelSize: 12; font.weight: Font.Bold }
                }
            }
        }
    }

    // ---- Key help (?) ------------------------------------------------------
    Rectangle {
        id: help
        property bool shown: false
        z: 950
        anchors.centerIn: parent
        width: Math.min(620, parent.width - 40)
        height: helpCol.implicitHeight + 40
        radius: 16
        color: Theme.surfaceHi
        border.color: Theme.alpha(Theme.accent, 0.6)
        opacity: shown ? 1 : 0
        visible: opacity > 0
        scale: shown ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        readonly property var globalKeys: [
            ["f", qsTr("hints: type a label to click it")], ["?", qsTr("this help")],
            ["H / L", qsTr("previous / next page (views on Notes)")], ["Esc", qsTr("back / leave a text field")],
            ["Alt+Tab", qsTr("switch between Neovim and the app (or Ctrl+;)")],
            ["Ctrl+T", qsTr("show / hide the Neovim pane")],
            ["Ctrl+1…4", qsTr("go to page")], ["F11", qsTr("full screen")]
        ]
        Column {
            id: helpCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
            spacing: 6
            Repeater {
                model: [{ title: qsTr("Everywhere"), keys: help.globalKeys }]
                    .concat(window.currentPage() ? [{ title: window.pages[window.pageIndex].label, keys: window.currentPage().keymap }] : [])
                Column {
                    required property var modelData
                    width: helpCol.width
                    spacing: 4
                    Text {
                        text: parent.modelData.title.toUpperCase()
                        color: Theme.textFaint; font.family: Theme.fontFamily; font.pixelSize: 11; font.letterSpacing: 1.4
                        topPadding: 6
                    }
                    Grid {
                        columns: 2
                        columnSpacing: 18
                        rowSpacing: 4
                        Repeater {
                            model: parent.parent.modelData.keys.length * 2
                            Text {
                                required property int index
                                readonly property var row: parent.parent.modelData.keys[Math.floor(index / 2)]
                                text: index % 2 === 0 ? row[0] : row[1]
                                color: index % 2 === 0 ? Theme.accent : Theme.textDim
                                font.family: index % 2 === 0 ? Theme.monoFamily : Theme.fontFamily
                                font.pixelSize: 13
                            }
                        }
                    }
                }
            }
        }
    }
}
