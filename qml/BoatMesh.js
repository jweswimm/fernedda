.pragma library
.import "BoatS235C.js" as Boat

// The S2 35C as a 3D model, lofted from the lines traced in BoatS235C.js, so
// corrections to the drawing carry over. build() returns one mesh per material.
//
// Axes: x metres forward of the aft point (as in the drawing), y metres above
// the waterline, z metres to starboard.
//
// The drawing has no hull sections, so their shape is assumed (a superellipse
// that sharpens toward the bow). It also shows the rig only from the side, so the
// spreader lengths are assumed too.

const L = Boat.lines

// ---- curves ----------------------------------------------------------------

// Smooth curve through points with ascending x, without overshooting them.
function curve(pts) {
    const n = pts.length
    const d = []
    for (let i = 0; i < n - 1; ++i) d.push((pts[i + 1][1] - pts[i][1]) / (pts[i + 1][0] - pts[i][0]))
    const m = [d[0]]
    for (let i = 1; i < n - 1; ++i) m.push(d[i - 1] * d[i] <= 0 ? 0 : 2 * d[i - 1] * d[i] / (d[i - 1] + d[i]))
    m.push(d[n - 2])
    return x => {
        if (x <= pts[0][0]) return pts[0][1]
        if (x >= pts[n - 1][0]) return pts[n - 1][1]
        let i = 0
        while (x > pts[i + 1][0]) ++i
        const h = pts[i + 1][0] - pts[i][0], t = (x - pts[i][0]) / h, t2 = t * t, t3 = t2 * t
        return (2 * t3 - 3 * t2 + 1) * pts[i][1] + (t3 - 2 * t2 + t) * h * m[i]
             + (3 * t2 - 2 * t3) * pts[i + 1][1] + (t3 - t2) * h * m[i + 1]
    }
}
function pr(list) { return list.map(p => Boat.pr(p[0], p[1])) }
function mix(a, b, t) { return a + (b - a) * t }
function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

const X_END = Boat.pr(L.hullTop[3][0], 0)[0]           // the stemhead
const halfBeam = curve(L.halfBreadth)
// Top of the hull: up the sloped transom from the aft point, then the sheer.
const hullTopY = curve(pr([L.counter[1]].concat(L.hullTop)))
// Bottom of the hull: under the counter, the underbody, then up the stem.
const hullBottomY = curve(pr([L.counter[1]].concat(L.underbodyPx.slice(1).reverse(), L.stem.slice().reverse())))
// Port half of the cabin trunk, closed to nothing at its nose.
const trunkHalf = curve(L.trunkPx.map(p => Boat.dk(p[0], p[1])).slice(0, -1).concat([[Boat.dk(L.trunkPx[8][0], 0)[0], 0]]))
const roofY = curve(pr(L.roofPx))

const COCKPIT_AFT = Boat.dk(L.cockpitPx[0][0], 0)[0]
const COCKPIT_FWD = Boat.dk(L.cockpitPx[1][0], 0)[0]
const COCKPIT_HALF = Boat.dk(0, L.cockpitPx[0][1])[1]
const TRUNK_AFT = Boat.pr(L.roofPx[0][0], 0)[0]
const TRUNK_FWD = Boat.dk(L.trunkPx[8][0], 0)[0]
const SOLE_Y = 0.78, SEAT_Y = 1.12                     // not in the drawing

// The hull's half-width at a station and height.
function hullZ(x, y) {
    const top = hullTopY(x), bottom = hullBottomY(x)
    if (top - bottom < 1e-4) return 0
    const u = clamp((top - y) / (top - bottom), 0, 1)
    const k = x > 6 ? mix(2.6, 1.35, (x - 6) / (X_END - 6)) : 2.6      // full amidships, a V at the bow
    return halfBeam(x) * Math.pow(1 - Math.pow(u, k), 1 / k)
}
function deckY(x, z) {
    const h = Math.max(halfBeam(x), 0.01)
    return hullTopY(x) + 0.06 * (1 - Math.min(1, (z * z) / (h * h)))   // camber
}
function stations(x0, x1, n) {
    const out = []
    for (let i = 0; i <= n; ++i) out.push(mix(x0, x1, i / n))
    return out
}

