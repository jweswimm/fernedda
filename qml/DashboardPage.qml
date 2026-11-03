import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Controls.Basic
import Fernedda

// The main board: one card per boat system. Click a card for its history.
Page {
    id: page
    title: qsTr("Dashboard")

    signal openDetail(Item item, var config)

    // ---- live values ------------------------------------------------------
    SignalKValue { id: sog; path: "navigation.speedOverGround" }
    SignalKValue { id: stw; path: "navigation.speedThroughWater" }
    SignalKValue { id: hdg; path: "navigation.headingMagnetic" }
    SignalKValue { id: hdgT; path: "navigation.headingTrue" }
    SignalKValue { id: cog; path: "navigation.courseOverGroundTrue" }
    SignalKValue { id: pos; path: "navigation.position" }
    SignalKValue { id: attitude; path: "navigation.attitude" }
    SignalKValue { id: awa; path: "environment.wind.angleApparent" }
    SignalKValue { id: aws; path: "environment.wind.speedApparent" }
    SignalKValue { id: twa; path: "environment.wind.angleTrueWater" }
    SignalKValue { id: tws; path: "environment.wind.speedTrue" }
    SignalKValue { id: twd; path: "environment.wind.directionTrue" }
    SignalKValue { id: depth; path: "environment.depth.belowTransducer" }
    SignalKValue { id: waterT; path: "environment.water.temperature" }
    SignalKValue { id: airT; path: "environment.outside.temperature" }
    SignalKValue { id: baro; path: "environment.outside.pressure" }
    SignalKValue { id: humidity; path: "environment.outside.relativeHumidity" }
    SignalKValue { id: rpm; path: "propulsion.main.revolutions" }
    SignalKValue { id: coolant; path: "propulsion.main.temperature" }
    SignalKValue { id: oil; path: "propulsion.main.oilPressure" }
    SignalKValue { id: hours; path: "propulsion.main.runTime" }
    SignalKValue { id: soc; path: "electrical.batteries.house.stateOfCharge" }
    SignalKValue { id: houseV; path: "electrical.batteries.house.voltage" }
    SignalKValue { id: houseI; path: "electrical.batteries.house.current" }
    SignalKValue { id: starterV; path: "electrical.batteries.starter.voltage" }
    SignalKValue { id: solar; path: "electrical.solar.main.panelPower" }
    SignalKValue { id: fuel; path: "tanks.fuel.0.currentLevel" }
    SignalKValue { id: fuelCap; path: "tanks.fuel.0.capacity" }
    SignalKValue { id: water; path: "tanks.freshWater.0.currentLevel" }
    SignalKValue { id: waterCap; path: "tanks.freshWater.0.capacity" }
    SignalKValue { id: black; path: "tanks.blackWater.0.currentLevel" }
    SignalKValue { id: blackCap; path: "tanks.blackWater.0.capacity" }

    function s(path, label, unit, scale, offset, decimals, extra) {
        let o = { path: path, label: label, unit: unit, scale: scale, offset: offset, decimals: decimals, angle: false }
        if (extra) for (let k in extra) o[k] = extra[k]
        return o
    }
    readonly property real kn: Units.msToKn
    readonly property real dg: Units.radToDeg

    // ---- layout -----------------------------------------------------------
    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: grid.implicitHeight + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        GridLayout {
            id: grid
            x: 24
            y: 4
            width: flick.width - 48
            readonly property int cols: Math.max(1, Math.min(4, Math.floor((width + columnSpacing) / 290)))
            readonly property real colW: (width - columnSpacing * (cols - 1)) / cols
            readonly property real rowH: 252
            columns: cols
            columnSpacing: Theme.gap
            rowSpacing: Theme.gap

            function w(span) { span = Math.min(span, cols); return colW * span + columnSpacing * (span - 1) }
            function h(span) { return rowH * span + rowSpacing * (span - 1) }

            // Wind ---------------------------------------------------------
            Card {
                id: windCard
                order: 0; revealed: page.entered
                title: qsTr("Wind"); icon: "wind"; accent: Theme.wind
                badge: twd.valid ? qsTr("TWD %1°").arg(Units.heading3(twd.number)) : ""
                Layout.columnSpan: Math.min(1, grid.cols)
                Layout.rowSpan: grid.cols >= 3 ? 2 : 1
                Layout.preferredWidth: grid.w(1)
                Layout.preferredHeight: grid.h(grid.cols >= 3 ? 2 : 1) + (grid.cols >= 3 ? 0 : 140)
                onOpened: page.openDetail(windCard, {
                    title: qsTr("Wind"), icon: "wind", color: Theme.wind,
                    series: [ s(aws.path, qsTr("Apparent speed"), "kn", kn, 0, 1, { includeZero: true }),
                              s(tws.path, qsTr("True speed"), "kn", kn, 0, 1, { includeZero: true }),
                              s(twd.path, qsTr("True direction"), "°", dg, 0, 0, { angle: true }),
                              s(awa.path, qsTr("Apparent angle"), "°", dg, 0, 0) ] })
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 6
                    WindRose {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        awa: awa.valid ? Units.deg180(awa.number) : NaN
                        twa: twa.valid ? Units.deg180(twa.number) : NaN
                        aws: aws.valid ? Units.kn(aws.number) : NaN
                        tws: tws.valid ? Units.kn(tws.number) : NaN
                    }
                    HistoryPlot {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 54
                        path: tws.path; windowSeconds: 1800; valueScale: page.kn
                        showAxes: false; color: Theme.accent2; lineWidth: 1.6; fillOpacity: 0.25
                    }
                    Text {
                        text: qsTr("True wind speed · 30 min")
                        color: Theme.textFaint; font.family: Theme.fontFamily; font.pixelSize: 11
                    }
                }
            }

            // Navigation ---------------------------------------------------
            Card {
                id: navCard
                order: 1; revealed: page.entered
                title: qsTr("Navigation"); icon: "compass"; accent: Theme.speed
                Layout.columnSpan: Math.min(2, grid.cols)
                Layout.preferredWidth: grid.w(2)
                Layout.preferredHeight: grid.h(1)
                onOpened: page.openDetail(navCard, {
                    title: qsTr("Navigation"), icon: "compass", color: Theme.speed,
                    series: [ s(sog.path, qsTr("Speed over ground"), "kn", kn, 0, 1, { includeZero: true }),
                              s(stw.path, qsTr("Speed through water"), "kn", kn, 0, 1, { includeZero: true }),
                              s(hdg.path, qsTr("Heading (mag)"), "°", dg, 0, 0, { angle: true }),
                              s(cog.path, qsTr("Course over ground"), "°", dg, 0, 0, { angle: true }) ] })
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 4
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        BigNumber { Layout.fillWidth: true; label: "SOG"; unit: "kn"; value: sog.valid ? Units.kn(sog.number) : NaN; color: Theme.speed; size: 44; stale: sog.stale }
                        BigNumber { Layout.fillWidth: true; label: "STW"; unit: "kn"; value: stw.valid ? Units.kn(stw.number) : NaN; size: 32; stale: stw.stale }
                        BigNumber { Layout.fillWidth: true; label: "HDG"; unit: "°M"; value: hdg.valid ? Units.deg360(hdg.number) : NaN; angle: true; pad3: true; size: 32; stale: hdg.stale }
                        BigNumber { Layout.fillWidth: true; label: "COG"; unit: "°T"; value: cog.valid ? Units.deg360(cog.number) : NaN; angle: true; pad3: true; size: 32; stale: cog.stale }
                    }
                    HistoryPlot {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        path: sog.path; windowSeconds: 1800; valueScale: page.kn; includeZero: true
                        showAxes: false; color: Theme.speed; lineWidth: 2; fillOpacity: 0.3
                    }
                }
            }

            // Depth --------------------------------------------------------
            Card {
                id: depthCard
                order: 2; revealed: page.entered
                readonly property bool shallow: depth.valid && depth.number < 3
                title: qsTr("Depth"); icon: "depth"; accent: shallow ? Theme.danger : Theme.depth
                badge: shallow ? qsTr("SHALLOW") : ""
                badgeColor: Theme.danger
                Layout.preferredWidth: grid.w(1)
                Layout.preferredHeight: grid.h(1)
                onOpened: page.openDetail(depthCard, { title: qsTr("Depth"), icon: "depth", color: Theme.depth,
                    series: [ s(depth.path, qsTr("Below transducer"), "m", 1, 0, 1, { includeZero: true }),
                              s(waterT.path, qsTr("Water temperature"), "°C", 1, -273.15, 1) ] })
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 2
                    BigNumber { value: depth.number; unit: "m"; size: 52; color: depthCard.shallow ? Theme.danger : Theme.text; stale: depth.stale }
                    HistoryPlot {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        path: depth.path; windowSeconds: 1800; includeZero: true
                        showAxes: false; color: Theme.depth; lineWidth: 1.8; fillOpacity: 0.35
                    }
                }
            }

            // Battery ------------------------------------------------------
            Card {
                id: batteryCard
                order: 3; revealed: page.entered
                title: qsTr("House bank"); icon: "battery"; accent: Theme.power
                badge: houseI.valid ? (houseI.number > 0.3 ? qsTr("Charging") : qsTr("Discharging")) : ""
                badgeColor: houseI.valid && houseI.number > 0.3 ? Theme.good : Theme.textDim
                Layout.preferredWidth: grid.w(1)
                Layout.preferredHeight: grid.h(1)
                onOpened: page.openDetail(batteryCard, { title: qsTr("Electrical"), icon: "battery", color: Theme.power,
                    series: [ s(soc.path, qsTr("State of charge"), "%", 100, 0, 0),
                              s(houseV.path, qsTr("House voltage"), "V", 1, 0, 2),
                              s(houseI.path, qsTr("House current"), "A", 1, 0, 1, { includeZero: true }),
                              s(solar.path, qsTr("Solar"), "W", 1, 0, 0, { includeZero: true }),
                              s(starterV.path, qsTr("Starter voltage"), "V", 1, 0, 2) ] })
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 10
                    BigNumber { value: soc.valid ? soc.number * 100 : NaN; decimals: 0; unit: "%"; size: 52; stale: soc.stale }
                    BatteryMeter { Layout.fillWidth: true; soc: soc.number; current: houseI.number }
                    Item { Layout.fillHeight: true }
                    RowLayout {
                        Layout.fillWidth: true
                        BigNumber { Layout.fillWidth: true; label: qsTr("Voltage"); value: houseV.number; decimals: 2; unit: "V"; size: 20 }
                        BigNumber { Layout.fillWidth: true; label: qsTr("Current"); value: houseI.number; decimals: 1; unit: "A"; size: 20
                                    color: houseI.number > 0 ? Theme.good : Theme.text }
                        BigNumber { Layout.fillWidth: true; label: qsTr("Solar"); value: solar.number; decimals: 0; unit: "W"; size: 20; color: Theme.warn }
                    }
                }
            }

            // Engine -------------------------------------------------------
            Card {
                id: engineCard
                order: 4; revealed: page.entered
                readonly property bool running: rpm.valid && rpm.number * 60 > 300
                title: qsTr("Engine"); icon: "engine"; accent: Theme.engine
                badge: rpm.valid ? (running ? qsTr("Running") : qsTr("Stopped")) : ""
                badgeColor: running ? Theme.engine : Theme.textDim
                Layout.preferredWidth: grid.w(1)
                Layout.preferredHeight: grid.h(1)
                onOpened: page.openDetail(engineCard, { title: qsTr("Engine"), icon: "engine", color: Theme.engine,
                    series: [ s(rpm.path, qsTr("RPM"), "rpm", 60, 0, 0, { includeZero: true }),
                              s(coolant.path, qsTr("Coolant"), "°C", 1, -273.15, 1),
                              s(oil.path, qsTr("Oil pressure"), "bar", 1e-5, 0, 2, { includeZero: true }) ] })
                RowLayout {
                    anchors.fill: parent
                    spacing: 6
                    RadialGauge {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        value: rpm.valid ? Units.rpm(rpm.number) : NaN
                        maximum: 3600; warnAt: 3000; dangerAt: 3300
                        unit: "rpm"; color: Theme.engine; ticks: 6
                    }
                    ColumnLayout {
                        Layout.preferredWidth: 92
                        spacing: 8
                        BigNumber { label: qsTr("Coolant"); value: coolant.valid ? Units.celsius(coolant.number) : NaN; decimals: 0; unit: "°C"; size: 22
                                    color: coolant.valid && Units.celsius(coolant.number) > 95 ? Theme.danger : Theme.text }
                        BigNumber { label: qsTr("Oil"); value: oil.valid ? Units.bar(oil.number) : NaN; decimals: 1; unit: "bar"; size: 22 }
                        BigNumber { label: qsTr("Hours"); value: hours.valid ? Units.hours(hours.number) : NaN; decimals: 1; unit: "h"; size: 18 }
                    }
                }
            }

            // Tanks --------------------------------------------------------
            Card {
                id: tanksCard
                order: 5; revealed: page.entered
                title: qsTr("Tanks"); icon: "tank"; accent: Theme.accent2
                Layout.preferredWidth: grid.w(1)
                Layout.preferredHeight: grid.h(1)
                onOpened: page.openDetail(tanksCard, { title: qsTr("Tanks"), icon: "tank", color: Theme.accent2,
                    series: [ s(fuel.path, qsTr("Fuel"), "%", 100, 0, 0), s(water.path, qsTr("Fresh water"), "%", 100, 0, 0),
                              s(black.path, qsTr("Holding"), "%", 100, 0, 0) ] })
                RowLayout {
                    anchors.fill: parent
                    spacing: 10
                    TankGauge { Layout.fillWidth: true; Layout.fillHeight: true; label: qsTr("Fuel"); level: fuel.number; color: Theme.engine
                                capacityL: fuelCap.valid ? fuelCap.number * 1000 : NaN }
                    TankGauge { Layout.fillWidth: true; Layout.fillHeight: true; label: qsTr("Water"); level: water.number; color: Theme.accent2
                                capacityL: waterCap.valid ? waterCap.number * 1000 : NaN }
                    TankGauge { Layout.fillWidth: true; Layout.fillHeight: true; label: qsTr("Holding"); level: black.number; color: Theme.textDim
                                capacityL: blackCap.valid ? blackCap.number * 1000 : NaN; lowIsBad: false }
                }
            }

            // Environment --------------------------------------------------
            Card {
                id: envCard
                order: 6; revealed: page.entered
                title: qsTr("Weather"); icon: "thermo"; accent: Theme.env
                badge: baroTrend.text
                Layout.columnSpan: Math.min(2, grid.cols)
                Layout.preferredWidth: grid.w(2)
                Layout.preferredHeight: grid.h(1)
                onOpened: page.openDetail(envCard, { title: qsTr("Weather"), icon: "thermo", color: Theme.env,
                    series: [ s(baro.path, qsTr("Barometer"), "hPa", 0.01, 0, 1),
                              s(airT.path, qsTr("Air temperature"), "°C", 1, -273.15, 1),
                              s(waterT.path, qsTr("Water temperature"), "°C", 1, -273.15, 1),
                              s(humidity.path, qsTr("Humidity"), "%", 100, 0, 0) ] })
                RowLayout {
                    anchors.fill: parent
                    spacing: 18
                    GridLayout {
                        columns: 2
                        columnSpacing: 18
                        rowSpacing: 10
                        Layout.alignment: Qt.AlignTop
                        BigNumber { label: qsTr("Air"); value: airT.valid ? Units.celsius(airT.number) : NaN; unit: "°C"; size: 30 }
                        BigNumber { label: qsTr("Sea"); value: waterT.valid ? Units.celsius(waterT.number) : NaN; unit: "°C"; size: 30 }
                        BigNumber { label: qsTr("Pressure"); value: baro.valid ? Units.hPa(baro.number) : NaN; decimals: 1; unit: "hPa"; size: 22 }
                        BigNumber { label: qsTr("Humidity"); value: humidity.valid ? Units.pct(humidity.number) : NaN; decimals: 0; unit: "%"; size: 22 }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 2
                        HistoryPlot {
                            id: baroPlot
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            path: baro.path; windowSeconds: 3 * 3600; valueScale: 0.01; decimals: 1; unit: "hPa"
                            color: Theme.env; gridColor: Theme.alpha(Theme.textFaint, 0.5); textColor: Theme.textFaint
                            surfaceColor: Theme.surfaceHi; lineWidth: 1.8; fillOpacity: 0.25
                        }
                        Text {
                            id: baroTrend
                            // Rough 3 h tendency from what we've seen.
                            readonly property real delta: baroPlot.maximum - baroPlot.minimum
                            text: !baro.valid ? "" : delta < 0.5 ? qsTr("Steady") : qsTr("Changing %1 hPa / 3 h").arg(delta.toFixed(1))
                            visible: false
                        }
                    }
                }
            }

            // Attitude & position ------------------------------------------
            Card {
                id: posCard
                order: 7; revealed: page.entered
                readonly property real heel: attitude.valid && attitude.value.roll !== undefined ? Units.deg(attitude.value.roll) : NaN
                title: qsTr("Heel & position"); icon: "heel"; accent: Theme.accent
                Layout.columnSpan: Math.min(2, grid.cols)
                Layout.preferredWidth: grid.w(2)
                Layout.preferredHeight: grid.h(1)
                interactive: false
                RowLayout {
                    anchors.fill: parent
                    spacing: 18

                    // Inclinometer: the boat seen from astern, rolling.
                    Item {
                        id: incl
                        Layout.preferredWidth: Math.min(parent.width * 0.45, 260)
                        Layout.fillHeight: true
                        readonly property real r: Math.max(20, Math.min(width / 2 - 8, (height - 40) / 1.56))
                        readonly property real cx: width / 2
                        readonly property real cy: r + 10
                        readonly property real k: r * 0.9
                        Shape {
                            anchors.fill: parent
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                strokeColor: Theme.border; strokeWidth: 8; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                                PathAngleArc { centerX: incl.cx; centerY: incl.cy; radiusX: incl.r; radiusY: incl.r; startAngle: 230; sweepAngle: 80 }
                            }
                            ShapePath {
                                strokeColor: Theme.alpha(Theme.warn, 0.55); strokeWidth: 8; fillColor: "transparent"
                                PathAngleArc { centerX: incl.cx; centerY: incl.cy; radiusX: incl.r; radiusY: incl.r; startAngle: 230; sweepAngle: 15 }
                            }
                            ShapePath {
                                strokeColor: Theme.alpha(Theme.warn, 0.55); strokeWidth: 8; fillColor: "transparent"
                                PathAngleArc { centerX: incl.cx; centerY: incl.cy; radiusX: incl.r; radiusY: incl.r; startAngle: 295; sweepAngle: 15 }
                            }
                        }
                        Shape {
                            anchors.fill: parent
                            preferredRendererType: Shape.CurveRenderer
                            // Signal K roll is + when heeled to starboard; seen from astern that leans right.
                            transform: Rotation {
                                origin.x: incl.cx; origin.y: incl.cy
                                angle: isNaN(posCard.heel) ? 0 : posCard.heel
                                Behavior on angle { NumberAnimation { duration: 800; easing.type: Easing.OutCubic } }
                            }
                            ShapePath { // mast
                                strokeColor: Theme.text; strokeWidth: 2.5; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                                startX: incl.cx; startY: incl.cy
                                PathLine { x: incl.cx; y: incl.cy - incl.k * 0.85 }
                            }
                            ShapePath { // hull and keel
                                strokeColor: Theme.accent; strokeWidth: 2; fillColor: Theme.alpha(Theme.accent, 0.18)
                                joinStyle: ShapePath.RoundJoin
                                startX: incl.cx - incl.k * 0.42; startY: incl.cy
                                PathLine { x: incl.cx + incl.k * 0.42; y: incl.cy }
                                PathQuad { x: incl.cx + incl.k * 0.06; y: incl.cy + incl.k * 0.3; controlX: incl.cx + incl.k * 0.4; controlY: incl.cy + incl.k * 0.28 }
                                PathLine { x: incl.cx; y: incl.cy + incl.k * 0.6 }
                                PathLine { x: incl.cx - incl.k * 0.06; y: incl.cy + incl.k * 0.3 }
                                PathQuad { x: incl.cx - incl.k * 0.42; y: incl.cy; controlX: incl.cx - incl.k * 0.4; controlY: incl.cy + incl.k * 0.28 }
                            }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            text: isNaN(posCard.heel) ? "—" : qsTr("Heel %1°%2").arg(Math.abs(posCard.heel).toFixed(0))
                                                                     .arg(posCard.heel < -0.5 ? " P" : posCard.heel > 0.5 ? " S" : "")
                            color: Math.abs(posCard.heel) > 25 ? Theme.warn : Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 18
                            font.features: { "tnum": 1 }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 6
                        Text { text: qsTr("Position"); color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: 12 }
                        Text {
                            text: pos.valid ? Units.latLon(pos.value.latitude, true) : "—"
                            color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 24; font.weight: Font.Light
                            font.features: { "tnum": 1 }
                        }
                        Text {
                            text: pos.valid ? Units.latLon(pos.value.longitude, false) : "—"
                            color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 24; font.weight: Font.Light
                            font.features: { "tnum": 1 }
                        }
                        Text {
                            text: pos.valid ? qsTr("updated %1").arg(pos.timestamp.toLocaleTimeString(Qt.locale(), "HH:mm:ss")) : ""
                            color: Theme.textFaint; font.family: Theme.fontFamily; font.pixelSize: 11
                        }
                    }
                }
            }
        }
    }
}
