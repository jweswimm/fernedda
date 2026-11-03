import QtQuick
import QtQuick.Shapes

// Line icons drawn from SVG path data on a 24×24 grid, so they take any
// color and stay crisp at any size.
Item {
    id: root
    property string name: "dot"
    property color color: Theme.text
    property real size: 20
    property real stroke: 1.8

    implicitWidth: size
    implicitHeight: size

    readonly property var paths: ({
        dashboard: "M3 3h7v9H3z M14 3h7v5h-7z M14 12h7v9h-7z M3 16h7v5H3z",
        data: "M3 12h4l3-8 4 16 3-8h4",
        notes: "M6 3h9l4 4v14H6z M15 3v4h4 M9 12h7 M9 16h7 M9 8h3",
        settings: "M4 6h9 M17 6h3 M15 4v4 M4 12h3 M11 12h9 M9 10v4 M4 18h11 M19 18h1 M17 16v4",
        sun: "M12 8a4 4 0 1 0 0.01 0z M12 2v2 M12 20v2 M4.9 4.9l1.4 1.4 M17.7 17.7l1.4 1.4 M2 12h2 M20 12h2 M4.9 19.1l1.4-1.4 M17.7 6.3l1.4-1.4",
        moon: "M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z",
        eye: "M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z M12 9a3 3 0 1 0 0.01 0z",
        plus: "M12 5v14 M5 12h14",
        search: "M11 4a7 7 0 1 0 0.01 0z M16.5 16.5L21 21",
        pin: "M9 3h6l-1 6 3 3v2H7v-2l3-3z M12 14v7",
        trash: "M4 7h16 M9 7V4h6v3 M6 7l1 13h10l1-13",
        close: "M6 6l12 12 M18 6L6 18",
        wind: "M3 8h10a3 3 0 1 0-3-3 M3 12h15a3 3 0 1 1-3 3 M3 16h6",
        speed: "M4 18a8 8 0 1 1 16 0 M12 18l4.5-6",
        depth: "M12 3v11 M8 10l4 4 4-4 M3 19c2-1.5 4-1.5 6 0s4 1.5 6 0 4-1.5 6 0",
        battery: "M3 8h15v8H3z M21 11v2 M6 11v2 M9 11v2",
        bolt: "M13 2L4 14h7l-1 8 9-12h-7z",
        engine: "M12 9a3 3 0 1 0 0.01 0z M12 3v3 M12 18v3 M3 12h3 M18 12h3 M5.6 5.6l2.1 2.1 M16.3 16.3l2.1 2.1 M5.6 18.4l2.1-2.1 M16.3 7.7l2.1-2.1",
        drop: "M12 3c4 5 6 8 6 11a6 6 0 0 1-12 0c0-3 2-6 6-11z",
        thermo: "M10 4a2 2 0 0 1 4 0v10a4 4 0 1 1-4 0z M12 9v7",
        tank: "M6 4h12v16H6z M6 12c2-1 4-1 6 0s4 1 6 0",
        compass: "M12 3a9 9 0 1 0 0.01 0z M15.5 8.5l-2 5-5 2 2-5z",
        boat: "M3 16h18l-3 4H6z M12 3v12 M12 4l6 10h-6z M11 6l-5 8h5",
        rigging: "M12 2v20 M12 4L5 18h7 M12 6l6 12h-6",
        sail: "M6 3v16h12z M6 21h12",
        hull: "M2 13h20l-3 6H5z M7 13V9h8l2 4",
        lifebuoy: "M12 3a9 9 0 1 0 0.01 0z M12 8a4 4 0 1 0 0.01 0z M5.6 5.6l3.6 3.6 M14.8 14.8l3.6 3.6 M18.4 5.6l-3.6 3.6 M9.2 14.8l-3.6 3.6",
        home: "M3 11l9-7 9 7 M5 10v10h14V10",
        note: "M5 4h14v16H5z M9 9h6 M9 13h6 M9 17h3",
        chevron: "M9 6l6 6-6 6",
        back: "M15 6l-6 6 6 6",
        check: "M5 12l5 5 9-10",
        plug: "M5 12.5a10 10 0 0 1 14 0 M8.5 16a5 5 0 0 1 7 0 M12 19.5h0.01",
        edit: "M4 20h4L19 9l-4-4L4 16z M13 7l4 4",
        gauge: "M12 21a9 9 0 1 1 0.01 0z M12 12l4-4",
        globe: "M12 3a9 9 0 1 0 0.01 0z M3 12h18 M12 3c3 3 3 15 0 18 M12 3c-3 3-3 15 0 18",
        heel: "M4 18h16 M12 18V5 M12 5l5 9 M7 10l5 8",
        clock: "M12 3a9 9 0 1 0 0.01 0z M12 7v5l3 2",
        pulse: "M12 3a9 9 0 1 0 0.01 0z",
        tag: "M3 12V4h8l10 10-8 8z M7.5 8.5h0.01",
        list: "M8 6h12 M8 12h12 M8 18h12 M4 6h0.01 M4 12h0.01 M4 18h0.01",
        folder: "M3 6h6l2 2h10v11H3z",
        expand: "M14 4h6v6 M10 20H4v-6 M20 4l-7 7 M4 20l7-7",
        dot: "M12 11a1 1 0 1 0 0.01 0z"
    })

    Shape {
        width: 24
        height: 24
        scale: root.size / 24
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: root.color
            strokeWidth: root.stroke * 24 / Math.max(1, root.size)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.paths[root.name] || root.paths.dot }
        }
    }
}