// Closer together where the waterline closes in, at the counter and the forefoot.
const HULL_STATIONS = stations(0, 0.4, 6).concat(stations(0.42, 1.4, 32), stations(1.5, 9.4, 53), stations(9.45, X_END, 26))

// ---- mesh building ---------------------------------------------------------

function sub(a, b) { return [a[0] - b[0], a[1] - b[1], a[2] - b[2]] }
function cross(a, b) { return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]] }
function dot(a, b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2] }
function unit(a) {
    const l = Math.hypot(a[0], a[1], a[2])
    return l > 1e-9 ? [a[0] / l, a[1] / l, a[2] / l] : [0, 1, 0]
}
function lerp3(a, b, t) { return [mix(a[0], b[0], t), mix(a[1], b[1], t), mix(a[2], b[2], t)] }

function Mesh() { return { p: [], n: [], i: [] } }
function vert(m, p, n) { m.p.push(p); m.n.push(n); return m.p.length - 1 }
// Winds each triangle to agree with its normals: the renderer lights a face's
// back as if the normal were reversed.
function tri(m, a, b, c) {
    const f = cross(sub(m.p[b], m.p[a]), sub(m.p[c], m.p[a]))
    if (dot(f, f) < 1e-16) return
    const s = [m.n[a][0] + m.n[b][0] + m.n[c][0], m.n[a][1] + m.n[b][1] + m.n[c][1], m.n[a][2] + m.n[b][2] + m.n[c][2]]
    if (dot(f, s) >= 0) m.i.push(a, b, c)
    else m.i.push(a, c, b)
}
// Smooth surface through a grid of points. `out` says which way is outward: a
// direction, or a function of the point. `normal(row, col)`, if given, replaces
// the grid's own estimate.
function grid(m, rows, out, normal) {
    const R = rows.length, C = rows[0].length, first = m.p.length
    for (let r = 0; r < R; ++r)
        for (let c = 0; c < C; ++c) {
            const q = rows[r][c]
            let n
            if (normal) n = normal(r, c)
            else {
                const du = sub(rows[Math.min(R - 1, r + 1)][c], rows[Math.max(0, r - 1)][c])
                const dv = sub(rows[r][Math.min(C - 1, c + 1)], rows[r][Math.max(0, c - 1)])
                n = unit(cross(du, dv))
                const o = typeof out === "function" ? out(q) : out
                if (dot(n, o) < 0) n = [-n[0], -n[1], -n[2]]
            }
            vert(m, q, n)
        }
    for (let r = 0; r < R - 1; ++r)
        for (let c = 0; c < C - 1; ++c) {
            const a = first + r * C + c, b = a + 1, d = a + C, e = d + 1
            tri(m, a, b, e)
            tri(m, a, e, d)
        }
}
function quad(m, a, b, c, d) {
    const n = unit(cross(sub(b, a), sub(d, a)))
    const i = [vert(m, a, n), vert(m, b, n), vert(m, c, n), vert(m, d, n)]
    tri(m, i[0], i[1], i[2])
    tri(m, i[0], i[2], i[3])
}
function box(m, x0, x1, y0, y1, z0, z1) {
    quad(m, [x0, y1, z0], [x0, y1, z1], [x1, y1, z1], [x1, y1, z0])
    quad(m, [x0, y0, z0], [x1, y0, z0], [x1, y0, z1], [x0, y0, z1])
    quad(m, [x0, y0, z0], [x0, y0, z1], [x0, y1, z1], [x0, y1, z0])
    quad(m, [x1, y0, z0], [x1, y1, z0], [x1, y1, z1], [x1, y0, z1])
    quad(m, [x0, y0, z0], [x0, y1, z0], [x1, y1, z0], [x1, y0, z0])
    quad(m, [x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1])
}
// A round bar from a to b, optionally with flat ends.
function tube(m, a, b, r, capped) {
    const axis = unit(sub(b, a))
    const u = unit(cross(axis, Math.abs(axis[1]) > 0.9 ? [1, 0, 0] : [0, 1, 0]))
    const v = cross(axis, u)
    const N = capped ? 14 : 5
    const dirs = []
    for (let i = 0; i < N; ++i) {
        const t = i / N * Math.PI * 2, c = Math.cos(t), s = Math.sin(t)
        dirs.push([u[0] * c + v[0] * s, u[1] * c + v[1] * s, u[2] * c + v[2] * s])
    }
    const ring = (o, d) => [o[0] + d[0] * r, o[1] + d[1] * r, o[2] + d[2] * r]
    const first = m.p.length
    for (const d of dirs) { vert(m, ring(a, d), d); vert(m, ring(b, d), d) }
    for (let i = 0; i < N; ++i) {
        const j = (i + 1) % N
        const p = first + i * 2, q = first + j * 2
        tri(m, p, p + 1, q + 1)
        tri(m, p, q + 1, q)
    }
    if (capped) for (const [o, n] of [[a, [-axis[0], -axis[1], -axis[2]]], [b, axis]]) {
        const c = vert(m, o, n)
        const k = m.p.length
        for (const d of dirs) vert(m, ring(o, d), n)
        for (let i = 0; i < N; ++i) tri(m, c, k + i, k + (i + 1) % N)
    }
}
function bars(m, pts, r) {
    for (let i = 0; i < pts.length - 1; ++i) tube(m, pts[i], pts[i + 1], r)
}

