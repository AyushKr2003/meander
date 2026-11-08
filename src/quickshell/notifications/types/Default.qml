import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import "../../"
import "../../reusables"
import "../"

Notification {
    id: faceRoot

    fullSummary: model ? (model.summary || I18n.t("notifications.types.default.fallback_summary")) : ""
    fullBody: model ? (model.body || "") : ""

    // Omarchy's icon order (sender picture, app icon, glyph); see NotifIcon.
    iconArea: [
        NotifIcon {
            anchors.fill: parent
            entry: faceRoot.model
            radius: s(5)
            glyphSize: s(22)
            fallbackColor: faceRoot.bodyText
        }
    ]

    headerArea: [
        Text {
            Layout.fillWidth: true
            horizontalAlignment: I18n.textAlignment
            text: model ? (model.displayName || model.appName || "System") : "System"
            font.family: ThemeBackend.fontFamily
            font.weight: Font.Bold
            font.pixelSize: s(11)
            color: faceRoot.bodyText
            elide: Text.ElideRight
        }
    ]
}
