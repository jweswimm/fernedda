pragma Singleton
import QtQuick

// Colors, type and motion for the whole app. Three modes:
//   night — gruvbox dark (hard contrast, to match Neovim), the default
//   day   — gruvbox light, for bright cockpits
//   red   — night-vision red on black, keeps your dark adaptation on watch
// Every color animates when the mode changes.
QtObject {
    id: theme

    property string mode: "night"
    readonly property bool dark: mode !== "day"

    function cycle() {
        mode = mode === "night" ? "red" : mode === "red" ? "day" : "night"
    }

    readonly property var palettes: ({
        night: {
            bg: "#1d2021", bg2: "#1d2021", surface: "#282828", surfaceHi: "#3c3836",
            border: "#504945", text: "#ebdbb2", textDim: "#a89984", textFaint: "#7c6f64",
            accent: "#fabd2f", accent2: "#83a598", warn: "#fe8019", danger: "#fb4934", good: "#b8bb26",
            port: "#fb4934", starboard: "#b8bb26",
            speed: "#83a598", wind: "#8ec07c", depth: "#d3869b", power: "#b8bb26",
            engine: "#fe8019", env: "#d79921"
        },
        day: {
            bg: "#fbf1c7", bg2: "#f2e5bc", surface: "#f9f5d7", surfaceHi: "#f2e5bc",
            border: "#d5c4a1", text: "#3c3836", textDim: "#665c54", textFaint: "#a89984",
            accent: "#b57614", accent2: "#076678", warn: "#af3a03", danger: "#9d0006", good: "#79740e",
            port: "#9d0006", starboard: "#79740e",
            speed: "#076678", wind: "#427b58", depth: "#8f3f71", power: "#79740e",
            engine: "#af3a03", env: "#b57614"
        },
        red: {
            bg: "#050000", bg2: "#0b0101", surface: "#140303", surfaceHi: "#1c0505",
            border: "#2e0808", text: "#ff4a3d", textDim: "#b3271f", textFaint: "#5c1410",
            accent: "#ff3b2f", accent2: "#e0352a", warn: "#ff6a3d", danger: "#ff2a1f", good: "#d63a2a",
            port: "#ff3b2f", starboard: "#a3241b",
            speed: "#ff4a3d", wind: "#ff3b2f", depth: "#d63a2a", power: "#e0352a",
            engine: "#ff6a3d", env: "#c2281f"
        }
    })
    readonly property var p: palettes[mode]

    property color bg: p.bg
    property color bg2: p.bg2
    property color surface: p.surface
    property color surfaceHi: p.surfaceHi
    property color border: p.border
    property color text: p.text
    property color textDim: p.textDim
    property color textFaint: p.textFaint
    property color accent: p.accent
    property color accent2: p.accent2
    property color warn: p.warn
    property color danger: p.danger
    property color good: p.good
    property color port: p.port
    property color starboard: p.starboard
    property color speed: p.speed
    property color wind: p.wind
    property color depth: p.depth
    property color power: p.power
    property color engine: p.engine
    property color env: p.env

    readonly property int colorMs: 600
    Behavior on bg { ColorAnimation { duration: theme.colorMs } }
    Behavior on bg2 { ColorAnimation { duration: theme.colorMs } }
    Behavior on surface { ColorAnimation { duration: theme.colorMs } }
    Behavior on surfaceHi { ColorAnimation { duration: theme.colorMs } }
    Behavior on border { ColorAnimation { duration: theme.colorMs } }
    Behavior on text { ColorAnimation { duration: theme.colorMs } }
    Behavior on textDim { ColorAnimation { duration: theme.colorMs } }
    Behavior on textFaint { ColorAnimation { duration: theme.colorMs } }
    Behavior on accent { ColorAnimation { duration: theme.colorMs } }
    Behavior on accent2 { ColorAnimation { duration: theme.colorMs } }
    Behavior on speed { ColorAnimation { duration: theme.colorMs } }
    Behavior on wind { ColorAnimation { duration: theme.colorMs } }
    Behavior on depth { ColorAnimation { duration: theme.colorMs } }
    Behavior on power { ColorAnimation { duration: theme.colorMs } }
    Behavior on engine { ColorAnimation { duration: theme.colorMs } }
    Behavior on env { ColorAnimation { duration: theme.colorMs } }

    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    // Type
    readonly property string fontFamily: "Noto Sans"
    readonly property string monoFamily: "Adwaita Mono"
    readonly property int radius: 16
    readonly property int gap: 14

    // Motion
    readonly property int fast: 160
    readonly property int normal: 320
    readonly property int slow: 560
}