// ---- the boat --------------------------------------------------------------

function hullBand(m, yLo, yHi, rows, keelward) {
    const xs = HULL_STATIONS
    for (const side of [-1, 1]) {
        const g = xs.map(x => {
            const top = hullTopY(x), bottom = hullBottomY(x)
            const y1 = clamp(yHi(x), bottom, top), y0 = clamp(yLo(x), bottom, top)
            const row = []
            for (let j = 0; j <= rows; ++j) {
                const t = j / rows
                const y = mix(y1, y0, keelward ? 1 - (1 - t) * (1 - t) : t)     // closer rows at the turn of the keel
                row.push([x, y, side * hullZ(x, y)])
            }
            return row
        })
        // Normals from the surface itself, so the bands of colour don't show a seam.
        grid(m, g, null, (r, c) => {
            const q = g[r][c], e = 0.02
            const x0 = Math.max(0, q[0] - e), x1 = Math.min(X_END, q[0] + e)
            const dzdx = (hullZ(x1, q[1]) - hullZ(x0, q[1])) / (x1 - x0)
            const dzdy = (hullZ(q[0], q[1] + e) - hullZ(q[0], q[1] - e)) / (2 * e)
            return unit([-dzdx * side, -dzdy * side, side])
        })
    }
}

function deckGrid(m, x0, x1, n, zOf) {
    const g = stations(x0, x1, n).map(x => {
        const row = []
        for (let j = 0; j <= 8; ++j) {
            const z = zOf(x, j / 8)
            row.push([x, deckY(x, z), z])
        }
        return row
    })
    grid(m, g, [0, 1, 0])
}

function buildDeck(m, transom) {
    const across = (x, t) => mix(-halfBeam(x), halfBeam(x), t)
    const transomTop = Boat.pr(L.hullTop[0][0], 0)[0]
    deckGrid(transom, 0, transomTop, 12, across)                // the sloped transom is hull, not deck
    deckGrid(m, transomTop, COCKPIT_AFT, 14, across)
    deckGrid(m, COCKPIT_FWD, X_END, 40, across)
    for (const s of [-1, 1])                                    // the side decks past the cockpit
        deckGrid(m, COCKPIT_AFT, COCKPIT_FWD, 12, (x, t) => s * mix(COCKPIT_HALF, halfBeam(x), t))
}

// The trunk's side wall leans in a little from deck to roof.
const LEAN = 0.07
function wallZ(x, y) {
    const base = deckY(x, trunkHalf(x)), roof = roofY(x)
    return trunkHalf(x) - LEAN * clamp((y - base) / Math.max(0.01, roof - base), 0, 1)
}
function roofAt(x, z) {
    const w = Math.max(0.01, trunkHalf(x) - LEAN)
    return Math.max(roofY(x) - 0.05 * (z * z) / (w * w), deckY(x, z) + 0.005)
}
function roofGrid(m, x0, x1, n, zOf) {
    const g = stations(x0, x1, n).map(x => {
        const row = []
        for (let j = 0; j <= 8; ++j) {
            const z = zOf(x, j / 8)
            row.push([x, roofAt(x, z), z])
        }
        return row
    })
    grid(m, g, [0, 1, 0])
}

