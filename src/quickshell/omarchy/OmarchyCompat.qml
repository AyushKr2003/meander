import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import "../"

// Omarchy's own IPC, answered by Meander.
//
// Omarchy's commands talk to its shell over IPC: `omarchy system lock` calls
// `lock lock`, the brightness keys `osd show`, `omarchy toggle notification
// silencing` `notifications toggleDnd`, `omarchy theme set` / `bg set`
// `background themeTransition` / `set`. Once Meander owns one of those engines
// (the Omarchy plugin is off, see OmarchyHost) nothing else answers the
// target, so this file does, with Meander's module, and every Omarchy command
// and keybind keeps working. A target is left empty while Omarchy still owns
// it, which is how a ShellIpc stays silent.
Item {
    id: compat
    visible: false

    // Set by MeanderBar.qml.
    property var main: null
    property var lockScreen: null

    function notifSettings() {
        return Config.getSetting("notifications", {});
    }

    function dndOn() {
        let n = notifSettings();
        return Boolean(n && n.dnd);
    }

    function setDnd(on) {
        let n = notifSettings();
        n.dnd = Boolean(on);
        Config.setSetting("notifications", n);
    }

    // Newest live notification, for act/dismissOne/invoke*.
    function newest() {
        let h = NotificationManager.globalNotificationHistory;
        if (!h || h.count === 0) return null;
        return h.get(0);
    }

    function liveOf(entry) {
        if (!entry) return null;
        return NotificationManager.liveNotifs[entry.uid] || entry.notif || null;
    }

    function invoke(entry, index) {
        let n = liveOf(entry);
        if (!n || !n.actions || n.actions.length === 0) return false;
        let i = Math.max(0, Math.min(n.actions.length - 1, index));
        let a = n.actions[i];
        if (a && typeof a.invoke === "function") {
            a.invoke();
            return true;
        }
        return false;
    }

    Commons.ShellIpc {
        target: OmarchyHost.ownsLock && compat.lockScreen ? "lock" : ""

        function lock(): string {
            if (!compat.lockScreen) return "failed";
            compat.lockScreen.lock();
            return "ok";
        }
        function isLocked(): string {
            return compat.lockScreen && (compat.lockScreen.sessionLocked || compat.lockScreen.lockPending) ? "true" : "false";
        }
        function status(): string {
            let l = compat.lockScreen;
            return JSON.stringify({
                locked: !!(l && l.sessionLocked),
                requested: !!(l && l.lockPending),
                pending: !!(l && l.lockPending),
                sessionLocked: !!(l && l.sessionLocked),
                secure: !!(l && l.sessionLocked),
                passwordPam: true,
                engine: "meander"
            });
        }
        // Omarchy's lock preview is a dev aid for its own view; Meander's
        // equivalent is its lock-screen redactor.
        function preview(): string {
            Quickshell.execDetached(["bash", Caching.meanderDir + "/scripts/qs_manager.sh", "lock-redactor"]);
            return "ok";
        }
        function hidePreview(): string { return "ok"; }
    }

    Commons.ShellIpc {
        target: OmarchyHost.ownsOsd ? "osd" : ""

        // Omarchy sends {icon, message, value, ...}. Meander draws volume, mic
        // and brightness from its own watchers; the rest has no Meander OSD
        // kind, so it goes out as a short transient notification.
        function show(payloadJson: string): string {
            let p = {};
            try { p = JSON.parse(payloadJson || "{}"); } catch (e) { p = {}; }
            let icon = String(p.icon || "");
            let value = p.value !== undefined && p.value !== "" ? Number(p.value) : NaN;
            if (icon === "brightness" || icon.indexOf("display-brightness") === 0) {
                OsdController.show("brightness", isNaN(value) ? undefined : Math.round(value));
            } else if (icon.indexOf("volume") !== -1 || icon.indexOf("audio") === 0) {
                OsdController.show("volume");
            } else if (icon.indexOf("mic") !== -1) {
                OsdController.show("mic");
            } else {
                let text = String(p.message || "");
                if (!isNaN(value)) text = (text ? text + " " : "") + (p.progressText || (value + "%"));
                if (text === "" && icon !== "") text = icon;
                if (text !== "")
                    Quickshell.execDetached(["notify-send", "-a", "Omarchy", "-u", "low", "-t", "1500", "-h", "boolean:transient:true", text]);
            }
            return "ok";
        }
        function close(): string { OsdController.hide(); return "ok"; }
        function state(): string { return OsdController.isVisible ? "open" : "closed"; }
        function ping(): string { return "ok"; }
    }

    Commons.ShellIpc {
        target: OmarchyHost.ownsNotifications ? "notifications" : ""

        function ping(): string { return "ok"; }
        function isDnd(): string { return compat.dndOn() ? "on" : "off"; }
        function toggleDnd(): string {
            compat.setDnd(!compat.dndOn());
            return compat.dndOn() ? "on" : "off";
        }
        function setDnd(value: string): string {
            let v = String(value).toLowerCase();
            compat.setDnd(v === "true" || v === "1" || v === "on" || v === "yes");
            return compat.dndOn() ? "on" : "off";
        }
        function act(): string { return compat.invoke(compat.newest(), 0) ? "ok" : "none"; }
        function dismissOne(): string {
            let e = compat.newest();
            if (!e) return "none";
            NotificationManager.dismissNotification(e.uid);
            NotificationManager.removePopup(e.uid);
            return "ok";
        }
        function dismissAll(): string { NotificationManager.clearNotifications(); return "ok"; }
        function invokeLast(): string { return compat.invoke(compat.newest(), 0) ? "ok" : "none"; }
        function invokeAction(n: int): string { return compat.invoke(compat.newest(), n - 1) ? "ok" : "none"; }
        function keyboard(): string {
            if (compat.main) compat.main.runCommand("toggle", "notifications", "");
            return "ok";
        }
        function showHistory(): string {
            if (compat.main) compat.main.runCommand("open", "notifications", "");
            return "ok";
        }
        function dismiss(summary: string): string {
            let h = NotificationManager.globalNotificationHistory;
            let needle = String(summary || "");
            for (let i = h.count - 1; i >= 0; i--) {
                let e = h.get(i);
                if (e && needle !== "" && String(e.summary).indexOf(needle) !== -1) {
                    NotificationManager.dismissNotification(e.uid);
                    NotificationManager.removePopup(e.uid);
                }
            }
            return "ok";
        }
        function count(): string { return String(NotificationManager.activePopupsModel.count); }
        function expand(): string { return keyboard(); }
        function probe(): string {
            return JSON.stringify({ engine: "meander", popups: NotificationManager.activePopupsModel.count, history: NotificationManager.globalNotificationHistory.count, dnd: compat.dndOn() });
        }
    }

    // ---------------------------------------------------------- background
    // Omarchy's theme and background commands. Meander's wallpaper engine
    // draws the desktop, with its own transitions.
    function followsOmarchy() {
        let w = Config.getSetting("omarchy", {});
        return !w || w.followBackground !== false;
    }

    function setBackground(path, transition) {
        if (!path) return;
        Wallpaper.setWallpaper("all", path, transition || "");
    }

    function applyThemeColors(colorsB64, shellB64) {
        let colorsRaw = "";
        let shellRaw = "";
        try { colorsRaw = Qt.atob(String(colorsB64 || "")); } catch (e) { colorsRaw = ""; }
        try { shellRaw = Qt.atob(String(shellB64 || "")); } catch (e2) { shellRaw = ""; }
        if (colorsRaw !== "") Commons.Color.loadColors(colorsRaw);
        if (shellRaw !== "") Commons.Color.loadShell(shellRaw);
        Commons.Style.scheduleRefresh();
        ThemeBackend.reloadOmarchyPalette();
    }

    Process {
        id: currentBackgroundProc
        command: ["readlink", "-f", OmarchyHost.currentBackground]
        stdout: StdioCollector {
            onStreamFinished: {
                let p = this.text.trim();
                if (p !== "" && compat.followsOmarchy()) compat.setBackground(p, "");
            }
        }
    }

    function refreshBackground() {
        currentBackgroundProc.running = false;
        currentBackgroundProc.running = true;
    }

    Commons.ShellIpc {
        target: OmarchyHost.ownsBackground ? "background" : ""

        function refresh(): void { compat.refreshBackground(); }
        function set(path: string): void { if (compat.followsOmarchy()) compat.setBackground(path, ""); }
        function setInstant(path: string): void { if (compat.followsOmarchy()) compat.setBackground(path, ""); }
        function setSuspended(value: string): void {
            let v = String(value).toLowerCase();
            Wallpaper.setPlayback("all", (v === "true" || v === "1" || v === "on" || v === "yes") ? "pause" : "play");
        }
        function transition(fromPath: string, path: string): void { if (compat.followsOmarchy()) compat.setBackground(path, ""); }
        function themeTransition(fromPath: string, path: string, finalPath: string, colorsB64: string, shellB64: string): void {
            compat.applyThemeColors(colorsB64, shellB64);
            if (compat.followsOmarchy()) compat.setBackground(finalPath || path, "");
        }
        function prepare(path: string): void {}
    }

    // A fresh install has no Meander wallpaper yet: start from Omarchy's.
    Timer {
        interval: 2500
        running: OmarchyHost.ownsBackground
        onTriggered: {
            if (Wallpaper.getWallpaperPath("") === "") compat.refreshBackground();
        }
    }

    Commons.ShellIpc {
        target: OmarchyHost.ownsDock ? "omarchy.dock" : ""
        function refresh(): void {}
        function apps(): void { if (compat.main) compat.main.runCommand("toggle", "applauncher", ""); }
    }
}
