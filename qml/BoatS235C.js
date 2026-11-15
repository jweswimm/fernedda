.pragma library

// S2 35C ("S2 35 Mid Cockpit", Graham & Schlageter, 1986–87), drawn in metres.
//
// Traced from the builder's line drawing (S2-35C_drawing.jpg, 583×864 px):
// side profile, deck plan and accommodation plan. Each view below converts the
// drawing's pixel coordinates to metres with one helper (pr / dk / bl), so a
// point can be checked against the image by its pixel position.
//
// Published numbers it agrees with: LOA 10.72 m (35′2″), beam 3.51 m (11′6″),
// I 13.72, J 4.33, P 11.79, E 4.33 (masthead sloop). The drawing shows a
// deeper fin (~1.7 m) than the 1.30 m (4′3″) standard-keel figure.
//
// Coordinates: x is metres forward of the aftmost point of the hull (bow to
// the right). In "outside" y is metres above the waterline; in the plan views
// y is metres to port of the centreline (port at the top).
//
// Art is SVG-like path strings using absolute M, L, C, Q and Z only.
// Zones are the tappable parts of the boat; later zones sit on top of
// earlier ones. `system` is the default system for a note created there.
// Zone ids are stored in notes, so rename `name`s freely but keep ids.

// ---- helpers -------------------------------------------------------------

function f(n) { return Math.round(n * 1000) / 1000 }
function rect(x0, y0, x1, y1) {
    return "M " + f(x0) + " " + f(y0) + " L " + f(x1) + " " + f(y0) + " L " + f(x1) + " " + f(y1) + " L " + f(x0) + " " + f(y1) + " Z "
}
function line(pts) {
    let s = ""
    for (let i = 0; i < pts.length; ++i) s += (i ? "L " : "M ") + f(pts[i][0]) + " " + f(pts[i][1]) + " "
    return s
}
function poly(pts) { return line(pts) + "Z " }
function ellipse(cx, cy, rx, ry) {
    const k = 0.5523
    return "M " + f(cx + rx) + " " + f(cy)
        + " C " + f(cx + rx) + " " + f(cy + ry * k) + " " + f(cx + rx * k) + " " + f(cy + ry) + " " + f(cx) + " " + f(cy + ry)
        + " C " + f(cx - rx * k) + " " + f(cy + ry) + " " + f(cx - rx) + " " + f(cy + ry * k) + " " + f(cx - rx) + " " + f(cy)
        + " C " + f(cx - rx) + " " + f(cy - ry * k) + " " + f(cx - rx * k) + " " + f(cy - ry) + " " + f(cx) + " " + f(cy - ry)
        + " C " + f(cx + rx * k) + " " + f(cy - ry) + " " + f(cx + rx) + " " + f(cy - ry * k) + " " + f(cx + rx) + " " + f(cy) + " Z "
}
function circle(cx, cy, r) { return ellipse(cx, cy, r, r) }
function circlePts(cx, cy, r, n) {
    const out = []
    for (let i = 0; i < (n || 14); ++i) {
        const a = i / (n || 14) * Math.PI * 2
        out.push([cx + r * Math.cos(a), cy + r * Math.sin(a)])
    }
    return out
}
// Smooth curve through points (Catmull-Rom as cubic Béziers).
function smooth(pts, closed) {
    const n = pts.length
    const at = i => closed ? pts[(i + n) % n] : pts[Math.max(0, Math.min(n - 1, i))]
    let s = "M " + f(pts[0][0]) + " " + f(pts[0][1]) + " "
    const segs = closed ? n : n - 1
    for (let i = 0; i < segs; ++i) {
        const p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2)
        s += "C " + f(p1[0] + (p2[0] - p0[0]) / 6) + " " + f(p1[1] + (p2[1] - p0[1]) / 6) + " "
           + f(p2[0] - (p3[0] - p1[0]) / 6) + " " + f(p2[1] - (p3[1] - p1[1]) / 6) + " "
           + f(p2[0]) + " " + f(p2[1]) + " "
    }
    return s + (closed ? "Z " : "")
}
function lerpTable(table, x) {
    if (x <= table[0][0]) return table[0][1]
    for (let i = 1; i < table.length; ++i) {
        if (x <= table[i][0]) {
            const a = table[i - 1], b = table[i]
            return a[1] + (b[1] - a[1]) * (x - a[0]) / (b[0] - a[0])
        }
    }
    return table[table.length - 1][1]
}
// A thin quad around the segment a→b, so a wire is easy to tap.
function band(a, b, w) {
    const dx = b[0] - a[0], dy = b[1] - a[1], l = Math.hypot(dx, dy)
    const nx = -dy / l * w / 2, ny = dx / l * w / 2
    return [[a[0] + nx, a[1] + ny], [b[0] + nx, b[1] + ny], [b[0] - nx, b[1] - ny], [a[0] - nx, a[1] - ny]]
}
// Points along a→b at fraction t.
function along(a, b, t) { return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t] }