function buildTrunk(m) {
    for (const s of [-1, 1]) {
        const g = stations(TRUNK_AFT, TRUNK_FWD, 44).map(x => {
            const z = Math.max(0, trunkHalf(x))
            return [[x, deckY(x, z), s * z], [x, roofAt(x, Math.max(0, z - LEAN)), s * Math.max(0, z - LEAN)]]
        })
        grid(m, g, [0, 0, s])
    }
    const across = (x, t) => { const w = Math.max(0, trunkHalf(x) - LEAN); return mix(-w, w, t) }
    roofGrid(m, TRUNK_AFT, COCKPIT_AFT, 10, across)
    roofGrid(m, COCKPIT_FWD, TRUNK_FWD, 30, across)
    for (const s of [-1, 1])                                    // the coamings beside the cockpit
        roofGrid(m, COCKPIT_AFT, COCKPIT_FWD, 12, (x, t) => s * mix(COCKPIT_HALF, trunkHalf(x) - LEAN, t))
}

function buildCockpit(m) {
    const h = COCKPIT_HALF, a = COCKPIT_AFT, f = COCKPIT_FWD
    quad(m, [a, SOLE_Y, -h], [a, SOLE_Y, h], [f, SOLE_Y, h], [f, SOLE_Y, -h])
    for (const s of [-1, 1]) {
        grid(m, stations(a, f, 12).map(x => [[x, SOLE_Y, s * h], [x, roofAt(x, s * h), s * h]]), [0, 0, -s])
    }
    const across = x => stations(-h, h, 8).map(z => [x, SOLE_Y, z])
    const ends = x => across(x).map(p => [x, roofAt(x, p[2]), p[2]])
    grid(m, [across(a), ends(a)], [1, 0, 0])
    grid(m, [across(f), ends(f)], [-1, 0, 0])
    for (const s of [-1, 1])
        box(m, Boat.dk(140, 0)[0], Boat.dk(237, 0)[0], SOLE_Y, SEAT_Y, s * 0.48, s * h)
}

function buildHelm(wire) {
    const x = Boat.dk(172, 0)[0], y = SOLE_Y + 0.85, r = Boat.dk(0, 553)[1]
    tube(wire, [x + 0.06, SOLE_Y, 0], [x + 0.06, y, 0], 0.05)
    const rim = []
    for (let i = 0; i <= 24; ++i) {
        const t = i / 24 * Math.PI * 2
        rim.push([x, y + r * Math.sin(t), r * Math.cos(t)])
    }
    bars(wire, rim, 0.016)
    for (let i = 0; i < 24; i += 8) tube(wire, [x, y, 0], rim[i], 0.012)
}

// A hatch on the roof, drawn in deck-plan pixels.
function hatch(frame, glass, X0, Y0, X1, Y1) {
    const a = Boat.dk(X0, Y0), b = Boat.dk(X1, Y1)
    const y = Math.max(roofAt(a[0], a[1]), roofAt(b[0], a[1]), roofAt(a[0], b[1]), roofAt(b[0], b[1]))
    box(frame, a[0], b[0], y - 0.08, y + 0.04, a[1], b[1])
    box(glass, a[0] + 0.03, b[0] - 0.03, y + 0.04, y + 0.047, Math.min(a[1], b[1]) + 0.03, Math.max(a[1], b[1]) - 0.03)
}

function buildDeckGear(frame, glass, spar) {
    hatch(frame, glass, 73, 562, 96, 589)
    hatch(frame, glass, 273, 553, 312, 596)
    hatch(frame, glass, 393, 558, 425, 592)
    for (const [y0, y1] of [[526, 541], [609, 624]]) hatch(frame, glass, 253, y0, 268, y1)
    box(frame, Boat.dk(248, 0)[0], Boat.dk(272, 0)[0], roofY(4.9) - 0.06, roofY(4.9) + 0.06, -0.36, 0.36)     // companionway slide
    for (const [X, Y] of [[296, 539], [296, 603]]) {                                                         // dorades
        const a = Boat.dk(X, Y)
        box(frame, a[0], a[0] + 0.16, roofAt(a[0], a[1]) - 0.02, roofAt(a[0], a[1]) + 0.12, a[1] - 0.16, a[1])
    }
    for (const [X, Y] of [[80, 530], [80, 620], [192, 527], [192, 623]]) {                                   // winches
        const a = Boat.dk(X, Y), y = roofAt(a[0], a[1])
        tube(spar, [a[0], y - 0.02, a[1]], [a[0], y + 0.2, a[1]], 0.09, true)
    }
    const nose = hullTopY(X_END)                                                                             // bow roller
    box(spar, X_END - 0.3, X_END + 0.32, nose - 0.02, nose + 0.05, -0.05, 0.05)
}

