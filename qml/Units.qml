pragma Singleton
import QtQuick

// Signal K speaks SI (m/s, radians, Kelvin, Pascal, ratios). These turn
// values into what a sailor reads, and guess units from a path for the
// Data explorer.
QtObject {
    readonly property real msToKn: 1.943844
    readonly property real radToDeg: 57.29577951308232

    function ok(v) { return v !== undefined && v !== null && !isNaN(v) }
    function fmt(v, decimals) { return ok(v) ? Number(v).toFixed(decimals === undefined ? 1 : decimals) : "—" }

    function kn(ms) { return ms * msToKn }
    function deg(rad) { return rad * radToDeg }
    function deg360(rad) { let d = (rad * radToDeg) % 360; return d < 0 ? d + 360 : d }
    function deg180(rad) { let d = deg360(rad); return d > 180 ? d - 360 : d }
    function celsius(k) { return k - 273.15 }
    function hPa(pa) { return pa / 100 }
    function pct(r) { return r * 100 }
    function rpm(hz) { return hz * 60 }
    function hours(s) { return s / 3600 }
    function bar(pa) { return pa / 100000 }

    function heading3(rad) {
        if (!ok(rad)) return "—"
        let d = Math.round(deg360(rad)) % 360
        return ("00" + d).slice(-3)
    }

    // 47°38.402′N
    function latLon(v, isLat) {
        if (!ok(v)) return "—"
        const hemi = isLat ? (v >= 0 ? "N" : "S") : (v >= 0 ? "E" : "W")
        const a = Math.abs(v)
        const d = Math.floor(a)
        const m = (a - d) * 60
        return d + "°" + m.toFixed(3) + "′" + hemi
    }

    function relativeTime(date) {
        if (!date) return ""
        const s = (Date.now() - date.getTime()) / 1000
        if (s < 45) return qsTr("just now")
        if (s < 3600) return qsTr("%1 min ago").arg(Math.round(s / 60))
        if (s < 86400) return qsTr("%1 h ago").arg(Math.round(s / 3600))
        if (s < 86400 * 7) return qsTr("%1 d ago").arg(Math.round(s / 86400))
        return date.toLocaleDateString(Qt.locale(), "d MMM yyyy")
    }

    // How to show a raw Signal K path: unit label plus the scale/offset that
    // HistoryPlot and the readouts apply.
    function describe(path) {
        const p = path.toLowerCase()
        const last = p.split(".").pop()
        const r = (unit, scale, offset, decimals, angle) =>
            ({ unit: unit, scale: scale, offset: offset, decimals: decimals, angle: !!angle })
        if (/speed|velocity/.test(last) && !/revolutions/.test(p)) return r("kn", msToKn, 0, 1)
        if (/rateofturn/.test(last)) return r("°/s", radToDeg, 0, 1)
        if (/angle|heading|course|direction|variation|^yaw$|^roll$|^pitch$/.test(last))
            return r("°", radToDeg, 0, 0, /heading|course|direction/.test(last))
        if (/temperature/.test(p)) return r("°C", 1, -273.15, 1)
        if (/pressure/.test(last)) return /oil/.test(last) ? r("bar", 1e-5, 0, 2) : r("hPa", 0.01, 0, 1)
        if (/currentlevel|stateofcharge|relativehumidity|ratio|level$/.test(last)) return r("%", 100, 0, 0)
        if (/revolutions/.test(last)) return r("rpm", 60, 0, 0)
        if (/voltage/.test(last)) return r("V", 1, 0, 2)
        if (/current$/.test(last)) return r("A", 1, 0, 1)
        if (/power$/.test(last)) return r("W", 1, 0, 0)
        if (/runtime/.test(last)) return r("h", 1 / 3600, 0, 1)
        if (/capacity/.test(p) && /tanks/.test(p)) return r("L", 1000, 0, 0)
        if (/capacity/.test(p) && /batteries/.test(p)) return r("Wh", 1 / 3600, 0, 0)
        if (/depth|belowtransducer|belowkeel|belowsurface|distance|length|beam|draft/.test(p)) return r("m", 1, 0, 1)
        return r("", 1, 0, 2)
    }

    function display(path, value) {
        if (value === undefined || value === null) return "—"
        if (typeof value === "object") {
            if (value.latitude !== undefined)
                return latLon(value.latitude, true) + "  " + latLon(value.longitude, false)
            return JSON.stringify(value)
        }
        if (typeof value !== "number") return String(value)
        const d = describe(path)
        let v = value * d.scale + d.offset
        if (d.angle) { v = v % 360; if (v < 0) v += 360 }
        return v.toFixed(d.decimals) + (d.unit ? " " + d.unit : "")
    }
}