// Drawing pixels → metres, one mapping per view of the drawing.
function pr(X, Y) { return [(X - 121.7) / 28, (422 - Y) / 28] }   // side profile: 28 px/m, waterline at y 422
function dk(X, Y) { return [(X - 16) / 50, (575 - Y) / 50] }      // deck plan: 50 px/m, centreline at y 575
function bl(X, Y) { return [(X - 16) / 50, (767.5 - Y) / 50] }    // accommodation plan: 50 px/m, centreline y 767.5
function P(fn, pts) { return pts.map(p => fn(p[0], p[1])) }
function R(fn, X0, Y0, X1, Y1) { const a = fn(X0, Y0), b = fn(X1, Y1); return rect(a[0], a[1], b[0], b[1]) }
function H(fn, X0, Y0, X1, Y1, inset) { const a = fn(X0, Y0), b = fn(X1, Y1); return hullRect(a[0], a[1], b[0], b[1], inset) }
function L(fn, pts) { return line(P(fn, pts)) }
function G(fn, pts) { return poly(P(fn, pts)) }
function S(fn, pts, closed) { return smooth(P(fn, pts), closed) }
// Mirror a plan-view polygon to starboard (pixel y about the centreline).
function mirror(pts, cy) { return pts.map(p => [p[0], 2 * cy - p[1]]) }

// ---- hull lines (from the deck plan) --------------------------------------

const MAST_X = dk(335, 575)[0]   // ≈ 6.38 m; the profile agrees within 0.1 m

// Half-breadth of the deck edge, aft to forward (metres).
const halfBreadth = [[0.0, 0.42], [0.12, 0.85], [0.3, 1.08], [0.68, 1.30], [1.68, 1.56], [2.68, 1.66],
                     [3.68, 1.76], [4.68, 1.78], [5.68, 1.72], [6.68, 1.50], [7.68, 1.20], [8.68, 0.82],
                     [9.68, 0.44], [10.48, 0.16], [10.72, 0]]
function hb(x) { return lerpTable(halfBreadth, x) }
function deckOutline(inset) {
    const k = inset || 0
    const port = halfBreadth.map(p => [Math.min(p[0], 10.72 - k * 1.5) + (p[0] < 0.01 ? k : 0), Math.max(0, p[1] - k)])
    const stbd = port.slice(0, -1).reverse().map(p => [p[0], -p[1]])
    return port.concat(stbd)
}
// Deck-edge points between two stations (for zone polygons).
function edgeBetween(x0, x1, sign, inset) {
    const k = inset || 0
    const out = [[x0, sign * (hb(x0) - k)]]
    for (const p of halfBreadth) if (p[0] > x0 && p[0] < x1) out.push([p[0], sign * Math.max(0, p[1] - k)])
    out.push([x1, sign * Math.max(0, hb(x1) - k)])
    return out
}
function stationSlice(x0, x1, inset) {
    const port = edgeBetween(x0, x1, 1, inset)
    const stbd = edgeBetween(x0, x1, -1, inset).reverse()
    return port.concat(stbd)
}
// A rectangle (metres) trimmed to stay inside the hull.
function hullRect(x0, y0, x1, y1, inset) {
    const k = inset || 0, n = 8
    const top = [], bot = []
    for (let i = 0; i <= n; ++i) {
        const x = x0 + (x1 - x0) * i / n, h = Math.max(0, hb(x) - k)
        top.push([x, Math.max(-h, Math.min(Math.max(y0, y1), h))])
        bot.push([x, Math.min(h, Math.max(Math.min(y0, y1), -h))])
    }
    return poly(top.concat(bot.reverse()))
}

// ---- outside (profile from starboard) -------------------------------------

const hullTop = [[135, 392.7], [210, 393.3], [310, 391.7], [421.7, 387.3]]           // sheer, aft → bow
const stem = [[421.7, 387.3], [413.3, 400], [403.3, 411.7], [396, 422]]
const counter = [[141.7, 422], [121.7, 415], [135, 392.7]]                             // waterline → aft point → transom top
const underbodyPx = [[396, 422], [393.3, 424.3], [376.7, 429.3], [343.3, 435], [310, 439],
                     [233.3, 438.3], [200, 435], [160, 427.3], [150, 425], [141.7, 422]]
const keelPx = [[233.3, 438.3], [240, 470.7], [273.3, 470.7], [278.3, 467.7], [310, 439]]
const rudderPx = [[133.3, 421], [134, 455], [145, 455.7], [158.3, 425]]

const topsides = S(pr, hullTop) + S(pr, stem).replace(/^M [^C]*/, "") + L(pr, [[141.7, 422]]).replace("M", "L")
               + L(pr, counter.slice(1)).replace("M", "L") + "Z "
const underbody = S(pr, underbodyPx.slice(0, 5)) + L(pr, underbodyPx.slice(5)).replace("M", "L") + "Z "
const keel = G(pr, keelPx)
const rudder = G(pr, rudderPx)

const masthead = pr(297.5, 10)
const tack = pr(418, 384)
const forestay = [pr(299, 11), pr(421, 387)]
const backstay = [pr(296, 11), pr(130, 390)]
const mainHead = pr(295, 14), mainTack = pr(295, 341), mainClew = pr(173, 341)
const jibHead = pr(300, 15), jibClew = pr(293, 369)
const main = poly([mainTack, mainHead]) .replace(/Z $/, "")
           + "Q " + f(pr(226, 170)[0]) + " " + f(pr(226, 170)[1]) + " " + f(mainClew[0]) + " " + f(mainClew[1]) + " Z "
