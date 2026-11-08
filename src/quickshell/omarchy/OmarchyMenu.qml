pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../"

// The Omarchy menu as launcher rows: typing ":" in Meander's launcher lists
// it, ":theme" searches it, and Enter on a submenu steps into it
// (":Appearance › "). Upstream has no such mode; it is Meander's.
//
// Omarchy is the engine. The rows come from the same files Omarchy's own menu
// reads (the shipped omarchy-menu.jsonc, the user's extension, the language
// catalog), and every rule that shapes them (JSONC parsing, the per-key
// merge, translations, the when/checked/disabled guard batch, search
// matching and ranking) is Omarchy's MenuModel.js, loaded from $OMARCHY_PATH
// at runtime instead of copied, so the launcher lists what `omarchy menu`
// lists. Its path is only known at runtime, so it is imported through
// Qt.createQmlObject rather than a static import.
//
// Picking a row runs its action the way Omarchy's menu does (`bash -lc`).
// Submenus filled by one of the menu's providers (fonts, kernels, languages)
// are enumerated inside Omarchy's menu, so those open it at that route.
QtObject {
    id: root

    readonly property string omarchyPath: OmarchyHost.omarchyPath
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string defaultMenuPath: omarchyPath + "/default/omarchy/omarchy-menu.jsonc"
    readonly property string userMenuPath: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"
    readonly property string languagePath: Quickshell.env("OMARCHY_LANGUAGE_FILE") || (configHome + "/omarchy/language")

    property var model: null
    property var defaultItems: []
    property var userItems: []
    property string language: "en"
    property var catalog: ({})

    property var items: ({})
    property var itemOrder: []
    property var whenResults: ({})
    property var checkedResults: ({})
    property var disabledResults: ({})

    // Guards run once per launcher opening, when ":" is first typed.
    property bool guardsFresh: false
    property bool guardsPending: false

    readonly property bool available: model !== null && itemOrder.length > 1

    // Bumped whenever the rows could read differently.
    signal changed()

    Component.onCompleted: {
        try {
            let url = "file://" + root.omarchyPath + "/shell/plugins/menu/MenuModel.js";
            let holder = Qt.createQmlObject(
                'import QtQuick\nimport "' + url + '" as MenuModel\nQtObject { readonly property var m: MenuModel }',
                root, "OmarchyMenuModel");
            if (holder && holder.m && typeof holder.m.mergeMenuSources === "function") root.model = holder.m;
        } catch (e) {
            console.warn("[Meander] Omarchy menu model unavailable:", e);
        }
        root.rebuild();
    }

    property list<QtObject> watchers: [
        FileView {
            path: root.defaultMenuPath
            watchChanges: true
            printErrors: false
            onLoaded: { if (root.model) root.defaultItems = root.model.keepMenuRows(root.defaultItems, text(), true); root.rebuild(); }
            onFileChanged: reload()
        },
        FileView {
            path: root.userMenuPath
            watchChanges: true
            printErrors: false
            onLoaded: { if (root.model) root.userItems = root.model.keepMenuRows(root.userItems, text(), false); root.rebuild(); }
            onLoadFailed: { root.userItems = []; root.rebuild(); }
            onFileChanged: reload()
        },
        FileView {
            path: root.languagePath
            watchChanges: true
            printErrors: false
            onLoaded: root.setLanguage(text())
            onLoadFailed: root.setLanguage("")
            onFileChanged: reload()
        },
        FileView {
            path: root.omarchyPath + "/default/i18n/" + root.language + "/menu.json"
            watchChanges: true
            printErrors: false
            onLoaded: {
                try {
                    let parsed = JSON.parse(text() || "{}");
                    root.catalog = (parsed && typeof parsed === "object" && !Array.isArray(parsed)) ? parsed : ({});
                } catch (e) {
                    root.catalog = ({});
                }
                root.rebuild();
            }
            onLoadFailed: { root.catalog = ({}); root.rebuild(); }
            onFileChanged: reload()
        }
    ]

    function setLanguage(raw) {
        let code = String(raw || "").trim();
        if (!/^[a-z]{2,3}(-[A-Za-z]{2})?$/.test(code)) code = "en";
        root.language = code;
    }

    function rebuild() {
        if (!root.model) return;
        let translated = root.model.applyTranslations(root.defaultItems, root.catalog);
        let rootLabel = root.catalog.root && root.catalog.root.label;
        let merged = root.model.mergeMenuSources(translated, root.userItems, rootLabel);
        root.items = merged.items;
        root.itemOrder = merged.itemOrder;
        root.guardsFresh = false;
        root.changed();
    }

    // Called when the launcher closes, so the next ":" re-reads the guards
    // (a theme picked, a package installed since).
    function invalidate() {
        root.guardsFresh = false;
    }

    function ensureGuards() {
        if (root.guardsFresh || !root.model || root.itemOrder.length === 0) return;
        if (guardProc.running) { root.guardsPending = true; return; }
        root.guardsPending = false;
        let script = root.model.guardScript(root.items);
        root.guardsFresh = true;
        if (!script) return;
        guardProc.collected = "";
        guardProc.command = ["bash", "-lc", script];
        guardProc.running = true;
    }

    property Process guardProc: Process {
        id: guardProc
        property string collected: ""
        stdout: SplitParser {
            onRead: data => guardProc.collected += data + "\n"
        }
        onExited: (exitCode, exitStatus) => {
            // Same rule as Omarchy's menu: a batch that did not finish keeps the
            // last complete answers.
            if (exitCode === 0 && exitStatus === 0) {
                let w = ({}), c = ({}), d = ({});
                let lines = guardProc.collected.split("\n");
                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i].trim();
                    let colon = line.lastIndexOf(":");
                    if (colon < 0) continue;
                    let value = line.substring(colon + 1) === "1";
                    let rest = line.substring(0, colon);
                    let tagAt = rest.lastIndexOf(":");
                    if (tagAt < 0) continue;
                    let id = rest.substring(0, tagAt);
                    let tag = rest.substring(tagAt + 1);
                    if (tag === "w") w[id] = value;
                    else if (tag === "c") c[id] = value;
                    else if (tag === "d") d[id] = value;
                }
                root.whenResults = w;
                root.checkedResults = c;
                root.disabledResults = d;
                root.changed();
            }
            if (root.guardsPending) {
                root.guardsFresh = false;
                Qt.callLater(root.ensureGuards);
            }
        }
    }

    function entry(id) {
        return root.items[id] || null;
    }

    function pathFor(id) {
        return root.model ? root.model.pathFor(root.items, id) : "";
    }

    // A row shows only if it and every menu above it pass their `when:`.
    function shown(e) {
        if (!e || e.id === "root") return false;
        let cur = e;
        for (let guard = 0; cur && cur.id !== "root" && guard < 32; guard++) {
            if (!root.model.isVisible(root.items, root.itemOrder, root.whenResults, cur, 0)) return false;
            cur = root.entry(cur.parent);
        }
        return true;
    }

    // Text after ":" -> { scope, filter }. "Appearance › Theme › gr" is the
    // search "gr" inside Appearance › Theme; a path that names no submenu is
    // searched as typed.
    function parse(rest) {
        let text = String(rest || "");
        let parts = text.split("›");
        if (parts.length > 1) {
            let path = parts.slice(0, -1).map(p => p.trim()).filter(p => p.length > 0).join(" › ");
            for (let i = 0; i < root.itemOrder.length; i++) {
                let e = root.entry(root.itemOrder[i]);
                if (e && (e.kind === "menu") && root.pathFor(e.id) === path)
                    return { scope: e.id, filter: parts[parts.length - 1].trim() };
            }
        }
        return { scope: "root", filter: text.trim() };
    }

    function childPreview(id) {
        let labels = [];
        for (let i = 0; i < root.itemOrder.length && labels.length < 4; i++) {
            let c = root.entry(root.itemOrder[i]);
            if (c && c.parent === id && root.shown(c)) labels.push(c.label);
        }
        return labels.length > 0 ? labels.join(", ") + (labels.length === 4 ? ", …" : "") : "";
    }

    function row(e, searching) {
        let target = e.kind === "link" ? e.target : e.id;
        let isMenu = e.kind === "menu" || e.kind === "link";
        let description = e.description || "";
        if (searching) {
            let parent = root.model.parentPathFor(root.items, e.id);
            description = parent + (parent && description ? " · " : "") + description;
        } else if (!description && isMenu && !e.provider) {
            description = root.childPreview(target);
        }
        return {
            omarchyId: e.id,
            name: root.model.labelFor(e, root.checkedResults, root.disabledResults) + (isMenu ? "  ›" : ""),
            description: description,
            fontIcon: e.icon || (isMenu ? "󰍜" : "󰘳"),
            iconFont: e.iconFont || ""
        };
    }

    // Launcher rows for the text after ":".
    function rows(rest) {
        if (!root.available) return [];
        root.ensureGuards();
        let q = root.parse(rest);
        let out = [];
        if (q.filter.length === 0) {
            for (let i = 0; i < root.itemOrder.length; i++) {
                let e = root.entry(root.itemOrder[i]);
                if (e && e.parent === q.scope && root.shown(e)) out.push(root.row(e, false));
            }
            return out;
        }
        let hits = [];
        for (let i = 0; i < root.itemOrder.length; i++) {
            let e = root.entry(root.itemOrder[i]);
            if (!e || e.id === "root") continue;
            if (q.scope !== "root" && !root.model.isDescendantOf(root.items, e.id, q.scope)) continue;
            if (!root.model.matchesQuery(e, q.filter, root.shown(e))) continue;
            hits.push({ e: e, score: root.model.searchScore(root.items, e, q.filter) });
        }
        hits.sort((a, b) => a.score - b.score);
        for (let j = 0; j < hits.length; j++) out.push(root.row(hits[j].e, true));
        return out;
    }

    // Enter on a row. Returns the launcher text to step into a submenu, or ""
    // once the row has been handed off (the launcher then closes), or null
    // for a row that does nothing (already installed).
    function activate(id) {
        let e = root.entry(id);
        if (!e) return null;
        if (root.model.isDisabled(root.disabledResults, e)) return null;
        if (e.kind === "action") {
            Quickshell.execDetached(["bash", "-lc", e.action]);
            return "";
        }
        let target = e.kind === "link" ? e.target : e.id;
        let t = root.entry(target);
        if (t && t.provider) {
            Quickshell.execDetached(["omarchy-menu", "summon", target]);
            return "";
        }
        return ":" + root.pathFor(target) + " › ";
    }
}
