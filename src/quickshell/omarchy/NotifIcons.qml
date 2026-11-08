pragma Singleton
import QtQuick
import Quickshell
import "../"

// What a notification card shows in its icon slot, chosen as Omarchy's own
// toasts choose it (shell/plugins/notifications/Toast.qml, `thumb`): the
// sender's picture, else an icon-theme icon for the app or the site it came
// from, else that app's desktop-entry icon, else the omarchy-glyph hint.
// Upstream drew only the app icon name and dropped the sender's picture.
//
// Omarchy's logic (Icons.js for the names, Security.js for which picture
// paths may be read, Markup.js for a browser notification's site, Delivery.js
// for its glyph font) is loaded in place, never copied, as Omacale loads it.
// Without it (an Omarchy before those files) the slot gets the sender's
// picture and the app icon only.
Singleton {
    id: root

    readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
    property var logic: null

    Component.onCompleted: {
        const src = 'import QtQuick\n'
            + 'import "Icons.js" as I\nimport "Security.js" as S\nimport "Markup.js" as M\nimport "Delivery.js" as D\n'
            + 'QtObject {\n'
            + '  readonly property bool ok: typeof I.candidates === "function" && typeof S.localImageUrl === "function"\n'
            + '                             && typeof M.identify === "function" && typeof M.regroup === "function"\n'
            + '  function candidates(row) { return I.candidates(row) }\n'
            + '  function isSymbolic(url) { return I.isSymbolic(url) }\n'
            + '  function localImageUrl(path) { return S.localImageUrl(path) }\n'
            + '  function identify(row) { return M.identify(row) }\n'
            + '  function regroup(row) { return M.regroup(row) }\n'
            + '  function safeGlyph(g) { return typeof S.safeGlyph === "function" ? S.safeGlyph(g) : "" }\n'
            + '  function omarchyGlyph(g) { return typeof D.omarchyGlyph === "function" && D.omarchyGlyph(g) }\n'
            + '}';
        try {
            const o = Qt.createQmlObject(src, root, "file://" + root.omarchyPath + "/shell/plugins/notifications/MeanderIconLogic.qml");
            if (o.ok) root.logic = o;
            else { o.destroy(); console.warn("Meander: Omarchy's notification icon logic is incomplete; notification icons use the app icon only"); }
        } catch (e) {
            console.warn("Meander: Omarchy's notification icon logic could not be loaded; notification icons use the app icon only:", e);
        }
    }

    readonly property var qsImage: /^image:\/\/qsimage\/[0-9]+\/[0-9]+$/

    // The sender's picture as a URL to load, "" for none. As Omarchy's
    // Store.snapshot: image://icon/<name> is a theme name (`-i some-icon`),
    // not a picture; qsimage is the live notification's own pixels; anything
    // else must be a local file Security.localImagePath accepts.
    function picture(m) {
        const img = String(m && m.senderImage || "");
        if (!img) return "";
        if (qsImage.test(img)) return img;
        if (img.indexOf("image://icon/") === 0 && !/^image:\/\/icon\/(?:\/|file:)/i.test(img)) return "";
        if (root.logic) return root.logic.localImageUrl(img);
        return img.charAt(0) === "/" ? "file://" + img : (/^file:\/\/\//.test(img) ? img : "");
    }

    // The row Omarchy's Icons.candidates reads.
    function row(m) {
        const app = String(m && m.appName || "");
        const img = String(m && m.senderImage || "");
        let named = "";
        if (img.indexOf("image://icon/") === 0 && !/^image:\/\/icon\/(?:\/|file:)/i.test(img)) named = img.substring("image://icon/".length);
        let appIcon = String(m && m.iconPath || "") || named || String(m && m.desktopEntry || "");
        // Store.normalise: a path (Chrome's desktop-entry hint) names no icon.
        if (!/^[a-zA-Z0-9_.-]{1,256}$/.test(appIcon)) appIcon = "";
        const r = { app: app, appIcon: appIcon, source: app, groupKey: "", key: String(m && m.uid || "") };
        if (root.logic) {
            r.source = root.logic.identify({ app: app, body: String(m && m.body || ""), summary: String(m && m.summary || "") }).source;
            r.groupKey = root.logic.regroup(r);
        }
        return r;
    }

    function entryIcon(icon) {
        const v = String(icon || "");
        return v.charAt(0) === "/" ? "file://" + v : (v ? Quickshell.iconPath(v, true) : "");
    }

    function firstOf(names, look) {
        for (let i = 0; i < names.length; i++) {
            const found = look(names[i]);
            if (found) return found;
        }
        return "";
    }

    // Every source worth trying, best first; a card moves to the next when
    // one fails to load. `withPicture` false is for an app's group header.
    // Meander's own resolved app icon (NotificationManager.resolveApp) goes
    // last, so nothing it found before is lost.
    function sources(m, withPicture) {
        const appsRevision = DesktopEntries.applications.values.length;
        const found = [];
        if (withPicture !== false) found.push(picture(m));
        const r = row(m);
        if (root.logic) {
            const want = root.logic.candidates(r);
            found.push(firstOf(want.themed, name => Quickshell.iconPath(name, true)));
            found.push(firstOf(want.entries, name => {
                const entry = DesktopEntries.heuristicLookup(name);
                return entry ? entryIcon(entry.icon) : "";
            }));
        } else if (r.appIcon) {
            found.push(Quickshell.iconPath(r.appIcon, true));
        }
        const own = String(m && m.icon || "");
        if (own) found.push(own.indexOf("://") > 0 ? own : entryIcon(own));
        return found.filter((url, i) => url && found.indexOf(url) === i);
    }

    function isSymbolic(url) {
        if (root.logic) return root.logic.isSymbolic(url);
        return /-symbolic(\.[A-Za-z]+)?$/.test(String(url || "").split("?")[0]);
    }

    function glyph(m) {
        const g = String(m && m.glyph || "");
        return root.logic ? root.logic.safeGlyph(g) : (g.length <= 16 ? g : "");
    }

    // Omarchy's own marks sit at U+E900.. and draw in its "omarchy" font.
    function glyphFont(m) {
        return root.logic && root.logic.omarchyGlyph(glyph(m)) ? "omarchy" : ThemeBackend.iconFont;
    }
}