const jib = poly([jibHead, tack, jibClew])
// Sail seams, like the drawing's panel lines.
function seams(luffA, luffB, leechA, leechB, n) {
    let s = ""
    for (let i = 1; i < n; ++i) {
        const t = i / n
        s += line([along(luffA, luffB, t), along(leechA, leechB, Math.min(1, t + 0.04))])
    }
    return s
}

const outside = {
    id: "outside",
    label: "Outside",
    bounds: [-0.4, -1.95, 11.3, 15.2],
    art: [
        { style: "water", d: rect(-40, -12, 50, 0) },          // clipped to the view
        { style: "sail", d: jib + main },
        { style: "detail", d: seams(jibHead, tack, jibHead, jibClew, 13) + seams(mainHead, mainTack, mainHead, mainClew, 12) },
        { style: "house", d: S(pr, [[153.3, 393], [153.3, 392], [160, 382.7], [176.7, 379.3], [190, 376.7], [198.3, 375]])
                           + L(pr, [[303.3, 374.3], [323.3, 377.3], [355, 381.7], [366, 388], [366, 394], [153.3, 394]]).replace("M", "L") + "Z " },
        { style: "hull", d: topsides },
        { style: "bottom", d: underbody + keel + rudder },
        { style: "stripe", d: L(pr, [[137, 397.3], [403.3, 395]]) },                                         // cove stripe
        { style: "stripe", d: L(pr, [[139, 420], [395, 420]]) },                                             // boot stripe
        { style: "glass", d: R(pr, 173.3, 386, 196, 390) + R(pr, 225, 385, 246.7, 390) + R(pr, 253.3, 385, 296.7, 390)
                           + R(pr, 328.3, 384, 339.3, 388.3) + R(pr, 340.7, 384, 350, 388.3) },
        { style: "detail", d: L(pr, [[141.7, 422], [396, 422]]) + L(pr, [[198.3, 375], [198.3, 392]]) + L(pr, [[198.3, 380], [303, 380]]) },
        // propeller and shaft (not in the drawing; usual spot just aft of the keel)
        { style: "line", d: L(pr, [[236, 436], [214, 437.5]]) },
        { style: "spar", d: ellipse(pr(213, 437.5)[0], pr(213, 437.5)[1], 0.05, 0.2) },
        // rails, lifelines, arch
        { style: "rig", d: L(pr, [[133, 392], [128, 373], [150, 373]])                                       // pushpit
                         + L(pr, [[400, 387], [406.7, 371.7], [421.7, 370], [423.3, 386.7]])                    // pulpit
                         + L(pr, [[150, 373], [406.7, 371.7]]) + L(pr, [[131, 382], [404, 380]])               // lifelines
                         + L(pr, [[165, 392.5], [165, 373]]) + L(pr, [[260, 392.4], [260, 372.6]])
                         + L(pr, [[355, 391], [355, 372]]) + L(pr, [[192, 375], [192, 347]]) },
        // standing rigging
        { style: "rig", d: line(forestay) + line(backstay)
                         + L(pr, [[297, 150], [288, 151]]) + L(pr, [[297, 245], [286, 246]]) },                // spreaders
        { style: "spar", d: R(pr, 295.5, 9, 299.3, 374.3)                                                    // mast
                          + R(pr, 172, 341, 296, 345) },                                                     // boom
        { style: "line", d: L(pr, [[297.5, 9], [297.5, 2]]) + L(pr, [[297.5, 5], [290, 5]]) },                // antenna + wind vane
    ],
    zones: [
        { id: "topsides", name: "Topsides & hull", system: "Hull & Deck", d: topsides, at: pr(330, 408) },
        { id: "bottom", name: "Bottom & thru-hulls", system: "Hull & Deck", d: underbody, at: pr(350, 430) },
        { id: "keel", name: "Keel & keel bolts", system: "Hull & Deck", d: keel, at: pr(262, 455) },
        { id: "rudder", name: "Rudder & stock", system: "Hull & Deck", d: rudder, at: pr(140, 440) },
        { id: "prop", name: "Prop, shaft & cutless", system: "Engine", d: R(pr, 205, 428, 228, 446), at: pr(214, 437) },
        { id: "transom", name: "Transom & swim step", system: "Hull & Deck", d: G(pr, [[121, 415], [135, 392.7], [140, 392.7], [146, 422], [141.7, 422]]), at: pr(132, 405) },
        { id: "genoa", name: "Headsail & furler", system: "Sails", d: jib, at: pr(345, 250) },
        { id: "mainsail", name: "Mainsail & boom", system: "Sails", d: main + R(pr, 170, 338, 297, 348), at: pr(250, 250) },
        { id: "stays", name: "Shrouds & stays", system: "Rigging",
          d: poly(band(forestay[0], forestay[1], 0.32)) + poly(band(backstay[0], backstay[1], 0.32)), at: pr(160, 300) },
        { id: "mast", name: "Mast & spreaders", system: "Rigging", d: R(pr, 291, 30, 304, 374), at: pr(297.5, 200) },
        { id: "masthead", name: "Masthead, lights & instruments", system: "Navigation", d: R(pr, 286, 0, 309, 30), at: pr(297.5, 18) },
    ],
}