function buildPortlights(glass) {
    const rects = [[173.3, 386, 196, 390], [225, 385, 246.7, 390], [253.3, 385, 296.7, 390],
                   [328.3, 384, 339.3, 388.3], [340.7, 384, 350, 388.3]]
    for (const r of rects) {
        const a = Boat.pr(r[0], r[3]), b = Boat.pr(r[2], r[1])
        for (const s of [-1, 1])
            grid(glass, stations(a[0], b[0], 6).map(x =>
                [[x, a[1], s * (wallZ(x, a[1]) + 0.006)], [x, b[1], s * (wallZ(x, b[1]) + 0.006)]]), [0, 0, s])
    }
}

// A fin, from its traced outline: `rows` of [aft x, forward x, y] down the span.
function foil(m, rows, thickness) {
    const N = 16
    const ring = r => {
        const out = []
        for (let i = 0; i <= N; ++i) {
            const t = i / N * Math.PI * 2, s = (1 - Math.cos(t)) / 2     // aft edge → forward edge → back
            const h = thickness * (r[1] - r[0]) * (1 - s) * Math.sqrt(s) * 2.6 * (t < Math.PI ? 1 : -1)
            out.push([mix(r[1], r[0], s), r[2], h])
        }
        return out
    }
    // Close the tip with a last, slightly thinner ring run to a line.
    const span = rows.map(ring)
    const last = rows[rows.length - 1]
    span.push(ring([last[0] + 0.01, last[1] - 0.01, last[2] - 0.015]).map(q => [q[0], q[1], q[2] * 0.15]))
    grid(m, span, q => [0, -0.15, q[2]])
}

function buildUnderwater(m) {
    const k = L.keelPx.map(p => Boat.pr(p[0], p[1]))             // aft-top, aft-bottom, fwd-bottom, knuckle, fwd-top
    const kRows = []
    for (let i = -1; i <= 8; ++i) {
        const t = i / 8
        const y = mix(k[0][1], k[1][1], t)
        const aft = mix(k[0][0], k[1][0], t)
        const fwd = mix(k[4][0], k[3][0], t)
        kRows.push([aft, fwd, y])
    }
    foil(m, kRows, 0.06)

    const r = L.rudderPx.map(p => Boat.pr(p[0], p[1]))           // aft-top, aft-bottom, fwd-bottom, fwd-top
    const rRows = []
    for (let i = -1; i <= 6; ++i) {
        const t = i / 6
        rRows.push([mix(r[0][0], r[1][0], t), mix(r[3][0], r[2][0], t), mix(r[0][1], r[1][1], t)])
    }
    foil(m, rRows, 0.05)
}

