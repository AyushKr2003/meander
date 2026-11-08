import QtQuick
import QtQuick.Effects
import "../"

// A notification's icon slot, filled as Omarchy's toast fills it (see
// omarchy/NotifIcons.qml): the sender's picture (cropped, rounded), else the
// app's icon (a -symbolic one tinted with the text colour), else the
// omarchy-glyph hint, else upstream's info glyph.
Item {
    id: root

    property var entry: null
    property bool withPicture: true
    property real radius: 0
    property real glyphSize: 22
    property color fallbackColor: ThemeBackend.subtext0
    property string fallbackGlyph: "󰋽"

    readonly property var sources: NotifIcons.sources(entry, withPicture)
    readonly property string sourcesKey: sources.join("\n")
    property int failed: 0
    onSourcesKeyChanged: failed = 0
    readonly property string best: sources[failed] || ""
    readonly property bool photo: best !== "" && best === NotifIcons.picture(entry) && withPicture
    readonly property bool mono: !photo && NotifIcons.isSymbolic(best)
    readonly property bool pictured: picture.status === Image.Ready && best !== ""
    readonly property string glyph: NotifIcons.glyph(entry)

    Image {
        id: picture
        anchors.fill: parent
        visible: root.pictured
        source: root.best
        asynchronous: true
        // A photo fills its square; an app icon keeps its own shape.
        fillMode: root.photo ? Image.PreserveAspectCrop : Image.PreserveAspectFit
        sourceSize: Qt.size(Math.max(48, root.width * 2), Math.max(48, root.height * 2))
        // A sender may write each picture to the same path (cover art).
        cache: !(root.photo && root.best.indexOf("file:") === 0)
        onStatusChanged: if (status === Image.Error && root.failed < root.sources.length) root.failed += 1
        readonly property bool rounded: root.photo && root.radius > 0
        opacity: root.mono ? 0.85 : 1
        layer.enabled: visible && (root.mono || rounded)
        layer.effect: MultiEffect {
            maskEnabled: picture.rounded
            maskSource: mask
            brightness: root.mono ? 1.0 : 0.0
            colorization: root.mono ? 1.0 : 0.0
            colorizationColor: ThemeBackend.text
        }
    }

    Rectangle {
        id: mask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        radius: root.radius
        color: "black"
    }

    Text {
        anchors.centerIn: parent
        visible: !root.pictured && root.glyph !== ""
        text: root.glyph
        textFormat: Text.PlainText
        font.family: NotifIcons.glyphFont(root.entry)
        font.pixelSize: root.glyphSize
        color: ThemeBackend.text
    }

    Text {
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: 1
        anchors.verticalCenterOffset: -1
        visible: !root.pictured && root.glyph === ""
        text: root.fallbackGlyph
        font.family: ThemeBackend.fontFamily
        font.pixelSize: root.glyphSize
        color: root.fallbackColor
    }
}
