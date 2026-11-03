pragma Singleton
import QtQuick

// Colors, type and motion for the whole app. Three modes:
//   night — deep navy, the default
//   day   — light, for bright cockpits
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
            bg: "#070d18", bg2: "#0c1626", surface: "#111c2e", surfaceHi: "#172539",
            border: "#1f3048", text: "#e6eef8", textDim: "#8ea3bd", textFaint: "#4f6380",
            accent: "#3dd6c6", accent2: "#5aa9ff", warn: "#f5b041", danger: "#ff6b6b", good: "#5ee38a",
            port: "#ff5a63", starboard: "#3ddc84",
            speed: "#5aa9ff", wind: "#3dd6c6", depth: "#8f8cff", power: "#5ee38a",
            engine: "#ff9f5a", env: "#c78bff", glowA: "#123a5a", glowB: "#0f3b3a"
        },
        day: {
            bg: "#eef2f7", bg2: "#e3e9f1", surface: "#ffffff", surfaceHi: "#f4f7fb",
            border: "#d5dde8", text: "#0e1a2b", textDim: "#4d6079", textFaint: "#9aa9bd",
            accent: "#0e9f92", accent2: "#2471d6", warn: "#c97a00", danger: "#d63a3a", good: "#1e9e50",
            port: "#d63a42", starboard: "#18a35a",
            speed: "#2471d6", wind: "#0e9f92", depth: "#5b57d9", power: "#1e9e50",
            engine: "#d9692a", env: "#8a4fd1", glowA: "#cfe0f5", glowB: "#cdeee9"
        },
        red: {
            bg: "#050000", bg2: "#0b0101", surface: "#140303", surfaceHi: "#1c0505",
            border: "#2e0808", text: "#ff4a3d", textDim: "#b3271f", textFaint: "#5c1410",
            accent: "#ff3b2f", accent2: "#e0352a", warn: "#ff6a3d", danger: "#ff2a1f", good: "#d63a2a",
            port: "#ff3b2f", starboard: "#a3241b",
            speed: "#ff4a3d", wind: "#ff3b2f", depth: "#d63a2a", power: "#e0352a",
            engine: "#ff6a3d", env: "#c2281f", glowA: "#200303", glowB: "#1a0202"
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
    property color glowA: p.glowA
    property color glowB: p.glowB

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
    Behavior on glowA { ColorAnimation { duration: theme.colorMs * 2 } }
    Behavior on glowB { ColorAnimation { duration: theme.colorMs * 2 } }

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
