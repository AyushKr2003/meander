.pragma library

// Pure geometry for Meander's keyboard cursor (KeyNav.qml). No Qt types:
// rects are { x, y, w, h } in one coordinate space, so this runs under node
// (tests/keynav.test.js).
//
// Arrows move spatially, the way a TV remote or Android's FocusFinder does:
// the next stop is the nearest control whose centre lies past the cursor in
// that direction, preferring one that shares the cursor's row or column (its
// "beam"). Tab walks reading order instead (top to bottom, then left to
// right), with a scroll view's rows kept together as one block.

function cx(r) { return r.x + r.w / 2 }
function cy(r) { return r.y + r.h / 2 }

// Is `r` past `c` in direction (dx, dy)? Its centre must be beyond the
// cursor's centre, and its far edge beyond the cursor's far edge, so a
// control that merely overlaps the cursor (a card around a button) doesn't
// count as the next one.
//
// It must also share the cursor's row (column) or lie wholly to that side:
// a wide control below the cursor isn't "to the left" of it.
function ahead(c, r, dx, dy) {
    const eps = 1
    const beam = inBeam(c, r, dx)
    if (dx > 0) return cx(r) > cx(c) + eps && r.x + r.w > c.x + c.w - eps && (beam || r.x >= c.x + c.w - eps)
    if (dx < 0) return cx(r) < cx(c) - eps && r.x < c.x + eps && (beam || r.x + r.w <= c.x + eps)
    if (dy > 0) return cy(r) > cy(c) + eps && r.y + r.h > c.y + c.h - eps && (beam || r.y >= c.y + c.h - eps)
    if (dy < 0) return cy(r) < cy(c) - eps && r.y < c.y + eps && (beam || r.y + r.h <= c.y + eps)
    return false
}

// Do `c` and `r` overlap on the axis across the direction of travel?
function inBeam(c, r, dx) {
    if (dx !== 0) return r.y < c.y + c.h && r.y + r.h > c.y
    return r.x < c.x + c.w && r.x + r.w > c.x
}

// Distance along the direction of travel (edge to edge, 0 when they touch
// or overlap) and across it (centre to centre).
function distances(c, r, dx, dy) {
    let major, minor
    if (dx > 0) { major = r.x - (c.x + c.w); minor = Math.abs(cy(r) - cy(c)) }
    else if (dx < 0) { major = c.x - (r.x + r.w); minor = Math.abs(cy(r) - cy(c)) }
    else if (dy > 0) { major = r.y - (c.y + c.h); minor = Math.abs(cx(r) - cx(c)) }
    else { major = c.y - (r.y + r.h); minor = Math.abs(cx(r) - cx(c)) }
    return { major: Math.max(0, major), minor: minor }
}

// Index into `rects` of the next stop from `c` in direction (dx, dy), or -1.
// `skip` is the cursor's own index (never picked).
function pick(c, rects, dx, dy, skip) {
    let best = -1, bestBeam = false, bestScore = Infinity
    for (let i = 0; i < rects.length; i++) {
        if (i === skip) continue
        const r = rects[i]
        if (!r || r.w <= 0 || r.h <= 0 || !ahead(c, r, dx, dy)) continue
        // A control around the cursor (a clickable card holding it) is
        // reached with Tab, not by an arrow out of it.
        if (contains(r, c)) continue
        const beam = inBeam(c, r, dx)
        const d = distances(c, r, dx, dy)
        // FocusFinder's weighting: being far along the way costs more than
        // being off to the side, so the next row wins over a far column.
        const score = 13 * d.major * d.major + d.minor * d.minor
        // A stop in the beam beats any outside it, unless the one outside is
        // clearly nearer along the way (a row of small buttons under a tall
        // card next to them).
        if (best < 0
            || (beam && !bestBeam && !(d.major > 0 && bestScore < score / 4))
            || (beam === bestBeam && score < bestScore)
            || (!beam && bestBeam && score * 4 < bestScore && distances(c, rects[best], dx, dy).major > d.major)) {
            best = i; bestBeam = beam; bestScore = score
        }
    }
    return best
}

// Reading order. Entries are { r, block, sub }: `block` is a key shared by
// the rows of one scroll view (placed at the view's top-left `r`), `sub` the
// row's index inside it; plain controls have block null.
function readingOrder(entries) {
    const rowTol = 4
    const idx = entries.map((e, i) => i)
    idx.sort((a, b) => {
        const A = entries[a], B = entries[b]
        if (A.block !== null && A.block === B.block) return A.sub - B.sub
        const dy = cy(A.r) - cy(B.r)
        if (Math.abs(dy) > rowTol) return dy
        return cx(A.r) - cx(B.r)
    })
    return idx
}

// Grow `r` by `d` on every side.
function grow(r, d) { return { x: r.x - d, y: r.y - d, w: r.w + 2 * d, h: r.h + 2 * d } }

function contains(outer, r) {
    return r.x >= outer.x - 0.5 && r.y >= outer.y - 0.5
        && r.x + r.w <= outer.x + outer.w + 0.5 && r.y + r.h <= outer.y + outer.h + 0.5
}

function intersects(a, b) {
    return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y
}

function intersect(a, b) {
    const x = Math.max(a.x, b.x), y = Math.max(a.y, b.y)
    const x2 = Math.min(a.x + a.w, b.x + b.w), y2 = Math.min(a.y + a.h, b.y + b.h)
    return { x: x, y: y, w: Math.max(0, x2 - x), h: Math.max(0, y2 - y) }
}

// How far a scroll view must move so `r` (in the view's content
// coordinates) is in sight: the new contentY / contentX, clamped.
function revealOffset(pos, size, viewPos, viewSize, contentSize, margin) {
    const maxPos = Math.max(0, contentSize - viewSize)
    let p = viewPos
    if (pos - margin < p) p = pos - margin
    else if (pos + size + margin > p + viewSize) p = pos + size + margin - viewSize
    return Math.max(0, Math.min(maxPos, p))
}

if (typeof module !== "undefined") {
    module.exports = { ahead, inBeam, distances, pick, readingOrder, grow, contains, intersects, intersect, revealOffset }
}
