import QtQuick
import "../"
import "KeyNavLogic.js" as Logic

// Meander's keyboard cursor. No Serpantinum original: upstream's popouts,
// bar and dock are pointer-only (its reusable buttons take Tab focus, but
// nothing draws it and most controls are bare MouseAreas). Ported in spirit
// from Omacale's panel keys (components/KeyNav.qml + PopoutContent's cursor),
// themselves Omarchy's Ui/PanelKeyCatcher keys:
//
//   arrows, h j k l      move to the nearest control that way
//   Tab, Shift+Tab       next / previous control in reading order
//   Home, End            first / last control
//   Enter, Space         activate (a click)
//   Menu, Shift+F10      secondary action (a right click)
//   Left/Right on a slider   change its value (Shift: by 1)
//   Ctrl+Tab, Ctrl+Shift+Tab next / previous panel (cycleRequested)
//
// A popout's own Shortcuts win over Keys handlers: the owner claims the
// cursor's keys with claims() from Keys.onShortcutOverride (the calendar's
// Left/Right), while upstream's Tab (music, volume, network: sections) stays.
// With `vimKeysOnly` (the calendar) the arrows are never taken: h j k l move
// the cursor and the arrows keep doing what upstream made them do.
//
// It works on upstream's code as it is, so upstream merges stay clean: the
// controls are found by walking `scope` on every key, not declared. A stop
// is a MouseArea with the pointing-hand cursor (how every upstream button
// says it is clickable), an item that takes Tab focus (upstream's reusable
// buttons, toggles, inputs), a slider, or a text field.
//
// Enter emits the control's MouseArea clicked() with no event: QML can't
// build a MouseEvent (a plain object passed for one arrives as null, which
// is why upstream's own Enter handler in ClickButton threw). The few
// handlers that read `mouse.button` ask KeyNavState.buttonOf(mouse)
// instead, which is the button KeyNav meant (right for Menu / Shift+F10).
// QtTest's TestEvent would send real events, but importing QtTest crashed
// the shell while loading (in Quickshell's import resolution), so no.
// Any item can opt in or out: `keyNavTarget: true|false`, `keyNavSkip: true`
// (the whole subtree), and `keyNavActivate()` replaces the synthetic click.
// `keyNavRingItem: someItem` draws the ring around that item instead.
//
// The owner sizes this item over the surface, sets `scope`, and calls
// handle(event) from a Keys.onPressed above the scope: keys a focused child
// accepts (a text field's letters, a slider's arrows) never reach it.
Item {
    id: root

    property Item scope: null
    // Where focus goes back to when the cursor leaves a text field or a
    // focusable control (defaults to the scope).
    property Item focusHome: scope
    // Off: every key passes through and nothing is drawn.
    property bool active: true
    // Only h j k l move the cursor; the arrow keys stay the surface's own
    // (the calendar: Left/Right flip the month or the weather day, upstream).
    property bool vimKeysOnly: false

    // The ring shows only while the keyboard is in use; moving the pointer
    // hides it (the cursor is kept for the next key).
    property bool keyMode: false
    property Item cursor: null
    property string cursorKind: ""
    property int cursorIndex: -1

    readonly property bool ringShown: active && keyMode && cursor !== null && ring.rect.w > 0

    signal cycleRequested(int direction)
    // `secondary`: Menu / Shift+F10 (a right click).
    signal activated(Item target, bool secondary)

    // ------------------------------------------------------------ discovery

    function isMouseArea(it) {
        return it.pressAndHoldInterval !== undefined && it.containsMouse !== undefined && it.acceptedButtons !== undefined
    }
    function isTextField(it) {
        return it.cursorPosition !== undefined && it.selectByMouse !== undefined && typeof it.selectAll === "function"
    }
    function isFlickable(it) {
        return it.contentY !== undefined && it.contentItem !== undefined && it.flickableDirection !== undefined
    }
    function kindOf(it) {
        if (it.keyNavTarget === false) return ""
        if (it.keyNavTarget === true) return "button"
        // Draggable (nudge) and SliderProgress (value + moved).
        if (it.from !== undefined && it.to !== undefined && it.value !== undefined
            && (typeof it.nudge === "function" || typeof it.moved === "function")) return "slider"
        if (isTextField(it)) return it.readOnly ? "" : "text"
        if (it.activeFocusOnTab === true && it !== scope) {
            // Steppers and dropdowns keep their own keys (they get focus);
            // upstream's plain buttons, toggles and checkboxes are clicked.
            if (typeof it.stepUp === "function" || it.isOpen !== undefined || typeof it.closePopup === "function") return "focus"
            return "button"
        }
        if (isMouseArea(it) && it.cursorShape === Qt.PointingHandCursor && (it.acceptedButtons & (Qt.LeftButton | Qt.RightButton))) return "mouse"
        return ""
    }

    // The item's box as drawn: mapped through its own and its ancestors'
    // transforms (scale, rotation, Translate), so a scaled control (the
    // calendar's hour cards shrink with depth) gets a ring its own size.
    function rectOf(it) {
        const m = it.mapToItem(root, Qt.rect(0, 0, it.width, it.height))
        return { x: m.x, y: m.y, w: m.width, h: m.height }
    }

    // Every stop, as { t, kind, r, flick, clip, block, sub }. `clip` is the
    // part of the surface the stop can be seen through (its clipping
    // ancestors, the scope); a stop inside a scroll view counts even when
    // scrolled out of sight, since moving to it scrolls it in.
    function collect() {
        const out = []
        if (!scope || !scope.visible) return out
        const scopeRect = rectOf(scope)
        const walk = (it, clip, flick, block) => {
            if (!it || !it.visible || it.opacity < 0.05 || it.enabled === false) return
            if (it.keyNavSkip === true) return
            if (it !== scope) {
                const k = kindOf(it)
                if (k !== "" && it.width > 1 && it.height > 1) {
                    const r = rectOf(it)
                    const seen = flick ? flick.view.w > 0 && flick.view.h > 0 : Logic.intersects(r, clip)
                    if (seen)
                        out.push({ t: it, kind: k, r: r, flick: flick ? flick.item : null, clip: clip, block: block, sub: 0 })
                    // A clickable card can hold its own buttons; everything
                    // else is one stop.
                    if (k !== "mouse") return
                }
            }
            let c = clip, f = flick, b = block
            if (it !== scope && isFlickable(it) && it.interactive !== false) {
                const vr = rectOf(it)
                f = { item: it, view: Logic.intersect(vr, clip) }
                b = it
                c = Logic.intersect(vr, clip)
            } else if (it.clip && it !== scope && !f) {
                c = Logic.intersect(rectOf(it), clip)
                if (c.w <= 0 || c.h <= 0) return
            }
            const kids = it.children
            for (let i = 0; i < kids.length; i++) walk(kids[i], c, f, b)
        }
        walk(scope, scopeRect, null, null)
        // Rows of one scroll view, in content order; the block sorts where
        // the view's top sits.
        const blocks = new Map()
        for (const e of out) {
            if (!e.block) { e.block = null; continue }
            if (!blocks.has(e.block)) blocks.set(e.block, [])
            blocks.get(e.block).push(e)
        }
        blocks.forEach((rows, view) => {
            rows.sort((a, b) => Math.abs(a.r.y - b.r.y) > 4 ? a.r.y - b.r.y : a.r.x - b.r.x)
            const top = rectOf(view)
            rows.forEach((e, i) => { e.sub = i; e.orderRect = { x: top.x, y: top.y, w: 1, h: 1 } })
        })
        return out
    }

    function ordered() {
        const es = collect()
        const order = Logic.readingOrder(es.map(e => ({ r: e.orderRect || e.r, block: e.block, sub: e.sub })))
        return order.map(i => es[i])
    }

    // ---------------------------------------------------------------- moves

    function setCursor(e) {
        if (!e) {
            cursor = null; cursorKind = ""
            return
        }
        cursor = e.t
        cursorKind = e.kind
        reveal(e)
        ring.glide()
        // Upstream's own focusable controls handle Enter and arrows
        // themselves once they hold focus; a text field takes the typing.
        if (e.kind === "focus" || e.kind === "text") e.t.forceActiveFocus()
        else homeFocus()
    }

    // Take focus back from a field or button the cursor has left, so it
    // stops eating keys.
    function homeFocus() {
        const w = root.Window.window
        const f = w ? w.activeFocusItem : null
        if (!f || !focusHome) return
        if (f === focusHome) return
        for (let p = f; p; p = p.parent) if (p === scope) { focusHome.forceActiveFocus(); return }
    }

    function reveal(e) {
        const v = e.flick
        if (!v) return
        const r = e.t.mapToItem(v.contentItem, 0, 0)
        const m = 8
        if (v.contentHeight > v.height + 1)
            v.contentY = Logic.revealOffset(r.y, e.t.height, v.contentY, v.height, v.contentHeight, m) + (v.originY || 0)
        if (v.contentWidth > v.width + 1)
            v.contentX = Logic.revealOffset(r.x, e.t.width, v.contentX, v.width, v.contentWidth, m) + (v.originX || 0)
    }

    function indexOfCursor(es) {
        if (!cursor) return -1
        for (let i = 0; i < es.length; i++) if (es[i].t === cursor) return i
        return -1
    }

    function first() {
        const es = ordered()
        if (es.length) { cursorIndex = 0; setCursor(es[0]) }
        return es.length > 0
    }
    function last() {
        const es = ordered()
        if (es.length) { cursorIndex = es.length - 1; setCursor(es[es.length - 1]) }
    }
    function step(d) {
        const es = ordered()
        if (!es.length) { setCursor(null); return }
        let i = indexOfCursor(es)
        if (i < 0) i = cursorIndex < 0 ? (d > 0 ? -1 : es.length) : Math.min(cursorIndex, es.length) - (d > 0 ? 1 : 0)
        i = (i + d + es.length) % es.length
        cursorIndex = i
        setCursor(es[i])
    }

    // Arrow keys. Inside a scroll view whose next rows aren't built yet (a
    // ListView only makes what is near the view), scroll first and look
    // again once they exist.
    property int pendingDx: 0
    property int pendingDy: 0
    function move(dx, dy, retried) {
        const es = collect()
        const i = indexOfCursor(es)
        if (i < 0) { if (!first()) return; return }
        const c = es[i]
        const j = Logic.pick(c.r, es.map(e => e.r), dx, dy, i)
        const v = c.flick
        const leaving = j < 0 || es[j].flick !== v
        if (v && leaving && !retried && scrollBy(v, dx, dy)) {
            pendingDx = dx; pendingDy = dy
            retry.restart()
            return
        }
        if (j < 0) return
        cursorIndex = ordered().findIndex(e => e.t === es[j].t)
        setCursor(es[j])
    }
    function scrollBy(v, dx, dy) {
        if (dy !== 0 && v.contentHeight > v.height + 1) {
            const top = v.originY || 0
            const max = top + v.contentHeight - v.height
            const ny = Math.max(top, Math.min(max, v.contentY + dy * v.height * 0.5))
            if (Math.abs(ny - v.contentY) < 1) return false
            v.contentY = ny
            return true
        }
        if (dx !== 0 && v.contentWidth > v.width + 1) {
            const left = v.originX || 0
            const max = left + v.contentWidth - v.width
            const nx = Math.max(left, Math.min(max, v.contentX + dx * v.width * 0.5))
            if (Math.abs(nx - v.contentX) < 1) return false
            v.contentX = nx
            return true
        }
        return false
    }
    Timer {
        id: retry
        interval: 40
        onTriggered: root.move(root.pendingDx, root.pendingDy, true)
    }

    function nearest(it, name) {
        for (let p = it; p && p !== scope; p = p.parent)
            if (typeof p[name] === "function") return p
        return null
    }

    function activate(secondary, modifiers) {
        const t = cursor
        if (!t) return false
        const own = nearest(t, "keyNavActivate")
        if (own && !secondary) { own.keyNavActivate(); activated(t, false); return true }
        if (cursorKind === "text") { t.forceActiveFocus(); return true }
        if (cursorKind === "slider") return false
        const btn = secondary ? Qt.RightButton : Qt.LeftButton
        const ma = cursorKind === "mouse" ? t : findMouseArea(t)
        if (ma && !(ma.acceptedButtons & btn)) return false
        click(t, btn, modifiers || Qt.NoModifier)
        activated(t, !!secondary)
        return true
    }
    function click(t, btn, mods) {
        const ma = isMouseArea(t) ? t : findMouseArea(t)
        if (!ma) return
        KeyNavState.button = btn
        try { ma.clicked(null) } finally { KeyNavState.button = Qt.LeftButton }
    }
    function findMouseArea(it) {
        if (isMouseArea(it) && it.enabled) return it
        for (let i = 0; i < it.children.length; i++) {
            const m = findMouseArea(it.children[i])
            if (m) return m
        }
        return null
    }

    // A slider takes the arrows along its own axis (up = more on a vertical
    // one); the other two still move the cursor.
    function adjust(dx, dy, fine) {
        if (cursorKind !== "slider" || !cursor) return false
        const s = cursor
        if (s.vertical === true) { if (dy === 0) return false; dx = -dy }
        else { if (dx === 0) return false; if (I18n.rtl) dx = -dx }
        const span = Math.abs(s.to - s.from)
        const unit = s.stepSize > 0 ? s.stepSize : span / 100
        // 5% a press, a single step with Shift.
        const n = fine ? 1 : Math.max(1, Math.round(span * 0.05 / unit))
        if (typeof s.nudge === "function") {
            for (let i = 0; i < n; i++) s.nudge(dx)
            if (typeof s.dragFinished === "function") s.dragFinished()
        } else if (typeof s.increase === "function" && typeof s.decrease === "function") {
            // A Qt Quick Controls Slider (the music EQ): as its own arrow
            // keys do, then moved() with no argument (it takes none).
            for (let i = 0; i < n; i++) dx > 0 ? s.increase() : s.decrease()
            s.moved()
        } else {
            // SliderProgress: as its own arrow keys do.
            s.value = Math.max(Math.min(s.from, s.to), Math.min(Math.max(s.from, s.to), s.value + dx * n * unit))
            s.moved(s.value)
        }
        return true
    }

    // ------------------------------------------------------------ the keys

    function handle(event) {
        if (!active || !scope) return false
        const k = event.key
        const t = event.text
        const mods = event.modifiers
        const ctrl = mods & Qt.ControlModifier
        const plain = !(mods & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
        const isTab = k === Qt.Key_Tab || k === Qt.Key_Backtab
        const back = k === Qt.Key_Backtab || (mods & Qt.ShiftModifier)

        if (isTab && ctrl) { cycleRequested(back ? -1 : 1); return accept(event) }

        let dx = 0, dy = 0
        if (plain) {
            const arrows = !vimKeysOnly
            if ((arrows && k === Qt.Key_Left) || t === "h") dx = -1
            else if ((arrows && k === Qt.Key_Right) || t === "l") dx = 1
            else if ((arrows && k === Qt.Key_Up) || t === "k") dy = -1
            else if ((arrows && k === Qt.Key_Down) || t === "j") dy = 1
        }
        const nav = dx !== 0 || dy !== 0 || (isTab && !ctrl) || k === Qt.Key_Home || k === Qt.Key_End

        // The first key only shows where the cursor is (or puts it on the
        // first control).
        if (nav && (!keyMode || !cursor || !cursorAlive())) {
            const had = cursor && cursorAlive()
            wake()
            if (!had) first()
            else ring.glide()
            return accept(event)
        }
        if (isTab) { step(back ? -1 : 1); return accept(event) }
        if (k === Qt.Key_Home && plain) { first(); return accept(event) }
        if (k === Qt.Key_End && plain) { last(); return accept(event) }
        if (adjust(dx, dy, mods & Qt.ShiftModifier)) return accept(event)
        if (dx !== 0 || dy !== 0) { move(dx, dy, false); return accept(event) }

        if (!keyMode || !cursor) return false
        if (k === Qt.Key_Return || k === Qt.Key_Enter || (k === Qt.Key_Space && plain)) {
            return activate(false, mods & Qt.ShiftModifier) ? accept(event) : false
        }
        if (k === Qt.Key_Menu || (k === Qt.Key_F10 && (mods & Qt.ShiftModifier))) {
            return activate(true, 0) ? accept(event) : false
        }
        return false
    }
    function accept(event) { event.accepted = true; return true }

    // A popout's own Shortcut on a key (the calendar's Left/Right) wins over
    // every Keys handler. While the cursor is shown, the owner claims the
    // keys the cursor uses from its Keys.onShortcutOverride, so they reach
    // handle(). Tab stays the popout's (music, volume, network: sections).
    function claims(event) {
        if (!active || !scope || !keyMode || !cursorAlive()) return false
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return false
        const k = event.key
        const arrow = k === Qt.Key_Left || k === Qt.Key_Right || k === Qt.Key_Up || k === Qt.Key_Down
        return (arrow && !vimKeysOnly)
            || k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space
    }

    function cursorAlive() {
        if (!cursor) return false
        for (let p = cursor; p; p = p.parent) {
            if (!p.visible || p.opacity < 0.05) return false
            if (p === scope) return true
        }
        return false
    }

    function wake() {
        keyMode = true
        pointer.armed = false
        pointerArm.restart()
    }

    // A fresh surface: forget the old cursor. With `keys`, start in key mode
    // and land on the first control as soon as one is laid out (pages
    // build and fade in over their first frames).
    property int seekTries: 0
    function reset(keys) {
        cursor = null; cursorKind = ""; cursorIndex = -1
        keyMode = !!keys
        seekTries = 0
        seek.lastCount = -1
        if (keys) seek.restart()
        else seek.stop()
    }
    Timer {
        id: seek
        interval: 60
        repeat: true
        // Rows fade in one after another; wait until the set of controls
        // holds still for a beat so the cursor starts on the real first one.
        property int lastCount: -1
        onTriggered: {
            if (root.cursor || !root.keyMode || ++root.seekTries > 20) { stop(); return }
            const n = root.collect().length
            if (n > 0 && (n === lastCount || root.seekTries > 12)) { if (root.first()) stop() }
            lastCount = n
        }
    }

    // The cursor's control went away (a page changed, a list rebuilt): put
    // it on whatever now sits at its place in the order.
    function restore() {
        if (!keyMode || cursorAlive()) return
        const es = ordered()
        if (!es.length) { cursor = null; return }
        const i = Math.max(0, Math.min(cursorIndex, es.length - 1))
        cursorIndex = i
        setCursor(es[i])
    }

    // ---------------------------------------------------------- the pointer
    //
    // Moving the mouse puts the keyboard away. The surface may move under a
    // still pointer (a popout morphing in), so only real travel counts.
    HoverHandler {
        id: pointer
        property bool armed: false
        property point origin: Qt.point(0, 0)
        onPointChanged: {
            if (!root.keyMode) return
            const p = point.position
            if (!armed) { origin = p; armed = true; return }
            if (Math.abs(p.x - origin.x) + Math.abs(p.y - origin.y) > 6) root.keyMode = false
        }
    }
    Timer { id: pointerArm; interval: 300; onTriggered: pointer.armed = false }

    // ------------------------------------------------------------- the ring
    //
    // Meander's focus indicator: a 2px accent outline 2px outside the
    // control, following its corners (each one, so a segment of a switch
    // or a tab with only its outer corners rounded gets the same shape);
    // just inside the edge instead where a clipping ancestor (a scroll view,
    // a clipped card, the popout's own edge) or the edge of the background
    // it sits on (a bar module's pill) would cut across the outer one.
    // On a control with a coloured fill (an accent bar pill, a selected
    // segment, a filled button) it sits inside the fill instead, in the control's own
    // icon/text colour, which reads on any fill, the accent included. It
    // glides between stops.

    function isRect(it) { return it && it.border !== undefined && typeof it.radius === "number" && it.color !== undefined }
    // What an item paints its area with: a Rectangle's colour, or a level
    // fill (FluidWave: the battery pill's charge) once it covers most of it.
    function paintOf(it) {
        if (isRect(it)) return it.color
        if (it && typeof it.fillLevel === "number" && it.fillLevel >= 0.5 && it.color2 !== undefined) return it.color2
        return null
    }
    function isText(it) { return it && typeof it.text === "string" && it.font !== undefined && it.color !== undefined && it.horizontalAlignment !== undefined }

    // A neutral surface: the theme's background and surface steps (a bar
    // module's pill, a plain button), where the accent ring already reads.
    function isNeutral(c) {
        const near = (a, b) => Math.abs(a.r - b.r) + Math.abs(a.g - b.g) + Math.abs(a.b - b.b) < 0.09
        const T = ThemeBackend
        const steps = [T.crust, T.mantle, T.base, T.surface0, T.surface1, T.surface2, "#000000"]
        for (let i = 0; i < steps.length; i++) if (near(c, Qt.color(steps[i]))) return true
        return Math.max(c.r, c.g, c.b) - Math.min(c.r, c.g, c.b) < 0.06 && 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b < 0.35
    }

    // The coloured fill drawn behind the control: the control itself, or a
    // Rectangle beside or above it that covers its centre and isn't much
    // bigger (a bar pill, the selected segment's highlight, the battery's
    // charge; not the card or
    // panel it sits on). null when the control sits on a neutral surface.
    function fillOf(t) {
        const r = rectOf(t)
        const cx = r.x + r.w / 2, cy = r.y + r.h / 2, area = Math.max(1, r.w * r.h)
        const solid = c => {
            const col = c === ring ? null : paintOf(c)
            if (!col || !c.visible || c.opacity * col.a < 0.5 || isNeutral(col)) return false
            const q = rectOf(c)
            return q.w * q.h <= area * 2.5 && cx >= q.x && cx <= q.x + q.w && cy >= q.y && cy <= q.y + q.h
        }
        if (solid(t)) return t
        for (let p = t, d = 0; p && d < 6; p = p.parent, d++) {
            const kids = p.children
            for (let i = kids.length - 1; i >= 0; i--) if (kids[i] !== t && solid(kids[i])) return kids[i]
            if (p !== t && solid(p)) return p
            if (p === scope) break
        }
        return null
    }

    // The colour the control draws its icon and label in: the first label
    // inside its button (its largest same-size ancestor), else whichever of
    // the theme's text and crust stands out on the fill.
    function foregroundOf(t, fillItem) {
        const fill = { color: paintOf(fillItem) }
        const near = (a, b) => Math.abs(a.width - b.width) < 2 && Math.abs(a.height - b.height) < 2
        let button = t
        for (let p = t.parent, d = 0; p && d < 3 && near(p, t); p = p.parent, d++) button = p
        const lum = c => 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
        const find = (it, d) => {
            if (!it || !it.visible || it.opacity < 0.3 || d > 4) return null
            if (isText(it) && it.text !== "" && Math.abs(lum(it.color) - lum(fill.color)) > 0.25) return it.color
            for (let i = 0; i < it.children.length; i++) {
                const c = find(it.children[i], d + 1)
                if (c) return c
            }
            return null
        }
        return find(button, 0) || find(fillItem, 0)
            || (lum(fill.color) > 0.5 ? ThemeBackend.crust : ThemeBackend.text)
    }

    // The background the control sits on: the nearest Rectangle around it
    // that is bigger than it (a bar module's pill, a card). The outer ring
    // has to fit inside it, or it would cut across that edge.
    function surfaceOf(t) {
        const r = rectOf(t)
        const holds = c => {
            if (!isRect(c) || c === ring || !c.visible || c.opacity * c.color.a < 0.3) return false
            const q = rectOf(c)
            return q.w * q.h > r.w * r.h * 1.3 && Logic.contains(q, r)
        }
        for (let p = t.parent, d = 0; p && d < 8; p = p.parent, d++) {
            const kids = p.children
            for (let i = kids.length - 1; i >= 0; i--) if (holds(kids[i])) return kids[i]
            if (holds(p)) return p
            if (p === scope) break
        }
        return null
    }

    // The control's corner radii, { tl, tr, bl, br }.
    function cornersOf(t) {
        const near = (a, b) => Math.abs(a.width - b.width) < 2 && Math.abs(a.height - b.height) < 2
        const all = v => ({ tl: v, tr: v, bl: v, br: v })
        const own = r => {
            if (typeof r.cornerRadius === "number" && r.cornerRadius > 0) return all(r.cornerRadius)
            if (r.border === undefined || typeof r.radius !== "number") return null
            // A Rectangle: per-corner radii fall back to `radius` when unset.
            const c = k => (typeof r[k] === "number" && r[k] >= 0) ? r[k] : r.radius
            const cs = { tl: c("topLeftRadius"), tr: c("topRightRadius"), bl: c("bottomLeftRadius"), br: c("bottomRightRadius") }
            return (cs.tl > 0 || cs.tr > 0 || cs.bl > 0 || cs.br > 0) ? cs : null
        }
        let r = own(t)
        if (r) return r
        // A MouseArea filling its button: the button's corners, or those of
        // a background drawn beside it at the same size.
        const kids = t.children
        for (let i = 0; i < kids.length; i++) if (near(kids[i], t) && (r = own(kids[i]))) return r
        for (let p = t.parent, d = 0; p && d < 3; p = p.parent, d++) {
            if (!near(p, t)) break
            if ((r = own(p))) return r
            for (let i = 0; i < p.children.length; i++) {
                const s = p.children[i]
                if (s !== t && near(s, t) && (r = own(s))) return r
            }
        }
        return all(Math.min(t.height / 2, ThemeBackend.borderRadius))
    }

    Item {
        id: ring
        z: 1000
        property var rect: ({ x: 0, y: 0, w: 0, h: 0 })
        property bool inner: false
        property real tl: 0
        property real tr: 0
        property real bl: 0
        property real br: 0
        property bool gliding: false
        readonly property real gap: 2
        readonly property real thickness: 2
        property color color: ThemeBackend.primary
        property Item surfaceFor: null
        property Item surface: null

        function glide() { gliding = true; glideEnd.restart(); update() }
        Timer { id: glideEnd; interval: 200; onTriggered: ring.gliding = false }

        function clipOf(t) {
            let c = { x: 0, y: 0, w: root.width, h: root.height }
            for (let p = t.parent; p; p = p.parent) {
                if (p.clip || (root.isFlickable(p) && p.interactive !== false)) c = Logic.intersect(c, root.rectOf(p))
                if (p === root.scope) { c = Logic.intersect(c, root.rectOf(p)); break }
            }
            return c
        }
        function update() {
            const t = root.cursor
            if (!t || !root.active || !root.keyMode) { rect = { x: 0, y: 0, w: 0, h: 0 }; return }
            if (!root.cursorAlive()) { rect = { x: 0, y: 0, w: 0, h: 0 }; restoreLater.restart(); return }
            // The ring goes around `keyNavRingItem` when the stop names one
            // (a click area much bigger than what it draws: the bar's media
            // info spans the full bar height in a clipped row).
            const s = (t.keyNavRingItem && t.keyNavRingItem.visible) ? t.keyNavRingItem : t
            const r = root.rectOf(s)
            const out = gap + thickness
            const fill = root.fillOf(s)
            const fg = fill ? root.foregroundOf(s, fill) : ThemeBackend.primary
            if (!Qt.colorEqual(fg, color)) color = fg
            if (surfaceFor !== s) { surfaceFor = s; surface = root.surfaceOf(s) }
            let room = clipOf(s)
            if (surface && surface.visible) room = Logic.intersect(room, root.rectOf(surface))
            inner = !!fill || !Logic.contains(room, Logic.grow(r, out))
            const ins = fill ? gap : 1
            const g = inner ? Logic.grow(r, -ins) : Logic.grow(r, out)
            if (g.x !== rect.x || g.y !== rect.y || g.w !== rect.w || g.h !== rect.h) rect = g
            // Corners scale with the control (rectOf is its drawn size); a
            // square corner stays square.
            const k = s.width > 0 ? r.w / s.width : 1
            const cs = root.cornersOf(s)
            const fit = v => Math.max(0, Math.min(g.h / 2, g.w / 2, inner ? v * k - ins : (v > 0 ? v * k + out : 0)))
            tl = fit(cs.tl); tr = fit(cs.tr); bl = fit(cs.bl); br = fit(cs.br)
        }
        Timer { id: restoreLater; interval: 30; onTriggered: root.restore() }

        FrameAnimation {
            running: root.active && root.keyMode && root.cursor !== null
            onTriggered: ring.update()
        }

        x: rect.x
        y: rect.y
        width: rect.w
        height: rect.h
        visible: root.active && root.keyMode && rect.w > 0
        opacity: visible ? 1 : 0

        Behavior on x { enabled: ring.gliding; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on y { enabled: ring.gliding; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on width { enabled: ring.gliding; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on height { enabled: ring.gliding; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 120 } }

        Rectangle {
            anchors.fill: parent
            topLeftRadius: ring.tl
            topRightRadius: ring.tr
            bottomLeftRadius: ring.bl
            bottomRightRadius: ring.br
            color: "transparent"
            border.width: ring.thickness
            border.color: ring.color
            antialiasing: true
        }
    }
}
