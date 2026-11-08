pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../"

// Third-party Omarchy bar widgets on Meander's bar.
//
// Omarchy's stock bar hosts any enabled plugin of kind "bar-widget": the shell
// loads its `barWidget` entry point into the bar widget registry, and the bar
// places it from shell.json `bar.layout`. A replacement bar gets a read-only
// snapshot of that registry (`barWidgetRegistry`, refreshed on every rescan)
// and has to host the widgets itself. This is Meander's side of it:
//
//   - every third-party widget in the registry becomes a Meander bar module
//     (`types`, read by BarModuleRegistry), keyed by its plugin id in lower
//     case, so it shows up in Settings -> Bar and is placed from Meander's
//     own `bar.modules` like an upstream module;
//   - bar/faces/plugin/PluginFace.qml instantiates the widget with Omarchy's
//     own `PluginBarApi` as its `bar`, as the stock bar does for a
//     third-party widget;
//   - this object keeps what the stock bar keeps across its widgets: the live
//     instances (moduleWidgets, panel hotkeys) and the single open popout,
//     which also closes Meander's own popouts and is closed by them.
//
// First-party widgets (omarchy.audio, omarchy.clock, ...) are left out: the
// stock bar hands them its whole Bar object, not the plugin API, and Meander
// has its own module for each job.
QtObject {
    id: root

    readonly property var registry: OmarchyHost.barWidgetRegistry

    // id (lower case) -> { pluginId, component, metadata }
    property var entries: ({})
    // id -> bar module type, in BarModuleRegistry's shape.
    property var types: ({})
    // Every id seen this session, in order. It never shrinks, so a widget
    // that is disabled and enabled again keeps its bar module (TopBar/SideBar
    // build one delegate per id, and rebuilding them all for one widget would
    // restart the whole bar's layout).
    property var ids: []

    readonly property string glyph: "󰐱"

    function keyOf(id) {
        return String(id || "").toLowerCase().trim();
    }

    function sync() {
        const reg = root.registry;
        const widgets = reg && reg.widgets ? reg.widgets : {};
        const nextEntries = {};
        const nextTypes = {};
        const nextIds = root.ids.slice();
        for (const id in widgets) {
            const w = widgets[id];
            const meta = w && w.metadata ? w.metadata : {};
            if (!w || !w.component) continue;
            if (meta.source !== "plugin" || meta.firstParty === true) continue;
            const pluginId = String(meta.pluginId || id);
            const key = root.keyOf(pluginId);
            if (!key) continue;
            nextEntries[key] = { pluginId: pluginId, component: w.component, metadata: meta };
            nextTypes[key] = {
                name: String(meta.displayName || pluginId),
                desc: String(meta.description || ""),
                icon: root.glyph,
                defaultVariant: "default",
                face: "faces/plugin/PluginFace.qml",
                plugin: true,
                pluginId: pluginId,
                category: String(meta.category || "Plugin")
            };
            if (nextIds.indexOf(key) === -1) nextIds.push(key);
        }
        root.entries = nextEntries;
        root.types = nextTypes;
        if (nextIds.length !== root.ids.length) root.ids = nextIds;
    }

    readonly property Connections registryWatch: Connections {
        target: root.registry
        ignoreUnknownSignals: true
        function onRevisionChanged() { root.sync(); }
        function onWidgetsChanged() { root.sync(); }
    }
    onRegistryChanged: sync()
    Component.onCompleted: sync()

    function entryFor(id) {
        return root.entries[root.keyOf(id)] || null;
    }

    // The widget's settings: its manifest defaults, then its entry in
    // shell.json `bar.layout` if it has one (`omarchy bar set`, and what the
    // widget writes itself through updateEntryInline).
    function settingsFor(id) {
        const e = root.entryFor(id);
        const out = {};
        const defaults = e && e.metadata && e.metadata.defaults ? e.metadata.defaults : {};
        for (const k in defaults) out[k] = defaults[k];
        const layout = OmarchyHost.barConfig && OmarchyHost.barConfig.layout ? OmarchyHost.barConfig.layout : {};
        const want = root.keyOf(e ? e.pluginId : id);
        for (const section in layout) {
            const list = Array.isArray(layout[section]) ? layout[section] : [];
            for (let i = 0; i < list.length; i++) {
                const entry = list[i];
                if (!entry || typeof entry !== "object" || root.keyOf(entry.id) !== want) continue;
                for (const k in entry) if (k !== "id" && k !== "type") out[k] = entry[k];
                return out;
            }
        }
        return out;
    }

    // ------------------------------------------------- live instances
    // pluginId -> [widget item], one per bar surface (monitor).
    property var instances: ({})

    function addInstance(pluginId, item) {
        const key = root.keyOf(pluginId);
        if (!key || !item) return;
        const next = Object.assign({}, root.instances);
        const list = (next[key] || []).filter(it => it && it !== item);
        list.push(item);
        next[key] = list;
        root.instances = next;
    }

    function removeInstance(pluginId, item) {
        const key = root.keyOf(pluginId);
        if (!root.instances[key]) return;
        const next = Object.assign({}, root.instances);
        next[key] = next[key].filter(it => it && it !== item);
        root.instances = next;
    }

    function moduleWidgets(pluginId) {
        return (root.instances[root.keyOf(pluginId)] || []).filter(it => !!it);
    }

    // A panel hotkey (`omarchy-shell shell summon <id>`) reaches the bar; the
    // copy on the focused monitor answers, as on the stock bar.
    function findPanelWidget(pluginId) {
        const items = root.moduleWidgets(pluginId).filter(it =>
            typeof it.open === "function" && typeof it.close === "function" && it.opened !== undefined);
        if (items.length === 0) return null;
        const open = items.find(it => it.opened === true);
        if (open) return open;
        const mon = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : "";
        const here = items.find(it => {
            const w = it.QsWindow ? it.QsWindow.window : null;
            return w && w.screen && String(w.screen.name) === mon;
        });
        return here || items[0];
    }

    function has(pluginId) {
        return !!root.entryFor(pluginId);
    }

    // ------------------------------------------------- one popout at a time
    property var activePopout: null
    // The PluginBarApi whose widget owns it: the others see a foreign marker.
    property var popoutApi: null
    // Set by MeanderBar: closes Meander's own popout.
    property var closeMeanderPopout: null

    function requestPopout(api, owner) {
        if (!owner || root.activePopout === owner) return;
        const prev = root.activePopout;
        if (prev) {
            try {
                if ("closeForPopoutSwitch" in prev) prev.closeForPopoutSwitch();
                else if ("close" in prev) prev.close();
            } catch (e) {}
        }
        root.activePopout = owner;
        root.popoutApi = api;
        if (typeof root.closeMeanderPopout === "function") root.closeMeanderPopout();
    }

    function releasePopout(api, owner) {
        if (root.activePopout !== owner) return;
        root.activePopout = null;
        root.popoutApi = null;
    }

    function closeActive() {
        const p = root.activePopout;
        if (!p) return;
        try {
            if ("close" in p) p.close();
        } catch (e) {}
        if (root.activePopout === p) {
            root.activePopout = null;
            root.popoutApi = null;
        }
    }
}