function buildSpars(spar, wire) {
    const mastX = (L.mainHead[0] + Boat.pr(299.3, 0)[0]) / 2
    const mastTop = Boat.pr(0, 9)[1], mastBase = roofAt(mastX, 0) - 0.05
    // Mast: a tapered oval, as in the deck plan.
    const g = stations(mastBase, mastTop, 12).map(y => {
        const t = clamp((y - 10) / (mastTop - 10), 0, 1)
        const row = []
        for (let i = 0; i <= 12; ++i) {
            const a = i / 12 * Math.PI * 2
            row.push([mastX + mix(0.14, 0.08, t) * Math.cos(a), y, mix(0.09, 0.05, t) * Math.sin(a)])
        }
        return row
    })
    grid(spar, g, q => [q[0] - mastX, 0, q[2]])
    box(spar, mastX - 0.09, mastX + 0.09, mastTop, mastTop + 0.08, -0.06, 0.06)

    tube(spar, [mastX - 0.05, L.mainTack[1] - 0.05, 0], [L.mainClew[0], L.mainTack[1] - 0.05, MAIN_CLEW_Z], 0.055)   // boom

    // Forestay, backstay, shrouds.
    const stay = 0.014
    tube(wire, [L.forestay[0][0], L.forestay[0][1], 0], [L.forestay[1][0], L.forestay[1][1], 0], stay)
    tube(wire, [L.backstay[0][0], L.backstay[0][1], 0], [L.backstay[1][0], L.backstay[1][1], 0], stay)
    const upperY = Boat.pr(0, 150)[1], lowerY = Boat.pr(0, 245)[1]
    const upperAft = Boat.pr(288, 0)[0] - mastX, lowerAft = Boat.pr(286, 0)[0] - mastX
    for (const s of [-1, 1]) {
        const plate = mastX - 0.2, chain = s * (halfBeam(plate) - 0.1), foot = deckY(plate, chain)
        const up = [mastX + upperAft, upperY, s * 0.55], lo = [mastX + lowerAft, lowerY, s * 0.95]
        tube(spar, [mastX, upperY, 0], up, 0.022)
        tube(spar, [mastX, lowerY, 0], lo, 0.026)
        bars(wire, [[mastX, mastTop - 0.15, 0], up, lo, [plate, foot, chain]], stay)
        tube(wire, [mastX, lowerY, 0], [plate - 0.5, deckY(plate - 0.5, chain), chain], stay)
        tube(wire, [mastX, lowerY, 0], [plate + 0.55, deckY(plate + 0.55, chain), chain], stay)
    }
    // Antenna and wind vane.
    tube(wire, [mastX, mastTop, 0], [mastX, Boat.pr(0, 2)[1], 0], 0.012)
    tube(wire, [mastX, Boat.pr(0, 5)[1], 0], [Boat.pr(290, 0)[0], Boat.pr(0, 5)[1], 0], 0.012)
}

function buildRails(wire) {
    const r = 0.016, topY = Boat.pr(0, 373)[1], midY = Boat.pr(0, 382)[1]
    const pushpit = [[1.01, 1.27], [0.42, 1.05], [0.22, 0.6], [0.2, 0], [0.22, -0.6], [0.42, -1.05], [1.01, -1.27]]
    bars(wire, pushpit.map(p => [p[0], topY, p[1]]), r)
    for (const p of pushpit) tube(wire, [p[0], topY, p[1]], [p[0], hullTopY(p[0]) + 0.01, p[1]], r)

    const pulpit = [[9.68, 0.36], [10.5, 0.22], [10.72, 0.12], [10.8, 0], [10.72, -0.12], [10.5, -0.22], [9.68, -0.36]]
    const pulpitY = Boat.pr(0, 371.7)[1]
    bars(wire, pulpit.map(p => [p[0], pulpitY, p[1]]), r)
    for (const p of [pulpit[0], pulpit[1], pulpit[5], pulpit[6], pulpit[3]]) {
        const x = Math.min(p[0], X_END)
        tube(wire, [p[0], pulpitY, p[1]], [x, hullTopY(x) + 0.01, p[1] * (x < X_END ? 1 : 0)], r)
    }

    for (const s of [-1, 1]) {
        const posts = [1.9, 3.9, 5.6, 7.0, 8.3].map(x => [x, s * (halfBeam(x) - 0.1)])
        for (const p of posts) tube(wire, [p[0], deckY(p[0], p[1]), p[1]], [p[0], topY, p[1]], r)
        for (const y of [topY, midY]) {
            const run = [[1.01, y, s * 1.27]].concat(posts.map(p => [p[0], y, p[1]]), [[9.68, y, s * 0.36]])
            bars(wire, run, 0.008)
        }
    }
}

// ---- sails -----------------------------------------------------------------

const MAIN_CLEW_Z = 0.35, JIB_CLEW_Z = 0.7

