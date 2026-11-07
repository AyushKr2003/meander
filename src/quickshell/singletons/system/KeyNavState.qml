pragma Singleton
import QtQuick

// Shared state of Meander's keyboard mode (keynav/KeyNav.qml), set over IPC
// by MeanderBar.qml (`meander.keynav`) and the `meander keys` CLI.
//
// `pendingKeys`: the next popout to open starts with the cursor shown on its
// first control, because the keyboard asked for it (a bar module activated
// from bar focus, Ctrl+Tab to the next panel, `meander keys open <panel>`).
// `barScreen` / `dockScreen`: the monitor whose bar or dock holds the
// keyboard ("" = none); one surface at a time.
QtObject {
    id: root

    property bool pendingKeys: false
    property string barScreen: ""
    property string dockScreen: ""

    // The button of a keyboard click (KeyNav emits MouseArea.clicked with no
    // event); handlers that tell buttons apart read buttonOf(mouse).
    property int button: Qt.LeftButton
    function buttonOf(mouse) { return mouse ? mouse.button : button }

    // A popout opened from the bar or dock by the keyboard takes the keys
    // over: the bar/dock lets go.
    function takePendingKeys() {
        const k = pendingKeys
        pendingKeys = false
        if (k) release()
        return k
    }

    // Monitors with a dock on screen (DockWindow reports it): dock focus
    // only goes where there is one.
    property var docks: ({})
    function setDock(screen, shown) {
        const d = Object.assign({}, docks)
        if (shown) d[screen] = true
        else delete d[screen]
        docks = d
        if (!shown && dockScreen === screen) dockScreen = ""
    }

    function focusBar(screen) { dockScreen = ""; barScreen = screen || "" }
    function focusDock(screen) {
        if (!docks[screen]) return false
        barScreen = ""
        dockScreen = screen
        return true
    }
    function release() { barScreen = ""; dockScreen = "" }
}