// ---- deck (plan from above) ------------------------------------------------

// Deckhouse: one long trunk with the cockpit sunk into it (port half, px).
const trunkPx = [[57, 530], [62, 520], [100, 518], [200, 517], [300, 520], [350, 527], [400, 537], [435, 548], [450, 575]]
const trunk = P(dk, trunkPx.concat(mirror(trunkPx.slice(0, -1), 575).reverse()))
const cockpitPx = [[130, 527], [245, 527], [245, 623], [130, 623]]
const portBars = [[[80, 520], [122, 524]], [[182, 515], [225, 519]], [[240, 513], [290, 519]], [[395, 535], [420, 545]], [[425, 540], [445, 550]]]
function bars() {
    let s = ""
    for (const b of portBars) {
        const a = b[0], c = b[1]
        s += G(dk, [[a[0], a[1]], [c[0], c[1] - 1], [c[0], c[1] + 2], [a[0], a[1] + 3]])
        s += G(dk, mirror([[a[0], a[1]], [c[0], c[1] - 1], [c[0], c[1] + 2], [a[0], a[1] + 3]], 575))
    }
    return s
}
function stanchionDots(xs) {
    let s = ""
    for (const x of xs) s += circle(x, hb(x) - 0.1, 0.035) + circle(x, -(hb(x) - 0.1), 0.035)
    return s
}

const deck = {
    id: "deck",
    label: "Deck",
    bounds: [-0.35, -2.05, 11.35, 2.05],
    art: [
        { style: "deck", d: smooth(deckOutline(0), true) },
        { style: "detail", d: smooth(deckOutline(0.1), true) },                                          // toe rail
        { style: "rig", d: smooth(deckOutline(0.16), true) },                                            // lifelines
        { style: "detail", d: S(dk, [[40, 520], [28, 545], [24, 575], [28, 605], [40, 630]]) },         // swim step
        { style: "nonskid", d: G(dk, [[455, 548], [485, 552], [540, 568], [540, 582], [485, 598], [455, 602]]) },
        { style: "house", d: smooth(trunk, true) },
        { style: "line", d: G(dk, cockpitPx) },
        { style: "cushion", d: R(dk, 140, 535, 237, 551) + R(dk, 140, 599, 237, 615) },                  // seats
        { style: "sole", d: G(dk, [[157, 557], [235, 553], [235, 597], [157, 593]]) },                  // cockpit sole
        { style: "detail", d: L(dk, [[140, 537], [157, 557]]) + L(dk, [[140, 613], [157, 593]]) + G(dk, [[157, 557], [235, 553], [235, 597], [157, 593]]) },
        { style: "spar", d: R(dk, 171, 553, 174, 597) },                                                 // wheel
        { style: "line", d: circle(dk(180, 575)[0], 0, 0.1) + L(dk, [[174, 575], [180, 575]]) },        // pedestal
        { style: "line", d: S(dk, [[114, 531], [117, 553], [118, 575], [117, 597], [114, 619]]) },      // traveler
        { style: "spar", d: circle(dk(117, 575)[0], 0, 0.06) + circle(dk(48, 575)[0], 0, 0.1) },       // mainsheet car, backstay plate
        { style: "glass", d: R(dk, 73, 562, 96, 589) + R(dk, 253, 526, 268, 541) + R(dk, 253, 609, 268, 624)
                           + R(dk, 393, 558, 425, 592) },                                                // hatches
        { style: "house", d: R(dk, 248, 557, 272, 593) },                                                // companionway slide
        { style: "glass", d: R(dk, 273, 553, 312, 596) },                                                // main hatch
        { style: "line", d: R(dk, 273, 553, 312, 596) },
        { style: "fixture", d: R(dk, 296, 539, 304, 547) + R(dk, 296, 603, 304, 611) },                 // dorades
        { style: "spar", d: bars() },                                                                    // portlights
        { style: "fixture", d: circle(dk(80, 0)[0], dk(0, 530)[1], 0.09) + circle(dk(80, 0)[0], dk(0, 620)[1], 0.09)
                             + circle(dk(192, 0)[0], dk(0, 527)[1], 0.1) + circle(dk(192, 0)[0], dk(0, 623)[1], 0.1) }, // winches
        { style: "spar", d: ellipse(MAST_X, 0, 0.15, 0.09) },                                           // mast
        { style: "line", d: G(dk, [[485, 548], [540, 568], [540, 582], [485, 602]])                      // anchor locker
                          + G(dk, [[548, 570], [572, 573], [572, 577], [548, 580]]) },                    // bow roller
        { style: "rig", d: L(dk, [[500, 556], [552, 563], [565, 575], [552, 587], [500, 594]])           // pulpit
                         + L(dk, [[20, 545], [33, 520]]) + L(dk, [[20, 605], [33, 630]]) },              // pushpit
        { style: "fixture", d: stanchionDots([1.9, 3.9, 5.6, 7.0, 8.3]) },
    ],
    zones: [
        { id: "sidedecks", name: "Side decks & lifelines", system: "Safety",
          d: poly(edgeBetween(0.82, 8.68, 1).concat(trunk.slice(0, 9).reverse()))
           + poly(edgeBetween(0.82, 8.68, -1).concat(trunk.slice(8).filter(p => p[1] <= 0))),
          at: dk(150, 500) },
        { id: "stern", name: "Stern & swim step", system: "Hull & Deck", d: poly(stationSlice(0, 0.82)), at: dk(30, 575) },
        { id: "foredeck", name: "Foredeck", system: "Hull & Deck", d: poly(stationSlice(8.68, 9.35)), at: dk(468, 575) },
        { id: "bow", name: "Bow, anchor & windlass", system: "Hull & Deck",
          d: poly(stationSlice(9.35, 10.72)) + R(dk, 545, 568, 575, 582), at: dk(515, 575) },
        { id: "cabintop", name: "Cabin top & hatches", system: "Hull & Deck", d: poly(trunk), at: dk(410, 560) },
        { id: "aftdeck", name: "Aft cabin top, hatch & traveler", system: "Hull & Deck",
          d: G(dk, [[57, 530], [62, 520], [100, 518], [130, 518], [130, 632], [100, 632], [62, 630], [57, 620]]), at: dk(85, 545) },
        { id: "cockpit", name: "Cockpit & lockers", system: "Hull & Deck", d: G(dk, cockpitPx), at: dk(212, 575) },
        { id: "helm", name: "Helm, pedestal & instruments", system: "Navigation", d: R(dk, 164, 550, 190, 600), at: dk(177, 560) },
        { id: "companionway", name: "Companionway & main hatch", system: "Hull & Deck", d: R(dk, 245, 550, 314, 600), at: dk(290, 575) },
        { id: "mastbase", name: "Mast base & halyards", system: "Rigging", d: poly(circlePts(MAST_X, 0, 0.42)), at: [MAST_X, 0] },
    ],
}