// A sail: for s along the luff (0 tack, 1 head) and t across (0 luff, 1 leech).
function sailPoint(sail, s, t) {
    const lu = [mix(sail.tack[0], sail.head[0], s), mix(sail.tack[1], sail.head[1], s)]
    const le = sail.leech(s)
    const x = mix(lu[0], le[0], t), y = mix(lu[1], le[1], t)
    const chord = Math.hypot(le[0] - lu[0], le[1] - lu[1])
    return [x, y, sail.clewZ * (1 - s) * t + sail.belly * chord * 4 * t * (1 - t)]
}
function buildSail(cloth, seams, sail, seamCount) {
    const rows = []
    for (const s of stations(0, 0.995, 28)) rows.push(stations(0, 1, 10).map(t => sailPoint(sail, s, t)))
    grid(cloth, rows, [0, 0, 1])
    for (let i = 1; i < seamCount; ++i) {
        const s = i / seamCount
        bars(seams, stations(0, 1, 6).map(t => {
            const q = sailPoint(sail, Math.min(0.995, s + 0.04 * t), t)
            return [q[0], q[1], q[2] + 0.004]
        }), 0.007)
    }
}
function buildSails(cloth, seams) {
    const control = Boat.pr(226, 170)
    buildSail(cloth, seams, {
        tack: L.mainTack, head: L.mainHead, clewZ: MAIN_CLEW_Z, belly: 0.06,
        leech: s => {                                                 // the roach, as in the drawing
            const u = 1 - s
            return [u * u * L.mainClew[0] + 2 * u * s * control[0] + s * s * L.mainHead[0],
                    u * u * L.mainClew[1] + 2 * u * s * control[1] + s * s * L.mainHead[1]]
        }
    }, 12)
    buildSail(cloth, seams, {
        tack: L.tack, head: L.jibHead, clewZ: JIB_CLEW_Z, belly: 0.07,
        leech: s => [mix(L.jibClew[0], L.jibHead[0], s), mix(L.jibClew[1], L.jibHead[1], s)]
    }, 13)
}

// ---- assembly --------------------------------------------------------------

function buildWater(m) {
    const R = 7.3, rings = 2, segs = 72
    const g = stations(0, 1, rings).map(t => stations(0, Math.PI * 2, segs).map(a =>
        [centre + R * t * Math.cos(a), 0, R * t * Math.sin(a)]))
    grid(m, g, [0, 1, 0], () => [0, 1, 0])
}

// The boat turns about its middle.
var centre = X_END / 2

function build() {
    const parts = {}
    const part = name => (parts[name] = Mesh())

    const topsides = part("topsides"), bottom = part("bottom"), stripe = part("stripe"), deck = part("deck")
    const house = part("house"), well = part("well"), glass = part("glass")
    const spar = part("spar"), wire = part("wire"), sail = part("sail"), seam = part("seam"), water = part("water")

    const coveAft = Boat.pr(L.hullTop[0][0], 397.3), coveFwd = Boat.pr(403.3, 395)
    const cove = x => mix(coveAft[1], coveFwd[1], (x - coveAft[0]) / (coveFwd[0] - coveAft[0]))
    const BOOT = 0.08
    const below = () => -9, above = () => 9
    hullBand(bottom, below, () => 0, 12, true)
    hullBand(stripe, () => 0, () => BOOT, 1)
    hullBand(topsides, () => BOOT, x => cove(x) - 0.03, 10, true)
    hullBand(stripe, x => cove(x) - 0.03, x => cove(x) + 0.03, 1)
    hullBand(topsides, x => cove(x) + 0.03, above, 2)
    buildUnderwater(bottom)

    buildDeck(deck, topsides)
    buildTrunk(house)
    buildCockpit(well)
    buildHelm(spar)
    buildDeckGear(house, glass, spar)
    buildPortlights(glass)
    buildSpars(spar, wire)
    buildRails(wire)
    buildSails(sail, seam)
    buildWater(water)

    // Propeller and shaft (the drawing's guess: just aft of the keel).
    const shaftA = Boat.pr(236, 436), shaftB = Boat.pr(214, 437.5)
    tube(spar, [shaftA[0], shaftA[1], 0], [shaftB[0], shaftB[1], 0], 0.02)
    tube(spar, [shaftB[0] - 0.02, shaftB[1], 0], [shaftB[0] + 0.04, shaftB[1], 0], 0.2, true)

    const out = {}
    for (const k in parts) {
        const m = parts[k]
        out[k] = {
            positions: m.p.map(q => Qt.vector3d(q[0], q[1], q[2])),
            normals: m.n.map(q => Qt.vector3d(q[0], q[1], q[2])),
            indexes: m.i
        }
    }
    return out
}
