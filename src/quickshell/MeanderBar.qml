import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "widgets"

// Meander -- entry point of the `meander.bar` Omarchy bar plugin.
//
// Upstream Serpantinum is a standalone Quickshell config (Shell.qml, a
// ShellRoot started by its own daemon). Here the Omarchy shell is the process:
// it loads this file once as the active bar option and injects the properties
// below. Everything Shell.qml instantiated is instantiated here, unchanged,
// except the engines Omarchy also ships, which start only while Omarchy's own
// is off (OmarchyHost), and the process-wide bits a guest must not touch
// (reload popups, Qt.application identity).
Item {
    id: root
    visible: false

    // ------------------------------------------------- host injection
    property string omarchyPath: Quickshell.env("OMARCHY_PATH")
    property var barWidgetRegistry: null
    property var pluginRegistry: null
    property var barConfig: ({})
    property var shell: null
    property var manifest: null

    readonly property string version: manifest && manifest.version ? manifest.version : "2.4.2-13"

    // Created first thing, so the notification server (when Meander owns it,
    // see OmarchyHost.fileOwns) is on the bus before the rest of the bar has
    // loaded: `omarchy restart shell` waits only 2s for it.
    readonly property var notificationEngine: NotificationManager

    // ------------------------------------------------- bar contract
    // Read by the host (`shell.bar.*`) and by Omarchy's KeyboardPanel /
    // PopupCard / notification placement.
    property bool barHidden: false
    readonly property var meanderBar: Config.getSetting("bar", {})
    readonly property string position: {
        let p = meanderBar && meanderBar.position ? String(meanderBar.position) : "top";
        return ["top", "bottom", "left", "right"].indexOf(p) >= 0 ? p : "top";
    }
    readonly property bool vertical: position === "left" || position === "right"
    readonly property int barSize: {
        if (barHidden || (meanderBar && meanderBar.autohide)) return 0;
        let h = meanderBar && meanderBar.height !== undefined ? Number(meanderBar.height) : 40;
        if (isNaN(h)) h = 40;
        return Math.round(Math.max(28, Math.min(48, h)) * (Scaler.uiScale || 1));
    }
    readonly property string fontFamily: ThemeBackend.fontFamily

    function barSizeFor(screenName) { return root.barSize; }
    function showTooltip(target, text) {}
    function hideTooltip(target) {}

    // Omarchy's panel hotkeys (SUPER+CTRL+A/B/W/...) summon a bar widget by its
    // Omarchy id; Meander answers with its own popout for the same job.
    readonly property var widgetTargets: ({
        "omarchy.audio": ["volume", ""],
        "omarchy.volume": ["volume", ""],
        "omarchy.network": ["network", "wifi"],
        "omarchy.bluetooth": ["network", "bt"],
        "omarchy.clock": ["calendar", ""],
        "omarchy.weather": ["calendar", ""],
        "omarchy.elsewhen": ["calendar", ""],
        "omarchy.power": ["system", ""],
        "omarchy.battery": ["system", ""],
        "omarchy.indicators": ["system", ""],
        "omarchy.media": ["music", ""],
        "omarchy.notifications": ["notifications", ""]
    })

    function targetFor(id) {
        return root.widgetTargets[String(id || "")] || null;
    }

    // Third-party Omarchy bar widgets on Meander's bar (PluginWidgets) answer
    // their own panel hotkeys, as on the stock bar.
    function pluginPanel(id) {
        return root.targetFor(id) ? null : PluginWidgets.findPanelWidget(id);
    }

    function summonBarWidget(id) {
        let p = root.pluginPanel(id);
        if (p) { p.open(); return true; }
        let t = root.targetFor(id);
        if (!t || !mainWindow) return false;
        mainWindow.runCommand("open", t[0], t[1]);
        return true;
    }

    // Wi-Fi and Bluetooth share one popout (network, tabs wifi/bt). Omarchy's
    // toggle asks isBarWidgetOpen first and hides on true, so a widget counts
    // as open only while its popout shows its own tab: SUPER+CTRL+B over the
    // Wi-Fi tab then switches to Bluetooth instead of closing the panel.
    function shows(t) {
        if (!t || !mainWindow || mainWindow.activeWidget !== t[0]) return false;
        let tab = t[1] ? mainWindow.activeTab() : "";
        return tab === "" || tab === t[1];
    }

    function hideBarWidget(id) {
        let p = root.pluginPanel(id);
        if (p) { p.close(); return true; }
        let t = root.targetFor(id);
        if (!t || !mainWindow) return false;
        if (root.shows(t)) mainWindow.runCommand("close", "", "");
        return true;
    }

    function isBarWidgetOpen(id) {
        let p = root.pluginPanel(id);
        if (p) return p.opened === true;
        return root.shows(root.targetFor(id));
    }

    function moduleWidgets(id) { return PluginWidgets.moduleWidgets(id); }

    // One popout at a time across Meander's popouts and the widgets' panels
    // (PluginWidgets.closeMeanderPopout is set in Component.onCompleted).
    Connections {
        target: mainWindow
        ignoreUnknownSignals: true
        function onActiveWidgetChanged() {
            // Later: closing, Main clears isClosing before currentActive, so
            // the old popout's name shows for a moment on its way out.
            if (mainWindow.activeWidget !== "hidden") Qt.callLater(() => {
                if (mainWindow.activeWidget !== "hidden") PluginWidgets.closeActive();
            });
        }
    }

    function panelWidgetIdAt(section, index) { return ""; }

    // `omarchy toggle bar transparency` cycles the bar's background; Meander's
    // closest equivalent is its bar style.
    function cycleBackground() {
        let b = Config.getSetting("bar", {});
        let styles = ["modular", "solid", "fill"];
        let cur = typeof b.style === "string" ? b.style : "modular";
        b.style = styles[(styles.indexOf(cur) + 1) % styles.length];
        Config.setSetting("bar", b);
    }

    function debugBarGeometry() { return []; }

    // ------------------------------------------------- host state
    Binding { target: OmarchyHost; property: "shell"; value: root.shell }
    Binding { target: OmarchyHost; property: "pluginRegistry"; value: root.pluginRegistry }
    Binding { target: OmarchyHost; property: "barConfig"; value: root.barConfig }
    Binding { target: OmarchyHost; property: "manifest"; value: root.manifest }
    Binding { target: OmarchyHost; property: "omarchyPath"; value: root.omarchyPath || "/usr/share/omarchy" }
    Binding { target: OmarchyHost; property: "barHidden"; value: root.barHidden }
    Binding { target: OmarchyHost; property: "barWidgetRegistry"; value: root.barWidgetRegistry }

    // isEnabled() is a function, so ownership is re-read whenever the host's
    // config (shell.json) or plugin set changes.
    onBarConfigChanged: OmarchyHost.revision++
    onPluginRegistryChanged: OmarchyHost.revision++
    Connections {
        target: root.shell && root.shell.pluginRegistry ? root.shell.pluginRegistry : null
        ignoreUnknownSignals: true
        function onPluginsChanged() { OmarchyHost.revision++; }
        function onScanFinished() { OmarchyHost.revision++; }
    }
    Timer {
        // shell.json edits from `meander enable/disable` reach the registry
        // without touching barConfig; a slow poll keeps ownership honest.
        interval: 3000
        running: true
        repeat: true
        onTriggered: OmarchyHost.revision++
    }

    // `omarchy toggle bar` (SUPER+SHIFT+SPACE) flips a flag file, as for the
    // stock bar.
    Process {
        id: barHiddenProbe
        running: true
        command: ["bash", "-c", "[[ -f $HOME/.local/state/omarchy/toggles/bar-off ]] && echo yes || echo no"]
        stdout: SplitParser { onRead: line => root.barHidden = String(line).trim() === "yes" }
    }
    FileView {
        path: (Quickshell.env("HOME") || "") + "/.local/state/omarchy/toggles"
        watchChanges: true
        printErrors: false
        onFileChanged: barHiddenProbe.running = true
    }
    IpcHandler {
        target: "omarchy.bar"
        function syncHidden(): void { barHiddenProbe.running = true; }
    }

    // Full keyboard mode (keynav/KeyNav.qml, `meander keys ...`): the bar or
    // dock of the focused monitor takes the keyboard, or a popout opens with
    // the cursor on. bar/dock toggle; Escape (or `off`) gives the keyboard
    // back.
    IpcHandler {
        target: "meander.keys"
        function bar(): void { root.keysFocus("bar"); }
        function dock(): void { root.keysFocus("dock"); }
        function off(): void { KeyNavState.release(); }
        function open(panel: string, arg: string): void {
            KeyNavState.release();
            mainWindow.openWithKeys(panel, arg);
        }
    }
    function keysFocus(kind) {
        const mon = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        const cur = kind === "bar" ? KeyNavState.barScreen : KeyNavState.dockScreen;
        if (cur !== "" && cur === mon) { KeyNavState.release(); return; }
        if (kind === "dock" && !KeyNavState.docks[mon]) return;
        mainWindow.runCommand("close", "", "");
        if (kind === "bar") KeyNavState.focusBar(mon);
        else if (!KeyNavState.focusDock(mon)) console.log("meander: no dock on " + mon + " (Settings > Dock)");
    }

    // ------------------------------------------------- background helpers
    // Upstream's daemon (serpantinumd) started these next to its Quickshell;
    // here the bar owns them, so they live and die with Meander.

    // Screen time for Digital Wellbeing (and the launcher's ranking).
    Process {
        id: screentimeTracker
        running: true
        command: ["meander-core", "screentime", "track", "--db-dir", Caching.getStateDir("focustime")]
        onExited: (code, status) => screentimeRestart.restart()
    }
    Timer {
        id: screentimeRestart
        interval: 15000
        onTriggered: screentimeTracker.running = true
    }

    // The audio engine comes back with whatever EQ was set last (it stays off
    // while the EQ is flat).
    Process {
        running: true
        command: ["bash", "-c", "command -v meander-audio >/dev/null && meander-audio start"]
    }

    // ------------------------------------------------- Meander (Shell.qml)
    LazyLoader {
        id: screenshotLoader
        ScreenshotOverlay {}
    }

    function ensureScreenshotOverlay() {
        if (!screenshotLoader.item) screenshotLoader.active = true;
        return screenshotLoader.item;
    }

    IpcHandler {
        target: "meander.screenshotOverlay"

        function toggle(img: string, editMode: string, audioPrefs: string, cGeom: string, cGeomVideo: string, cMode: string, cBackend: string, targetMon: string): void {
            let overlay = root.ensureScreenshotOverlay();
            if (overlay) overlay.toggleOverlay(img, editMode, audioPrefs, cGeom, cGeomVideo, cMode, cBackend, targetMon);
        }

        function activate(img: string, editMode: string, audioPrefs: string, cGeom: string, cGeomVideo: string, cMode: string, cBackend: string, targetMon: string): void {
            let overlay = root.ensureScreenshotOverlay();
            if (overlay) overlay.activate(img, editMode, audioPrefs, cGeom, cGeomVideo, cMode, cBackend, targetMon);
        }

        function deactivate(): void {
            if (screenshotLoader.item) screenshotLoader.item.deactivate();
        }
    }

    readonly property bool performanceMode: !!(Config.getSetting("general", {}).performance)
    readonly property bool quickactionsEnabled: Config.getSetting("general", {}).quickactions !== false
    readonly property bool dockEnabled: Config.getSetting("dock", {}).enabled !== false

    Main { id: mainWindow }

    Bar {}

    Loader {
        id: lockLoader
        active: OmarchyHost.ownsLock
        sourceComponent: Component { Lock {} }
    }

    WidgetRedactor {}
    LockRedactor {}

    Launcher {}
    Clipboard {}

    Loader {
        active: OmarchyHost.ownsPolkit
        sourceComponent: Component { Polkit {} }
    }

    WellbeingLimitOverlay {}
    PopoutManager {}

    Loader {
        active: root.dockEnabled && OmarchyHost.ownsDock
        sourceComponent: Component { Dock {} }
    }

    Idle {}

    Variants {
        model: root.performanceMode ? [] : Quickshell.screens
        delegate: WidgetLoader {
            required property var modelData
            screen: modelData
            monitorName: modelData.name
        }
    }

    Loader {
        active: !root.performanceMode && OmarchyHost.ownsBackground
        sourceComponent: Component { WallpaperEngine {} }
    }

    Loader {
        active: !root.performanceMode && root.quickactionsEnabled
        sourceComponent: Component { Floating {} }
    }

    OmarchyCompat {
        main: root.mainWindow
        lockScreen: lockLoader.item
    }

    Component.onCompleted: {
        FirstLaunch.checkFirstLaunch();
        // Battery warnings stay Omarchy's unless omarchy.batteryAlerts is on
        // (SysNotif checks the setting itself).
        SysNotif.checkBattery();
        PluginWidgets.closeMeanderPopout = function() {
            if (mainWindow && mainWindow.activeWidget !== "hidden") mainWindow.runCommand("close", "", "");
        };
    }
}
