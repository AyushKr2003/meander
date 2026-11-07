import QtQuick
import "../"

// Keyboard for a hover card that upstream never focuses (the tray menu, the
// dock's app menu, the vertical bar's music card). Opened from bar or dock
// focus (KeyNavState.pendingKeys), the card takes the keyboard and a KeyNav
// cursor walks it: arrows move, Enter clicks, Escape closes. Opened by the
// pointer it stays pointer-only, as upstream.
//
// The owner fills its window with this, sets `open` and `scope`, binds
//   WlrLayershell.keyboardFocus: card.keyFocus ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
// and closes itself on closeRequested().
Item {
    id: root

    property bool open: false
    property Item scope: null
    readonly property bool keyFocus: held && open
    property bool held: false

    // Escape, 30 s untouched.
    signal closeRequested()
    // The pointer moved over the card: it is a hover card again.
    signal released()

    onOpenChanged: {
        held = open && KeyNavState.takePendingKeys();
        if (held) {
            nav.reset(true);
            keys.forceActiveFocus();
            idle.restart();
        } else {
            nav.reset(false);
            idle.stop();
        }
    }

    Item {
        id: keys
        anchors.fill: parent
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                root.closeRequested();
                event.accepted = true;
                return;
            }
            idle.restart();
            nav.handle(event);
        }
    }

    KeyNav {
        id: nav
        anchors.fill: parent
        scope: root.scope
        focusHome: keys
        active: root.keyFocus
        onKeyModeChanged: if (!keyMode && root.held) {
            root.held = false;
            root.released();
        }
    }

    Timer { id: idle; interval: 30000; onTriggered: root.closeRequested() }
}