// ---- below (accommodation plan) ---------------------------------------------

// The aft cabin's sole (stippled D in the drawing) and its berth across the stern.
const aftSolePx = [[195, 712], [150, 722], [126, 752], [125, 780], [140, 803], [172, 818], [172, 751], [195, 751]]
const berth = edgeBetween(0.06, 2.45, 1, 0.08)
    .concat(P(bl, [[139, 717], [150, 722], [126, 752], [125, 780], [140, 803], [120, 821]]))
    .concat(edgeBetween(0.06, bl(120, 0)[0], -1, 0.08).reverse())

// A bulkhead across the boat at pixel x, trimmed to the hull.
function wall(X, Y0, Y1) {
    const a = bl(X, Y0), b = bl(X, Y1), h = hb(a[0]) - 0.03
    return line([[a[0], Math.max(-h, Math.min(h, a[1]))], [b[0], Math.max(-h, Math.min(h, b[1]))]])
}
function strips(X0, X1, Y0, Y1, step) {   // teak-and-holly sole lines
    let s = ""
    for (let y = Y0; y <= Y1; y += step) s += L(bl, [[X0, y], [X1, y]])
    return s
}

const below = {
    id: "below",
    label: "Below",
    bounds: [-0.35, -2.05, 11.35, 2.05],
    art: [
        { style: "interior", d: smooth(deckOutline(0), true) },
        // Soles
        { style: "sole", d: G(bl, [[250, 715], [276, 715], [276, 810], [250, 810]]) + R(bl, 276, 740, 378, 793)
                          + R(bl, 378, 740, 409, 790) + R(bl, 172, 800, 250, 815) + S(bl, aftSolePx, true) },
        { style: "detail", d: strips(250, 276, 718, 808, 7) + strips(380, 409, 743, 788, 6) + strips(278, 376, 744, 790, 6) + strips(172, 250, 803, 813, 5) },
        // Aft cabin: double berth across the stern, lockers port and starboard forward
        { style: "cushion", d: poly(berth) },
        { style: "detail", d: L(bl, [[17, 750], [76, 750], [76, 700]]) + L(bl, [[76, 715], [95, 707], [140, 708]]) },
        { style: "furniture", d: G(bl, [[139, 690], [196, 684], [196, 710], [170, 718], [139, 712]]) + H(bl, 120, 821, 165, 870, 0.04) },
        { style: "detail", d: L(bl, [[132, 840], [142, 828]]) + L(bl, [[142, 840], [152, 828]]) + L(bl, [[152, 840], [162, 828]])
                            + L(bl, [[128, 834], [166, 834]]) },
        // Head (port): vanity and sink, shower grate, toilet
        { style: "furniture", d: H(bl, 199, 670, 249, 702, 0.04) },
        { style: "sole", d: R(bl, 200, 712, 247, 730) },
        { style: "detail", d: strips(200, 247, 714, 729, 4) + L(bl, [[212, 712], [212, 730]]) + L(bl, [[224, 712], [224, 730]]) + L(bl, [[236, 712], [236, 730]]) },
        { style: "fixture", d: circle(bl(226, 0)[0], bl(0, 694)[1], 0.1) + ellipse(bl(227, 0)[0], bl(0, 741)[1], 0.15, 0.18) },
        // Engine box under the galley counter, galley (starboard)
        { style: "machine", d: R(bl, 165, 751, 250, 772) },
        { style: "furniture", d: R(bl, 159, 751, 171, 782) + R(bl, 165, 772, 250, 800) + H(bl, 165, 826, 250, 870, 0.04) },
        { style: "fixture", d: R(bl, 209, 779, 229, 797)                                                            // sink
                             + R(bl, 250, 819, 276, 837) + circle(bl(256, 0)[0], bl(0, 828)[1], 0.07) + circle(bl(269, 0)[0], bl(0, 828)[1], 0.07) // stove
                             + R(bl, 194, 829, 230, 843) },                                                       // icebox
        // Companionway ladder
        { style: "line", d: L(bl, [[254, 758], [254, 778]]) + L(bl, [[260, 758], [260, 778]]) + L(bl, [[266, 758], [266, 778]])
                          + L(bl, [[272, 758], [272, 778]]) + L(bl, [[250, 757], [276, 757]]) + L(bl, [[250, 779], [276, 779]]) },
        { style: "furniture", d: H(bl, 251, 670, 275, 712, 0.04) },                                                      // nav / locker
        // Saloon: settees, drop-leaf table round the mast post
        { style: "furniture", d: H(bl, 277, 670, 376, 704, 0.04) + H(bl, 277, 826, 376, 870, 0.04) },
        { style: "cushion", d: H(bl, 277, 704, 376, 739, 0.04) + H(bl, 277, 794, 376, 826, 0.04) },
        { style: "ghost", d: R(bl, 291, 741, 333, 790) + R(bl, 337, 741, 378, 790) },                            // table leaves
        { style: "furniture", d: R(bl, 290, 760, 330, 771) + R(bl, 338, 761, 379, 771) },
        { style: "spar", d: ellipse(MAST_X + 0.04, 0, 0.09, 0.06) },
        // Hanging lockers, V-berth, chain locker
        { style: "furniture", d: H(bl, 378, 680, 408, 738, 0.04) + H(bl, 380, 790, 408, 860, 0.04) },
        { style: "detail", d: L(bl, [[383, 806], [390, 828]]) },
        { style: "cushion", d: poly(stationSlice(bl(410, 0)[0], bl(508, 0)[0], 0.06)) },
        { style: "sole", d: R(bl, 410, 751, 440, 784) },                                                 // filler
        // Bulkheads
        { style: "wall", d: wall(195, 660, 751) + L(bl, [[195, 751], [250, 751]]) + wall(250, 660, 712) + wall(276, 660, 740)
                          + wall(276, 800, 880) + wall(165, 800, 880) + L(bl, [[120, 821], [165, 821]]) + wall(120, 821, 880)
                          + wall(377, 660, 740) + wall(377, 790, 880) + wall(409, 660, 750) + wall(409, 784, 880) + wall(510, 660, 880) },
    ],
    zones: [
        { id: "aftcabin", name: "Aft cabin", system: "Interior",
          d: poly(stationSlice(0, bl(165, 0)[0])) + H(bl, 165, 751, 195, 600), at: bl(85, 780) },
        { id: "galley", name: "Galley", system: "Interior",
          d: H(bl, 165, 772, 250, 900) + H(bl, 250, 810, 276, 900), at: bl(215, 815) },
        { id: "engine", name: "Engine", system: "Engine", d: R(bl, 165, 751, 250, 772), at: bl(207, 761) },
        { id: "head", name: "Head & shower", system: "Plumbing", d: H(bl, 195, 600, 250, 751), at: bl(222, 718) },
        { id: "ladder", name: "Companionway & engine access", system: "Engine", d: R(bl, 250, 712, 276, 810), at: bl(263, 768) },
        { id: "nav", name: "Nav station & panel", system: "Electrical", d: H(bl, 250, 600, 276, 712), at: bl(263, 696) },
        { id: "saloon", name: "Saloon & settees", system: "Interior", d: H(bl, 276, 600, 377, 940), at: bl(300, 722) },
        { id: "bilge", name: "Bilge & sump", system: "Plumbing", d: R(bl, 278, 757, 289, 778), at: bl(283, 768) },
        { id: "maststep", name: "Mast step & compression post", system: "Rigging", d: poly(circlePts(MAST_X + 0.04, 0, 0.2)), at: [MAST_X + 0.04, 0] },
        { id: "fwdlockers", name: "Hanging lockers", system: "Interior",
          d: H(bl, 377, 600, 409, 740) + H(bl, 377, 788, 409, 940), at: bl(393, 718) },
        { id: "vberth", name: "V-berth", system: "Interior", d: poly(stationSlice(bl(409, 0)[0], bl(510, 0)[0])), at: bl(470, 767) },
        { id: "chainlocker", name: "Chain locker", system: "Hull & Deck", d: poly(stationSlice(bl(510, 0)[0], 10.72)), at: bl(525, 767) },
    ],
}

