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
    // The panel does its own keyboard focus (Settings): only draw the ring
    // around whatever holds focus, never move it.
    property bool followFocus: false

    // The ring shows only while the keyboard is in use; moving the pointer
    // hides it (the cursor is kept for the next key).
    property bool keyMode: false
    property Item cursor: null
    property string cursorKind: ""
    property int cursorIndex: -1

    readonly property bool ringShown: active && keyMode && cursor !== null && ring.rect.w > 0

    signal cycleRequested(int direction)
    signal activated(Item target)

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

    function rectOf(it) {
        const p = it.mapToItem(root, 0, 0)
        return { x: p.x, y: p.y, w: it.width, h: it.height }
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
        if (own && !secondary) { own.keyNavActivate(); activated(t); return true }
        if (cursorKind === "text") { t.forceActiveFocus(); return true }
        if (cursorKind === "slider") return false
        const btn = secondary ? Qt.RightButton : Qt.LeftButton
        const ma = cursorKind === "mouse" ? t : findMouseArea(t)
        if (ma && !(ma.acceptedButtons & btn)) return false
        click(t, btn, modifiers || Qt.NoModifier)
        activated(t)
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

        if (followFocus) {
            // Settings: its arrows and Tab change tabs until a control has
            // focus, and nothing upstream gives one focus from the keyboard.
            // Enter steps into the page's first control; from there its own
            // Up/Down walk the controls and Escape steps back out.
            const w = root.Window.window
            const f = w ? w.activeFocusItem : null
            if ((k === Qt.Key_Return || k === Qt.Key_Enter) && plain && (!f || f === scope)) {
                const n = scope.nextItemInFocusChain(true)
                if (n && n !== scope) {
                    n.forceActiveFocus(Qt.TabFocusReason)
                    wake()
                    return accept(event)
                }
            }
            if (isTab || k === Qt.Key_Up || k === Qt.Key_Down || k === Qt.Key_Left || k === Qt.Key_Right) wake()
            return false
        }

        let dx = 0, dy = 0
        if (plain) {
            if (k === Qt.Key_Left || t === "h") dx = -1
            else if (k === Qt.Key_Right || t === "l") dx = 1
            else if (k === Qt.Key_Up || t === "k") dy = -1
            else if (k === Qt.Key_Down || t === "j") dy = 1
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

    // Settings moves focus with keys we never see (it accepts them first):
    // a control taking focus there means the keyboard is in use.
    Connections {
        target: root.followFocus && root.active ? root.Window.window : null
        function onActiveFocusItemChanged() { if (root.focusTarget()) root.wake() }
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
    // control, following its corner radius; just inside the edge instead
    // where a clipping ancestor (a scroll view, a clipped card, the popout's
    // own edge) would cut the outer one off. It glides between stops.

    function radiusOf(t) {
        const near = (a, b) => Math.abs(a.width - b.width) < 2 && Math.abs(a.height - b.height) < 2
        const own = r => (typeof r.cornerRadius === "number" && r.cornerRadius > 0) ? r.cornerRadius
            : (typeof r.radius === "number" && r.radius > 0 && r.border !== undefined) ? r.radius : -1
        let r = own(t)
        if (r >= 0) return r
        // A MouseArea filling its button: the button's corners, or those of
        // a background drawn beside it at the same size.
        const kids = t.children
        for (let i = 0; i < kids.length; i++) if (near(kids[i], t) && (r = own(kids[i])) >= 0) return r
        for (let p = t.parent, d = 0; p && d < 3; p = p.parent, d++) {
            if (!near(p, t)) break
            if ((r = own(p)) >= 0) return r
            for (let i = 0; i < p.children.length; i++) {
                const s = p.children[i]
                if (s !== t && near(s, t) && (r = own(s)) >= 0) return r
            }
        }
        return Math.min(t.height / 2, ThemeBackend.borderRadius)
    }

    Item {
        id: ring
        z: 1000
        property var rect: ({ x: 0, y: 0, w: 0, h: 0 })
        property bool inner: false
        property real radius: 0
        property bool gliding: false
        readonly property real gap: 2
        readonly property real thickness: 2

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
            const t = root.followFocus ? root.focusTarget() : root.cursor
            if (!t || !root.active || !root.keyMode) { rect = { x: 0, y: 0, w: 0, h: 0 }; return }
            if (!root.followFocus && !root.cursorAlive()) { rect = { x: 0, y: 0, w: 0, h: 0 }; restoreLater.restart(); return }
            const r = root.rectOf(t)
            const out = gap + thickness
            inner = !Logic.contains(clipOf(t), Logic.grow(r, out))
            const g = inner ? Logic.grow(r, -1) : Logic.grow(r, out)
            if (g.x !== rect.x || g.y !== rect.y || g.w !== rect.w || g.h !== rect.h) rect = g
            const tr = root.radiusOf(t)
            radius = Math.max(0, Math.min(g.h / 2, g.w / 2, inner ? tr - 1 : (tr > 0 ? tr + out : 0)))
        }
        Timer { id: restoreLater; interval: 30; onTriggered: root.restore() }

        FrameAnimation {
            running: root.active && root.keyMode && (root.cursor !== null || root.followFocus)
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
            radius: ring.radius
            color: "transparent"
            border.width: ring.thickness
            border.color: ThemeBackend.primary
            antialiasing: true
        }
    }

    // Settings moves its own focus; the ring follows the focused control.
    function focusTarget() {
        const w = root.Window.window
        let f = w ? w.activeFocusItem : null
        if (!f || f === scope) return null
        let inScope = false
        for (let p = f; p; p = p.parent) if (p === scope) { inScope = true; break }
        if (!inScope) return null
        // A text field's ring goes around its box, not the bare text.
        if (isTextField(f) && f.parent && f.parent !== scope && f.parent.height >= f.height) {
            const box = f.parent.parent && f.parent.parent !== scope ? f.parent.parent : f.parent
            return box.width > f.width + 40 ? f.parent : box
        }
        return f.activeFocusOnTab || isTextField(f) ? f : null
    }
}
