import QtQuick
import "."

// Meander's service entry (manifest `entryPoints.service`).
//
// The Omarchy shell creates service plugins synchronously right after its
// plugin scan, while the bar (MeanderBar.qml) is a large asynchronous load
// that finishes seconds later. `omarchy restart shell` waits only 2s for
// org.freedesktop.Notifications, so the notification server is started here:
// this file and the bar share one QML engine, so NotificationManager is the
// same singleton the bar uses. Whether Meander owns notifications is read
// from shell.json until the bar has the host's registry (OmarchyHost).
QtObject {
    property var shell: null
    property var manifest: null
    property string omarchyPath: ""
    readonly property var notificationEngine: NotificationManager
}