var name = "S2 35C"
var specs = "35′2″ LOA · 11′6″ beam · masthead sloop"
var views = [outside, deck, below]

// The traced lines, for lofting the 3D model (BoatMesh.js).
var lines = {
    halfBreadth, hullTop, stem, counter, underbodyPx, keelPx, rudderPx, trunkPx, cockpitPx,
    mainHead, mainTack, mainClew, jibHead, jibClew, tack, forestay, backstay,
    roofPx: [[153.3, 393], [160, 382.7], [176.7, 379.3], [190, 376.7], [198.3, 375],   // cabin top, profile px
             [303.3, 374.3], [323.3, 377.3], [355, 381.7], [366, 388]],
}

// ---- lookups -------------------------------------------------------------

// Every zone is a folder: boat/<view>/<folder>/ — `path` is that relative
// path, and the folder's name is the zone's name everywhere in the app. The
// folder starts as the zone's id and follows it when you rename it (see
// applyEdits); `key` ("<view>/<id>") never changes, and names a zone in
// boat/.zones.json. (`title`, the drawing's own name for it, is unused.)
var zoneById = {}
var zoneByPath = {}
function indexZones() {
    for (const k in zoneByPath) delete zoneByPath[k]
    for (const v of views) {
        for (const z of v.zones) { z.path = v.id + "/" + z.folder; zoneByPath[z.path] = z }
        for (const l of v.layers || [])
            for (const z of l.zones) zoneByPath[z.path] = z
    }
}
for (const v of views)
    for (const z of v.zones) {
        z.view = v.id; z.key = v.id + "/" + z.id; z.folder = z.id; zoneById[z.id] = z
        z.title = z.name; z.name = z.folder
    }
