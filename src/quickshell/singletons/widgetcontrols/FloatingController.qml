pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../../"

Item {
    id: controller

    signal setIndexRequested(var screen, string index)
    signal showSystemUsageRequested(var screen)
    signal showNotesRequested(var screen)
    // Meander: open / toggle / close the quick actions sidebar from the
    // keyboard (`meander quick`); it then holds the keyboard until Escape.
    signal keyOpenRequested(var screen, string tab)
    signal keyToggleRequested(var screen, string tab)
    signal keyCloseRequested()

    function targetScreen(screen) {
        if (screen) return screen;
        if (Quickshell.cursorScreen) return Quickshell.cursorScreen;
        return Quickshell.screens && Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
    }

    // Meander: a hotkey means the monitor in focus, not the one under the
    // pointer.
    function focusedScreen() {
        let mon = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        let list = Quickshell.screens || [];
        for (let i = 0; i < list.length; i++) {
            if (list[i].name === mon) return list[i];
        }
        return targetScreen(null);
    }

    function setIndex(index, screen) {
        let target = targetScreen(screen);
        if (target) controller.setIndexRequested(target, index);
    }

    function showSystemUsage(screen) {
        let target = targetScreen(screen);
        if (target) controller.showSystemUsageRequested(target);
    }

    function showNotes(screen) {
        let target = targetScreen(screen);
        if (target) controller.showNotesRequested(target);
    }

    IpcHandler {
        target: "meander.floating"

        function setIndex(index: string) {
            controller.setIndex(index, null);
        }

        function showSystemUsage() {
            controller.showSystemUsage(null);
        }

        function showNotes() {
            controller.showNotes(null);
        }

        // Meander: tab is a number (0-based) or a name: draw, system, timer,
        // notes, calculator (a prefix will do); "" keeps the current tab.
        function open(tab: string) {
            let target = controller.focusedScreen();
            if (target) controller.keyOpenRequested(target, tab);
        }

        function toggle(tab: string) {
            let target = controller.focusedScreen();
            if (target) controller.keyToggleRequested(target, tab);
        }

        function close() {
            controller.keyCloseRequested();
        }

        function forceReload() {
            Quickshell.reload(true)
        }
    }
}
