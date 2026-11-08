pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// What Meander knows about the Omarchy shell that hosts it.
//
// Meander runs inside the Omarchy shell's Quickshell process as a bar plugin
// (MeanderBar.qml). Several of its modules are "engines" that Omarchy also
// ships: a notification daemon, a polkit agent, a session lock, an OSD, a
// dock and the desktop background. Two of a kind can't share one process (one
// D-Bus name, one ext-session-lock, two OSDs on every key), so each of
// Meander's engines only starts while the matching Omarchy plugin is off.
// `meander enable` turns those off in shell.json (and `meander disable` puts
// them back); until then Meander simply leaves that job to Omarchy.
//
QtObject {
    id: root

    // Injected by MeanderBar.qml from the host's property injection.
    property var shell: null
    property var pluginRegistry: null
    property var barConfig: ({})
    property var manifest: null
    property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
    property bool barHidden: false

    readonly property bool hosted: pluginRegistry !== null

    // Bumped by the adapter whenever the registry or shell.json changes, so
    // the owns* bindings re-evaluate (isEnabled() is a plain function).
    property int revision: 0

    function omarchyEnabled(id) {
        void root.revision;
        if (!root.pluginRegistry || typeof root.pluginRegistry.isEnabled !== "function") return false;
        try {
            // A clone (`omarchy plugin clone`, or another shell's handover
            // copy) stands in for the stock plugin: ask about whichever is live.
            if (root.pluginRegistry.isEnabled(id) === true) return true;
            let live = typeof root.pluginRegistry.resolveEnabledId === "function" ? root.pluginRegistry.resolveEnabledId(id) : id;
            return live !== id && root.pluginRegistry.isEnabled(live) === true;
        } catch (e) {
            return false;
        }
    }

    // Until the host injects its registry (only after the whole bar has
    // loaded, seconds into a shell start) ownership is read from shell.json
    // itself: Meander is the bar and the stock plugin is in `disabledPlugins`.
    // Live clones aren't checked here (`plugins[]` can keep entries whose
    // folder is gone); `meander enable` disables any live clone anyway, and the
    // registry is the truth once injected. Reading the file lets the service
    // entry (MeanderService.qml) start the notification server early enough
    // for `omarchy restart shell`, which waits only 2s for it.
    readonly property FileView shellJson: FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy/shell.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    readonly property var shellConfig: {
        try { return JSON.parse(shellJson.text() || "{}"); } catch (e) { return {}; }
    }

    function fileOwns(id) {
        let c = root.shellConfig || {};
        let off = Array.isArray(c.disabledPlugins) ? c.disabledPlugins : [];
        return !!(c.bar && c.bar.id === "meander.bar" && off.indexOf(id) >= 0);
    }

    // shell.json decides, always: the registry Omarchy injects into a plugin
    // (PluginRegistryApi) answers isEnabled() only for the plugin itself, so on
    // its own it reads every engine as off and Meander would take them all.
    // Where the registry does know (a live clone), it can still veto.
    function owns(id) {
        return root.fileOwns(id) && !(root.hosted && root.omarchyEnabled(id));
    }
    readonly property bool ownsNotifications: owns("omarchy.notifications")
    readonly property bool ownsPolkit: owns("omarchy.polkit")
    readonly property bool ownsLock: owns("omarchy.lock")
    readonly property bool ownsOsd: owns("omarchy.osd")
    readonly property bool ownsDock: owns("omarchy.dock")
    readonly property bool ownsBackground: owns("omarchy.background")

    readonly property string stateHome: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
    readonly property string currentThemeDir: stateHome + "/omarchy/current/theme"
    readonly property string currentBackground: stateHome + "/omarchy/current/background"
    readonly property string themeNameFile: stateHome + "/omarchy/current/theme.name"

    readonly property string version: manifest && manifest.version ? manifest.version : ""
}