indexZones()

function viewById(id) {
    for (const v of views) if (v.id === id) return v
    return null
}

function viewLabel(id) {
    for (const v of views) if (v.id === id) return v.label
    return ""
}

// Flatten a path string into polygons (for hit-testing and centroids).
function polygons(d) {
    const out = []
    const tok = d.trim().split(/[\s,]+/)
    let cur = null, last = null, cmd = "", i = 0
    const num = () => parseFloat(tok[i++])
    while (i < tok.length) {
        if (/^[MLCQZ]$/i.test(tok[i])) cmd = tok[i++].toUpperCase()
        if (cmd === "Z") { if (cur) out.push(cur); cur = null; continue }
        if (cmd === "M") { if (cur) out.push(cur); last = [num(), num()]; cur = [last]; cmd = "L"; continue }
        if (cmd === "L") { last = [num(), num()]; cur.push(last); continue }
        if (cmd === "C" || cmd === "Q") {
            const pts = [last]
            for (let k = 0; k < (cmd === "C" ? 3 : 2); ++k) pts.push([num(), num()])
            for (let s = 1; s <= 8; ++s) {
                const t = s / 8
                // de Casteljau
                let p = pts.slice()
                while (p.length > 1) {
                    const q = []
                    for (let k = 0; k < p.length - 1; ++k) q.push([p[k][0] + (p[k + 1][0] - p[k][0]) * t, p[k][1] + (p[k + 1][1] - p[k][1]) * t])
                    p = q
                }
                cur.push(p[0])
            }
            last = pts[pts.length - 1]
            continue
        }
        i++ // unknown token
    }
    if (cur && cur.length > 2) out.push(cur)
    return out
}

function inside(pt, polygon) {
    let c = false
    for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
        const a = polygon[i], b = polygon[j]
        if ((a[1] > pt[1]) !== (b[1] > pt[1]) && pt[0] < (b[0] - a[0]) * (pt[1] - a[1]) / (b[1] - a[1]) + a[0]) c = !c
    }
    return c
}

// Polygons for hit-testing, and each zone's bounding box [x0, y0, x1, y1] for zooming.
for (const v of views)
    for (const z of v.zones) {
        z.polys = polygons(z.d)
        let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity
        for (const p of z.polys)
            for (const q of p) { x0 = Math.min(x0, q[0]); y0 = Math.min(y0, q[1]); x1 = Math.max(x1, q[0]); y1 = Math.max(y1, q[1]) }
        z.bbox = [x0, y0, x1, y1]
    }

// ---- your edits ------------------------------------------------------------

// Borders and folders you've changed, kept in boat/.zones.json as
//   { "<view>/<id>": { points: [[x, y], …], folder: "…" },
//     "layers": { "<view>": [ { folder: "…", zones: [ { folder: "…", points: […], line: true? } ] } ] } }
// (metres, like everything here). The drawing above stays the original.
//
// Layers: more sets of parts over the same drawing of a view, e.g. an
// "electrical" layer over Below. A layer is a folder in the view's folder
// (boat/below/electrical/) and its parts are folders in that; they're yours
// entirely (drawn in the app), where the view's own parts ("Main") come from
// the drawing above. A layer's part is an area (a closed outline) or, with
// `line`, a line: an open run of segments, like a wire or a hose.
var original = {}
for (const v of views)
    for (const z of v.zones) original[z.key] = { d: z.d, at: z.at }

function setShape(z, d) {
    z.d = d
    z.polys = polygons(d)
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity
    for (const p of z.polys)
        for (const q of p) { x0 = Math.min(x0, q[0]); y0 = Math.min(y0, q[1]); x1 = Math.max(x1, q[0]); y1 = Math.max(y1, q[1]) }
    z.bbox = [x0, y0, x1, y1]
}

