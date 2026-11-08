import QtQuick
import Quickshell
import qs.Ui as OmarchyUi
import qs.Commons as Commons
import "../../../"
import "../../"

// Meander: a third-party Omarchy bar widget (kind "bar-widget") as a Meander
// bar module. See omarchy/PluginWidgets.qml.
//
// The widget is built the way Omarchy's stock bar builds a third-party
// widget: its component from the host's registry, with `bar` set to Omarchy's
// own PluginBarApi (not the bar object), `moduleName` to its plugin id and
// `settings` to its manifest defaults plus its shell.json entry. Its popups
// are Omarchy's KeyboardPanel / PopupCard windows; they hang off the edge of
// Meander's bar (barSizeFor) and share Meander's one-popout-at-a-time rule.
//
// Omarchy widgets are drawn for Omarchy's bar (26px, 12px icons). They lay
// out in those units here too, and the whole widget is scaled so its icon
// matches Meander's status icons, inside a pill padded like the tray's.
BarFaceBase {
    id: root

    readonly property string moduleKey: module ? BarModuleRegistry.normalizeId(module.moduleId) : ""
    readonly property var entry: { void PluginWidgets.entries; return PluginWidgets.entryFor(moduleKey); }
    readonly property string pluginId: entry ? entry.pluginId : moduleKey
    readonly property var widgetComponent: entry ? entry.component : null
    readonly property var moduleSettings: {
        void OmarchyHost.barConfig;
        void PluginWidgets.entries;
        return PluginWidgets.settingsFor(root.pluginId);
    }
    readonly property string displayName: entry && entry.metadata && entry.metadata.displayName
        ? String(entry.metadata.displayName) : pluginId

    // Keeps the module mapped while the widget is hidden (BarModule
    // keepVisible): the widget's own `visible` is then what decides.
    readonly property bool keepVisible: !isPreview && widgetComponent !== null

    readonly property string barPosition: barWindow && barWindow.barPosition ? barWindow.barPosition : "top"

    // ------------------------------------------------- size
    readonly property real nativeBarSize: isVertical ? Commons.Style.bar.sizeVertical : Commons.Style.bar.sizeHorizontal
    readonly property real glyphTarget: s(isCompact ? 14 : 15)
    readonly property real thicknessNow: module && module.thickness > 0 ? module.thickness : nativeBarSize
    readonly property real widgetScale: Math.max(0.5, Math.min(glyphTarget / Math.max(1, Commons.Style.bar.iconSize),
                                                              thicknessNow / Math.max(1, nativeBarSize)))
    readonly property real pad: s(isCompact ? 6 : 8)

    readonly property Item widgetItem: loader.item
    readonly property real naturalAlong: widgetItem ? Math.max(0, Number(isVertical ? widgetItem.implicitHeight : widgetItem.implicitWidth) || 0) : 0
    readonly property real naturalAcross: widgetItem ? Math.max(0, Number(isVertical ? widgetItem.implicitWidth : widgetItem.implicitHeight) || 0) : 0
    readonly property bool widgetShown: widgetItem !== null && widgetItem.visible && naturalAlong > 0.5

    property real targetLength: isPreview ? previewLength
        : (widgetShown ? Math.round(naturalAlong * widgetScale + pad * 2) : 0)
    property bool isFaceVisible: isPreview || widgetComponent !== null

    implicitWidth: isVertical ? (parent ? parent.width : 0) : targetLength
    implicitHeight: isVertical ? targetLength : (parent ? parent.height : 0)

    // ------------------------------------------------- where the bar ends
    // How far the bar reaches in from its screen edge, as Omarchy's popups
    // ask (bar.barSizeFor): they open just past it.
    readonly property real stripSize: {
        const w = barWindow;
        if (!w) return nativeBarSize;
        const m = w.margins;
        const thick = Number(w.barHeight) || nativeBarSize;
        if (barPosition === "bottom") return (m ? m.bottom : 0) + (w.height - (Number(w.baseOffsetY) || 0));
        if (barPosition === "left") return (m ? m.left : 0) + (Number(w.baseOffsetX) || 0) + thick;
        if (barPosition === "right") return (m ? m.right : 0) + (w.width - (Number(w.baseOffsetX) || 0));
        return (m ? m.top : 0) + (Number(w.baseOffsetY) || 0) + thick;
    }

    // The edge that stays put when the widget grows, from its section.
    readonly property string fixedEdge: {
        void configRevision;
        const ms = Config.rawSettings && Config.rawSettings.bar && Config.rawSettings.bar.modules ? Config.rawSettings.bar.modules : {};
        const has = arr => Array.isArray(arr) && arr.some(x => Array.isArray(x)
            ? x.some(y => BarModuleRegistry.normalizeId(y) === root.moduleKey)
            : BarModuleRegistry.normalizeId(x) === root.moduleKey);
        if (has(ms.left)) return "start";
        if (has(ms.right)) return "end";
        return "center";
    }

    // ------------------------------------------------- the bar API
    // A service-less entry shell, as the host gives any replacement bar for
    // a widget placed in shell.json `bar.layout` (null otherwise).
    // Fetched outside any binding: the host's factory caches into one of its
    // own properties, which a binding calling it would then depend on.
    property var entryShell: null
    function refreshEntryShell() {
        const sh = OmarchyHost.shell;
        let next = null;
        if (sh && root.pluginId && typeof sh.pluginShellForBarEntry === "function") {
            try { next = sh.pluginShellForBarEntry("meander.bar", root.pluginId); } catch (e) { next = null; }
        }
        if (next !== root.entryShell) root.entryShell = next;
    }
    readonly property string entryShellKey: {
        const l = OmarchyHost.barConfig && OmarchyHost.barConfig.layout ? OmarchyHost.barConfig.layout : null;
        return (OmarchyHost.shell ? "1" : "0") + "|" + root.pluginId + "|" + JSON.stringify(l);
    }
    onEntryShellKeyChanged: Qt.callLater(refreshEntryShell)

    property var clickTargets: []

    OmarchyUi.PluginBarApi {
        id: api
        pluginId: root.pluginId || "meander.plugin"
        moduleName: root.pluginId || "meander.plugin"
        shell: root.entryShell

        foreground: ThemeBackend.text
        barForeground: ThemeBackend.text
        background: ThemeBackend.base
        urgent: ThemeBackend.red
        fontFamily: ThemeBackend.fontFamily
        position: root.barPosition
        vertical: root.isVertical
        barSize: root.nativeBarSize
        transparent: false
        activePopout: PluginWidgets.activePopout === null ? null
            : (PluginWidgets.popoutApi === api ? PluginWidgets.activePopout : api.foreignPopoutMarker)
        clickTargets: root.clickTargets
        layoutConfig: OmarchyHost.barConfig && OmarchyHost.barConfig.layout ? OmarchyHost.barConfig.layout : ({})

        _showTooltip: function(target, text) { tip.show(target, text); }
        _hideTooltip: function(target) { tip.hide(target); }
        _registerClickTarget: function(target) {
            if (target && root.clickTargets.indexOf(target) === -1) root.clickTargets = root.clickTargets.concat([target]);
        }
        _unregisterClickTarget: function(target) {
            root.clickTargets = root.clickTargets.filter(t => t !== target);
        }
        _requestPopout: function(owner) { PluginWidgets.requestPopout(api, owner); }
        _releasePopout: function(owner) { PluginWidgets.releasePopout(api, owner); }
        _notePopoutCard: function(card) {}
        _popoutCardFor: function(owner) { return null; }
        _switchPanelFrom: function(owner, direction) { return false; }
        _targetBelongsToWindow: function(target, window) {
            return !!target && !!target.QsWindow && target.QsWindow.window === window;
        }
        _moduleWidgets: function(id) { return PluginWidgets.moduleWidgets(id); }
        _run: function(command) {
            if (command) Quickshell.execDetached(["bash", "-c", String(command)]);
        }
        _setCenterHoverRevealSuppressed: function(value) {}

        // Not on PluginBarApi: KeyboardPanel and PopupCard ask for it before
        // falling back to barSize, which here is the widget's layout unit.
        function barSizeFor(screenName) { return root.stripSize; }
    }

    // ------------------------------------------------- the widget
    Item {
        id: stage
        anchors.centerIn: parent
        width: loader.width
        height: loader.height
        scale: root.widgetScale
        visible: !root.isPreview

        Loader {
            id: loader
            active: !root.isPreview && root.widgetComponent !== null && (!root.module || root.module.moduleActive)
            sourceComponent: root.widgetComponent
            width: item ? (root.isVertical ? root.nativeBarSize : Math.max(1, root.naturalAlong)) : 0
            height: item ? (root.isVertical ? Math.max(1, root.naturalAlong) : root.nativeBarSize) : 0

            property Item registered: null

            function inject() {
                const t = item;
                if (!t) return;
                // Ahead of bar, as the stock bar does.
                if ("fixedEdge" in t) t.fixedEdge = root.fixedEdge;
                if ("bar" in t) t.bar = api;
                if ("moduleName" in t) t.moduleName = root.pluginId;
                if ("settings" in t) t.settings = root.moduleSettings;
            }

            onLoaded: {
                inject();
                Qt.callLater(inject);
                if (registered) PluginWidgets.removeInstance(root.pluginId, registered);
                registered = item;
                PluginWidgets.addInstance(root.pluginId, item);
            }
            onItemChanged: {
                if (!item && registered) {
                    PluginWidgets.removeInstance(root.pluginId, registered);
                    registered = null;
                }
            }
            onStatusChanged: {
                if (status === Loader.Error) console.warn("meander: bar widget " + root.pluginId + " failed to load");
            }
            Component.onDestruction: {
                if (registered) PluginWidgets.removeInstance(root.pluginId, registered);
                if (PluginWidgets.popoutApi === api) PluginWidgets.closeActive();
            }
        }
    }

    onModuleSettingsChanged: loader.inject()
    onFixedEdgeChanged: loader.inject()

    // ------------------------------------------------- Settings preview
    readonly property real previewLength: Math.round(previewGlyph.implicitWidth + pad * 2)
    Text {
        id: previewGlyph
        visible: root.isPreview
        anchors.centerIn: parent
        text: PluginWidgets.glyph
        color: ThemeBackend.text
        font.family: ThemeBackend.iconFont
        font.pixelSize: root.glyphTarget
    }

    // ------------------------------------------------- tooltip
    // The stock bar's shared tooltip, for this widget: shown after a short
    // delay while the target is hovered, beside the bar.
    PopupWindow {
        id: tip
        property Item target: null
        property string text: ""
        property bool armed: false

        function show(t, txt) {
            if (!t || !txt) { hide(t); return; }
            target = t;
            text = String(txt);
            armed = false;
            tipDelay.restart();
        }
        function hide(t) {
            if (t && target !== t) return;
            tipDelay.stop();
            armed = false;
            target = null;
        }

        visible: armed && target !== null && text !== "" && !!target.QsWindow && !!target.QsWindow.window
        color: "transparent"
        implicitWidth: tipLabel.implicitWidth + root.s(16)
        implicitHeight: tipLabel.implicitHeight + root.s(10)

        anchor {
            id: tipAnchor
            window: tip.target && tip.target.QsWindow ? tip.target.QsWindow.window : null
            adjustment: PopupAdjustment.Slide
            edges: Edges.Top | Edges.Left
            gravity: Edges.Bottom | Edges.Right
            rect.width: 1
            rect.height: 1
            onAnchoring: {
                const t = tip.target;
                const w = t && t.QsWindow ? t.QsWindow.window : null;
                if (!t || !w) return;
                const g = root.s(8);
                let lx = t.width / 2 - tip.implicitWidth / 2;
                let ly = t.height + g;
                if (root.barPosition === "bottom") ly = -tip.implicitHeight - g;
                else if (root.barPosition === "left") { lx = t.width + g; ly = t.height / 2 - tip.implicitHeight / 2; }
                else if (root.barPosition === "right") { lx = -tip.implicitWidth - g; ly = t.height / 2 - tip.implicitHeight / 2; }
                const p = w.contentItem.mapFromItem(t, lx, ly);
                tipAnchor.rect.x = Math.round(p.x);
                tipAnchor.rect.y = Math.round(p.y);
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: Math.min(ThemeBackend.borderRadius, height / 2)
            color: ThemeBackend.base
            border.width: 1
            border.color: ThemeBackend.surface1

            Text {
                id: tipLabel
                anchors.centerIn: parent
                text: tip.text
                textFormat: Text.PlainText
                color: ThemeBackend.text
                font.family: ThemeBackend.fontFamily
                font.pixelSize: root.s(12)
            }
        }

        Timer {
            id: tipDelay
            interval: 400
            onTriggered: tip.armed = tip.target !== null
        }
    }
}
