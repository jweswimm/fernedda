import QtQuick

// A number that glides to its new value instead of jumping. With `angle`
// set it takes the short way round (359° → 2° goes forward 3°, not back).
Text {
    id: root
    property real value: NaN
    property int decimals: 1
    property bool angle: false
    property bool pad3: false   // 007 style for headings
    property int duration: 650

    property real shown: 0
    property bool _init: false

    function _target(v) {
        if (!angle) return v
        let delta = ((v - shown) % 360 + 540) % 360 - 180
        return shown + delta
    }

    onValueChanged: {
        if (isNaN(value)) return
        // First value, or a change too small to see: snap instead of animating,
        // so jittery inputs don't keep restarting the tween.
        if (!_init || Math.abs(value - (angle ? ((shown % 360) + 360) % 360 : shown)) < Math.pow(10, -decimals)) {
            _init = true; anim.enabled = false; shown = angle ? _target(value) : value; anim.enabled = true; return
        }
        shown = _target(value)
    }
    Component.onCompleted: if (!isNaN(value)) { _init = true; anim.enabled = false; shown = value; anim.enabled = true }

    Behavior on shown {
        id: anim
        NumberAnimation { duration: root.duration; easing.type: Easing.OutCubic }
    }

    text: {
        if (isNaN(value)) return "—"
        let v = shown
        if (angle) { v = v % 360; if (v < 0) v += 360 }
        if (pad3) { const r = Math.round(v) % 360; return ("00" + r).slice(-3) }
        return v.toFixed(decimals)
    }
    font.family: Theme.fontFamily
    font.features: { "tnum": 1 }
    color: Theme.text
}