// A line part: no area, hit within a few pixels of its segments.
function setLineShape(z, pts) {
    z.d = line(pts)
    z.polys = []
    z.segs = pts
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity
    for (const q of pts) { x0 = Math.min(x0, q[0]); y0 = Math.min(y0, q[1]); x1 = Math.max(x1, q[0]); y1 = Math.max(y1, q[1]) }
    z.bbox = [x0, y0, x1, y1]
}

// The point halfway along a line, where its label goes.
function halfway(pts) {
    let total = 0
    for (let i = 1; i < pts.length; ++i) total += Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1])
    let left = total / 2
    for (let i = 1; i < pts.length; ++i) {
        const a = pts[i - 1], b = pts[i], d = Math.hypot(b[0] - a[0], b[1] - a[1])
        if (d >= left && d > 0) return [a[0] + (b[0] - a[0]) * left / d, a[1] + (b[1] - a[1]) * left / d]
        left -= d
    }
    return pts[0]
}

function segmentDistance(p, a, b) {
    const dx = b[0] - a[0], dy = b[1] - a[1], len2 = dx * dx + dy * dy
    const t = len2 ? Math.max(0, Math.min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / len2)) : 0
    return Math.hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dy)
}

// Where a polygon's label goes: its centroid (the middle of its corners if
// it has no area).
function centroid(pts) {
    let a = 0, cx = 0, cy = 0
    for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
        const k = pts[j][0] * pts[i][1] - pts[i][0] * pts[j][1]
        a += k; cx += (pts[j][0] + pts[i][0]) * k; cy += (pts[j][1] + pts[i][1]) * k
    }
    if (Math.abs(a) < 1e-9)
        return [pts.reduce((s, p) => s + p[0], 0) / pts.length, pts.reduce((s, p) => s + p[1], 0) / pts.length]
    return [cx / (3 * a), cy / (3 * a)]
}

// Put every zone back to the original, then apply `edits`.
function applyEdits(edits) {
    for (const v of views)
        for (const z of v.zones) {
            const o = original[z.key], e = edits[z.key] || {}
            z.folder = e.folder || z.id
            z.name = z.folder
            if (e.points && e.points.length >= 3) {
                setShape(z, poly(e.points))
                z.at = centroid(e.points)
            } else if (z.d !== o.d) {
                setShape(z, o.d)
                z.at = o.at
            }
        }
    const layers = edits.layers || {}
    for (const v of views)
        v.layers = (layers[v.id] || []).map(l => {
            const path = v.id + "/" + l.folder
            return {
                folder: l.folder, name: l.folder, view: v.id, path: path,
                zones: (l.zones || []).filter(q => q.points && q.points.length >= (q.line ? 2 : 3)).map(q => {
                    const z = { id: q.folder, folder: q.folder, name: q.folder, view: v.id, layer: l.folder,
                                key: path + "/" + q.folder, path: path + "/" + q.folder, line: !!q.line }
                    if (z.line) {
                        setLineShape(z, q.points)
                        z.at = halfway(q.points)
                    } else {
                        setShape(z, poly(q.points))
                        z.at = centroid(q.points)
                    }
                    return z
                })
            }
        })
    indexZones()
}

function layerByPath(path) {
    const parts = path.split("/")
    const v = viewById(parts[0])
    return v && parts.length >= 2 ? (v.layers || []).find(l => l.folder === parts[1]) || null : null
}

// The part of the boat a folder path is in (the path itself, or a parent), or null.
function zoneOf(path) {
    const parts = path ? path.split("/") : []
    for (let n = Math.min(parts.length, 3); n >= 2; --n) {
        const z = zoneByPath[parts.slice(0, n).join("/")]
        if (z) return z
    }
    return null
}

// Topmost zone at a point in view coordinates, or null. Lines count within
// `reach` (metres) of them, and win over areas they cross.
function hit(zones, x, y, reach) {
    for (let i = zones.length - 1; i >= 0; --i) {
        const z = zones[i]
        if (z.line)
            for (let k = 1; k < z.segs.length; ++k)
                if (segmentDistance([x, y], z.segs[k - 1], z.segs[k]) <= (reach || 0)) return z
    }
    for (let i = zones.length - 1; i >= 0; --i) {
        const z = zones[i]
        for (const p of z.polys) if (inside([x, y], p)) return z
    }
    return null
}

// Map a path string to pixels: x' = ox + x*s, y' = oy - y*s. Paths are
// tokenised once and cached, so re-projecting every frame of a zoom is cheap.
var tokens = {}
function project(d, s, ox, oy) {
    let t = tokens[d]
    if (!t) {
        t = d.trim().split(/[\s,]+/).map(x => /^[A-Za-z]$/.test(x) ? x : parseFloat(x))
        tokens[d] = t
    }
    const out = new Array(t.length)
    let expectX = true
    for (let i = 0; i < t.length; ++i) {
        const v = t[i]
        if (typeof v === "string") { out[i] = v; expectX = true; continue }
        out[i] = expectX ? (ox + v * s).toFixed(1) : (oy - v * s).toFixed(1)
        expectX = !expectX
    }
    return out.join(" ")
}
