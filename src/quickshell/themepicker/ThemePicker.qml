import QtQuick
import QtQuick.Window
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"

// Meander's theme picker. No Serpantinum original (its themes are colour
// presets in Settings); this picks Omarchy themes, drawn as the wallpaper
// picker draws wallpapers: the same skewed carousel, card sizes, motion and
// floating top bar (wallpaper/WallpaperPicker.qml), without its filters,
// online search and video.
//
// Data: `meander-core themes` (Omarchy's own picker rows + each theme's
// palette). Apply: `omarchy-theme-set <id>`; Meander follows the switch
// through Omarchy's `background themeTransition` IPC like any theme change,
// and the picker stays open so you can try the next one.
//
// Keys: ← → / h l move, Enter or Space applies, Home / End, / or Tab to
// search (Enter or ↓ back to the cards), Escape closes (Main.qml).
Item {
    id: window
    visible: false
    width: Screen.width
    focus: true
    // The cards take every key themselves; KeyNav's cursor stays out.
    property bool keyNavSkip: true

    function s(val) { return Scaler.s(val); }

    readonly property real itemWidth: window.s(400)
    readonly property real itemHeight: window.s(420)
    readonly property real borderWidth: window.s(3)
    readonly property real skewFactor: -0.35
    readonly property real selectedCenterOffset: (window.skewFactor * (window.itemHeight)) / 2
    readonly property var skew: Qt.matrix4x4(1, window.skewFactor, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
    readonly property var unskew: Qt.matrix4x4(1, -window.skewFactor, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)

    property var allThemes: []
    property string currentId: ""
    property string applyingId: ""
    property string query: ""
    property bool loaded: false
    property bool initialFocusSet: false

    // ------------------------------------------------------------ lifecycle

    property bool isExiting: false
    readonly property bool isReady: visible && !isExiting
    property var exitCallback: null

    function startExit(onFinished) {
        if (isExiting) return;
        isExiting = true;
        exitCallback = onFinished;
        exitAnim.restart();
    }

    SequentialAnimation {
        id: exitAnim
        ParallelAnimation {
            NumberAnimation { target: topBar; property: "anchors.topMargin"; to: window.s(-75); duration: 150; easing.type: Easing.InCubic }
            NumberAnimation { target: topBar; property: "opacity"; to: 0.0; duration: 160; easing.type: Easing.InQuad }
            NumberAnimation { target: view; property: "opacity"; to: 0.0; duration: 250; easing.type: Easing.InQuad }
            NumberAnimation { target: view; property: "anchors.margins"; to: window.s(45); duration: 250; easing.type: Easing.InCubic }
        }
        ScriptAction {
            script: {
                if (window.exitCallback) {
                    let cb = window.exitCallback;
                    window.exitCallback = null;
                    cb();
                }
            }
        }
    }

    onVisibleChanged: {
        if (visible) {
            isExiting = false;
            topBar.anchors.topMargin = Qt.binding(() => window.isReady ? window.s(65) : window.s(-75));
            topBar.opacity = Qt.binding(() => window.isReady ? 1.0 : 0.0);
            view.opacity = Qt.binding(() => window.isReady ? 1.0 : 0.0);
            view.anchors.margins = Qt.binding(() => window.isReady ? 0 : window.s(40));
            query = "";
            searchInput.text = "";
            initialFocusSet = false;
            if (allThemes.length) rebuild(true);
            lister.running = true;
            focusTimer.restart();
        } else {
            applyingId = "";
        }
    }

    Timer { id: focusTimer; interval: 50; onTriggered: view.forceActiveFocus() }

    // ----------------------------------------------------------------- data

    Process {
        id: lister
        command: ["meander-core", "themes"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let d = JSON.parse(text);
                    window.allThemes = d.themes || [];
                    window.currentId = d.current || "";
                } catch (e) {
                    window.allThemes = [];
                }
                window.loaded = true;
                window.rebuild(true);
            }
        }
    }

    // Omarchy writes theme.name when a switch lands.
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            window.currentId = text().trim();
            if (window.applyingId === window.currentId) window.applyingId = "";
        }
    }

    ListModel { id: shown }

    function matches(t) {
        let q = window.query.trim().toLowerCase();
        return q === "" || t.name.toLowerCase().indexOf(q) !== -1 || t.id.indexOf(q) !== -1;
    }

    // Refill the cards; keep the selected theme (or land on the current one).
    function rebuild(toCurrent) {
        let keep = (!toCurrent && view.currentIndex >= 0 && view.currentIndex < shown.count) ? shown.get(view.currentIndex).tid : window.currentId;
        shown.clear();
        let at = 0;
        for (let i = 0; i < window.allThemes.length; i++) {
            let t = window.allThemes[i];
            if (!window.matches(t)) continue;
            if (t.id === keep) at = shown.count;
            shown.append({ tid: t.id, name: t.name, thumb: "file://" + t.thumb, mode: t.mode, colors: JSON.stringify(t.colors || []) });
        }
        // Set again once the cards have their sizes: the selected card is
        // wider, and the strict highlight range snaps to whatever sits in it.
        window.pendingIndex = shown.count ? at : -1;
        view.currentIndex = window.pendingIndex;
        settle.restart();
    }
    property int pendingIndex: -1
    Timer {
        id: settle
        interval: 30
        onTriggered: {
            view.currentIndex = window.pendingIndex;
            window.initialFocusSet = true;
        }
    }

    function apply(i) {
        if (i < 0 || i >= shown.count) return;
        let id = shown.get(i).tid;
        view.currentIndex = i;
        if (id === window.currentId || id === window.applyingId) return;
        window.applyingId = id;
        Quickshell.execDetached(["omarchy-theme-set", id]);
        applyTimeout.restart();
    }
    Timer { id: applyTimeout; interval: 15000; onTriggered: window.applyingId = "" }

    function themeName(id) {
        for (let i = 0; i < window.allThemes.length; i++) if (window.allThemes[i].id === id) return window.allThemes[i].name;
        return id;
    }

    // ----------------------------------------------------------------- keys

    function step(d) {
        if (!shown.count) return;
        view.currentIndex = Math.max(0, Math.min(shown.count - 1, view.currentIndex + d));
    }
    function openSearch(seed) {
        searchInput.forceInputFocus();
        if (seed) { searchInput.text = seed; window.query = seed; window.rebuild(false); }
    }

    Keys.onPressed: (event) => {
        let k = event.key, t = event.text;
        // Keys the search field let through stop here: Enter there only
        // returns to the cards (it must never apply a theme).
        if (searchInput.hasFocus) {
            if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Down || k === Qt.Key_Tab) view.forceActiveFocus();
            event.accepted = true;
            return;
        }
        let plain = !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier));
        if (k === Qt.Key_Left || (plain && t === "h")) window.step(-1);
        else if (k === Qt.Key_Right || (plain && t === "l")) window.step(1);
        else if (k === Qt.Key_Home) window.step(-shown.count);
        else if (k === Qt.Key_End) window.step(shown.count);
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) window.apply(view.currentIndex);
        else if (k === Qt.Key_Slash || k === Qt.Key_Tab || k === Qt.Key_Up) window.openSearch("");
        else if (k === Qt.Key_Down || (plain && (t === "j" || t === "k"))) {}
        else return;
        event.accepted = true;
    }

    // ---------------------------------------------------------------- cards

    ListView {
        id: view
        anchors.fill: parent
        opacity: window.isReady ? 1.0 : 0.0
        anchors.margins: window.isReady ? 0 : window.s(40)
        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on anchors.margins { NumberAnimation { duration: 650; easing.type: Easing.OutQuint } }

        spacing: 0; orientation: ListView.Horizontal; clip: false
        // meander: the cards are sheared with a Matrix4x4 and clipped by a
        // MultiEffect mask; the effect's quad gets no edge antialiasing under
        // the shear, so the slanted sides came out stair-stepped. Rendering
        // the carousel into one multisampled layer antialiases those edges
        // (one fixed-size texture, so scrolling doesn't reallocate it).
        layer.enabled: true
        layer.samples: 4
        layer.smooth: true
        cacheBuffer: window.itemWidth * 3
        keyNavigationEnabled: false
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: (width / 2) - ((window.itemWidth * 1.5 + window.s(4)) / 2) + window.selectedCenterOffset
        preferredHighlightEnd: (width / 2) + ((window.itemWidth * 1.5 + window.s(4)) / 2) + window.selectedCenterOffset
        highlightMoveDuration: window.initialFocusSet ? 400 : 0

        header: Item { width: Math.max(0, (view.width / 2) - ((window.itemWidth * 1.5) / 2) + window.selectedCenterOffset) }
        footer: Item { width: Math.max(0, (view.width / 2) - ((window.itemWidth * 1.5) / 2) - window.selectedCenterOffset) }
        model: shown

        property int scrollAccum: 0
        Timer { id: scrollThrottle; interval: 140 }
        MouseArea {
            anchors.fill: parent; acceptedButtons: Qt.NoButton
            onWheel: (wheel) => {
                if (scrollThrottle.running) { wheel.accepted = true; return; }
                let delta = Math.abs(wheel.angleDelta.x) > Math.abs(wheel.angleDelta.y) ? wheel.angleDelta.x : wheel.angleDelta.y;
                view.scrollAccum += delta;
                if (Math.abs(view.scrollAccum) >= window.s(45)) {
                    window.step(view.scrollAccum > 0 ? -1 : 1);
                    view.scrollAccum = 0;
                    scrollThrottle.start();
                }
                wheel.accepted = true;
            }
        }

        delegate: Item {
            id: card
            readonly property bool isCurrent: ListView.isCurrentItem
            readonly property bool isActive: model.tid === window.currentId
            readonly property bool isApplying: model.tid === window.applyingId
            readonly property int dist: Math.abs(index - view.currentIndex)
            readonly property real sideScale: Math.max(0.58, Math.pow(0.88, Math.max(0, dist - 1)))
            readonly property var palette: { try { return JSON.parse(model.colors); } catch (e) { return []; } }

            readonly property real dynamicRadius: {
                let baseR = ThemeBackend.borderRadius;
                if (baseR <= 0) return 0;
                let k = Math.min(1.0, Math.pow(baseR / 48, 2));
                let decay = Math.max(0.45, Math.pow(0.85, dist));
                return baseR * (1.0 - k * (1.0 - decay));
            }

            width: isCurrent ? (window.itemWidth * 1.5 + window.s(4)) : (window.itemWidth * 0.48 * sideScale)
            height: isCurrent ? (window.itemHeight + window.s(30)) : (window.itemHeight * Math.max(0.62, Math.pow(0.90, Math.max(0, dist - 1))))
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            anchors.verticalCenterOffset: window.s(25)
            z: isCurrent ? 100 : Math.max(1, 50 - dist)
            Behavior on width { enabled: window.initialFocusSet; NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            Behavior on height { enabled: window.initialFocusSet; NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

            Item {
                id: skewed
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: -(window.skewFactor * height) / 2
                width: parent.width
                height: parent.height
                transform: Matrix4x4 { matrix: window.skew }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: window.apply(index)
                }

                Item {
                    id: frame
                    anchors.fill: parent
                    anchors.margins: window.borderWidth

                    Rectangle { anchors.fill: parent; radius: card.dynamicRadius; color: ThemeBackend.surface0 }
                    Rectangle { id: mask; anchors.fill: parent; radius: card.dynamicRadius; visible: false; layer.enabled: true }

                    Item {
                        anchors.fill: parent
                        layer.enabled: true
                        layer.effect: MultiEffect { maskEnabled: true; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0; maskSource: mask }

                        Image {
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: window.s(-50)
                            width: (window.itemWidth * 1.5) + ((window.itemHeight + window.s(30)) * Math.abs(window.skewFactor)) + window.s(50)
                            height: window.itemHeight + window.s(30)
                            fillMode: Image.PreserveAspectCrop
                            source: model.thumb
                            asynchronous: true
                            cache: true
                            opacity: status === Image.Ready ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                            sourceSize.width: Math.round(width)
                            sourceSize.height: Math.round(height)
                            transform: Matrix4x4 { matrix: window.unskew }
                        }

                        // Name and palette on the selected card, over a shade
                        // so they read on any preview.
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: window.s(96)
                            opacity: card.isCurrent ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 250 } }
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.62) }
                            }
                        }
                    }

                    // Counter-skewed so text stands upright, as the wallpaper
                    // picker's favourite button does.
                    Column {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: window.s(22) + (-window.skewFactor * window.s(22))
                        anchors.bottomMargin: window.s(18)
                        spacing: window.s(8)
                        opacity: card.isCurrent ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                        transform: Matrix4x4 { matrix: window.unskew }

                        Text {
                            text: model.name
                            color: "#ffffff"
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: window.s(22)
                            font.bold: true
                            style: Text.Outline
                            styleColor: Qt.rgba(0, 0, 0, 0.35)
                        }
                        Row {
                            spacing: window.s(6)
                            Repeater {
                                model: card.palette
                                Rectangle {
                                    width: window.s(14); height: width; radius: width / 2
                                    color: modelData
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.35)
                                }
                            }
                        }
                    }

                    // Active / applying badge, top left.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.leftMargin: window.s(10)
                        anchors.topMargin: window.s(10)
                        visible: (card.isActive || card.isApplying) && card.width > window.s(120)
                        height: window.s(26)
                        width: badgeRow.implicitWidth + window.s(16)
                        radius: height / 2
                        color: Qt.alpha(ThemeBackend.base, 0.78)
                        transform: Matrix4x4 { matrix: window.unskew }
                        Row {
                            id: badgeRow
                            anchors.centerIn: parent
                            spacing: window.s(6)
                            Text {
                                text: card.isApplying ? "󰑐" : "󰄬"
                                color: ThemeBackend.primary
                                font.family: ThemeBackend.iconFont
                                font.pixelSize: window.s(14)
                                anchors.verticalCenter: parent.verticalCenter
                                RotationAnimation on rotation { running: card.isApplying; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                            }
                            Text {
                                text: card.isApplying ? "Applying" : "Active"
                                color: ThemeBackend.text
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: window.s(12)
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: card.dynamicRadius
                        color: "transparent"
                        border.width: card.isActive ? window.s(2) : 0
                        border.color: ThemeBackend.primary
                    }
                }
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: window.loaded && shown.count === 0
        text: window.query !== "" ? "No theme matches “" + window.query + "”" : "No themes found"
        color: ThemeBackend.subtext0
        font.family: ThemeBackend.fontFamily
        font.pixelSize: window.s(14)
    }

    // -------------------------------------------------------------- top bar

    Rectangle {
        id: topBar
        anchors.top: parent.top
        anchors.topMargin: window.isReady ? window.s(65) : window.s(-75)
        opacity: window.isReady ? 1.0 : 0.0
        Behavior on anchors.topMargin { NumberAnimation { duration: 650; easing.type: Easing.OutQuint } }
        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        anchors.horizontalCenter: parent.horizontalCenter
        z: 200
        height: window.s(48)
        width: barRow.width + window.s(20)
        radius: ThemeBackend.borderRadius
        color: Qt.alpha(ThemeBackend.base, ThemeBackend.elementOpacity)

        WallpaperBlur { z: -1; anchors.fill: parent; radius: parent.radius }

        Row {
            id: barRow
            anchors.centerIn: parent
            spacing: window.s(8)

            Rectangle {
                height: window.s(34)
                width: titleRow.implicitWidth + window.s(24)
                radius: ThemeBackend.borderRadius
                anchors.verticalCenter: parent.verticalCenter
                color: Qt.alpha(ThemeBackend.surface0, ThemeBackend.elementOpacity)
                Row {
                    id: titleRow
                    anchors.centerIn: parent
                    spacing: window.s(8)
                    Text {
                        text: "󰏘"
                        color: ThemeBackend.primary
                        font.family: ThemeBackend.iconFont
                        font.pixelSize: window.s(16)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: window.applyingId !== ""
                            ? "Applying " + window.themeName(window.applyingId) + "…"
                            : (window.themeName(window.currentId) || "Themes") + "  ·  " + shown.count + "/" + window.allThemes.length
                        color: ThemeBackend.text
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: window.s(12)
                        font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            Input {
                id: searchInput
                anchors.verticalCenter: parent.verticalCenter
                width: window.s(220)
                implicitWidth: window.s(220)
                implicitHeight: window.s(34)
                height: window.s(34)
                cornerRadius: ThemeBackend.borderRadius
                baseColor: Qt.alpha(ThemeBackend.surface0, ThemeBackend.elementOpacity)
                borderColor: ThemeBackend.text
                textColor: ThemeBackend.text
                subTextColor: ThemeBackend.subtext0
                accentColor: ThemeBackend.text
                fontFamily: ThemeBackend.fontFamily
                fontPixelSize: window.s(12)
                placeholderText: "Search themes  ( / )"
                showClearButton: true
                onTextEdited: (newText) => { window.query = newText; window.rebuild(false); }
                onCleared: { window.query = ""; window.rebuild(false); }
            }
        }
    }
}
