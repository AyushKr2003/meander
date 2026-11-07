pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"
import "Material.js" as Material

Item {
    id: root

    property string fontFamily: "Adwaita Mono"
    property int borderRadius: 8
    property int clampedBorderRadius: {
        const r = borderRadius;
        return Math.floor(
            r <= 24
                ? r
                : 24 + Math.pow(r - 24, 0.55)
        );
    }

    // Hyprland's window corners follow this radius (meander.lua): the value
    // goes to $XDG_STATE_HOME/meander/hypr.lua, which meander.lua reads on
    // every load, and to meander_apply() at once through `hyprctl eval`
    // (a no-op unless meander.lua is loaded).
    onBorderRadiusChanged: hyprRadiusSync.restart()
    Timer {
        id: hyprRadiusSync
        interval: 400
        onTriggered: {
            let r = Math.max(0, Math.round(root.borderRadius));
            let dir = (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/meander";
            Quickshell.execDetached(["bash", "-c",
                "mkdir -p \"$1\" && printf 'return { radius = %s }\\n' \"$2\" > \"$1/hypr.lua\" && " +
                "hyprctl eval \"if meander_apply then meander_apply({ radius = $2 }) end\" >/dev/null 2>&1",
                "meander-hypr", dir, String(r)]);
        }
    }

    property real elementOpacity: 1.0
    property bool blurBackground: false
    property string blurStyle: "blur"
    readonly property real liquidGlassOpacity: 0.1
    readonly property bool glassActive: blurBackground && elementOpacity < 0.999
    readonly property bool liquidGlass: blurBackground && blurStyle === "liquid"

    property color base: "#1e1e2e"
    property color mantle: "#181825"
    property color crust: "#11111b"
    property color _text: "#cdd6f4"
    property color _subtext0: "#a6adc8"
    property color _subtext1: "#bac2de"
    readonly property color text: liquidGlass ? "#ffffff" : _text
    readonly property color subtext0: liquidGlass ? "#ffffff" : _subtext0
    readonly property color subtext1: liquidGlass ? "#ffffff" : _subtext1
    property color surface0: "#313244"
    property color surface1: "#45475a"
    property color surface2: "#585b70"
    property color overlay0: "#6c7086"
    property color overlay1: "#7f849c"
    property color overlay2: "#9399b2"
    property color blue: "#89b4fa"
    readonly property color primary: blue
    property color sapphire: "#74c7ec"
    property color peach: "#fab387"
    property color green: "#a6e3a1"
    property color red: "#f38ba8"
    property color mauve: "#cba6f7"
    property color pink: "#f5c2e7"
    property color yellow: "#f9e2af"
    property color maroon: "#eba0ac"
    property color teal: "#94e2d5"

    property string configPath: Quickshell.env("QS_COLORS_JSON") || "~/.local/state/meander/qs_colors.json"
    property string matugenConfigPath: (typeof Caching !== "undefined" && Caching.stateDir ? Caching.stateDir : ((Quickshell.env("HOME") ?? "") + "/.local/state/meander")) + "/qs_matugen_colors.json"

    property bool _readInProgress: false
    property var matugenColors: null
    property var _colorQueue: []
    property int colorsPerFrame: 3

    property var availableFontPaths: ({})
    property var bundledNames: []
    property string activeFontPath: ""

    FontLoader {
        id: iconFontLoader
        source: (typeof Caching !== "undefined" && Caching.meanderDir && Caching.meanderDir !== "")
            ? ("file://" + Caching.meanderDir + "/assets/fonts/SymbolsNerdFontMono-Regular.ttf")
            : ""
    }

    readonly property string iconFont: (iconFontLoader.status === FontLoader.Ready && iconFontLoader.name !== "")
        ? iconFontLoader.name
        : (root.fontFamily !== "" ? root.fontFamily : "sans-serif")
    readonly property bool iconFontReady: iconFontLoader.status === FontLoader.Ready

    onFontFamilyChanged: {
        root.updateActiveFontLoader();
    }

    // ---------------------------------------------------------- Omarchy
    // The "Omarchy" preset (the default): the live Omarchy theme's
    // colors.toml, mapped onto Meander's palette roles. Omarchy rewrites the
    // file on `omarchy theme set`; OmarchyCompat also calls
    // reloadOmarchyPalette() from the theme transition.
    property var omarchyPalette: ({})
    property string omarchyAccent: ""
    property bool omarchyLight: false

    // The "Material" preset: a Material 3 scheme seeded with the Omarchy
    // accent (Material.js, from Omacale), so it follows `omarchy theme set`
    // like the Omarchy preset. Stored as theme.omarchy + theme.material.
    function isMaterialTheme() {
        let t = Config.getSetting("theme", {});
        return root.isOmarchyTheme() && (t.material === true || t.activePreset === "Material");
    }

    function materialVariant() {
        let t = Config.getSetting("theme", {});
        return typeof t.materialVariant === "string" ? t.materialVariant : "tonalspot";
    }

    // Light or dark as the Omarchy theme says (colors.toml `mode`, else its
    // background's lightness); theme.mode "light"/"dark" overrides it.
    function materialLight() {
        let t = Config.getSetting("theme", {});
        if (t.mode === "light") return true;
        if (t.mode === "dark") return false;
        return root.omarchyLight;
    }

    function materialPalette() {
        let seed = root.omarchyAccent || (root.omarchyPalette && root.omarchyPalette.blue) || "";
        if (!seed) return null;
        return Material.scheme(seed, root.materialVariant(), root.materialLight());
    }

    // Settings › Theme › Pure black: any dark palette gets #000 panels.
    function pureBlackOn() {
        let t = Config.getSetting("theme", {});
        return t.pureBlack === true;
    }

    function isOmarchyTheme() {
        let t = Config.getSetting("theme", { "omarchy": true, "activePreset": "Omarchy" });
        if (t.omarchy !== undefined) return t.omarchy === true;
        return t.activePreset === "Omarchy" || t.activePreset === undefined;
    }

    function _mix(a, b, t) {
        let ca = Qt.color(a), cb = Qt.color(b);
        let h = function(v) { let s = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16); return s.length < 2 ? "0" + s : s; };
        return "#" + h(ca.r + (cb.r - ca.r) * t) + h(ca.g + (cb.g - ca.g) * t) + h(ca.b + (cb.b - ca.b) * t);
    }

    function parseOmarchyColors(text) {
        let kv = {};
        let lines = String(text || "").split("\n");
        for (let i = 0; i < lines.length; i++) {
            let m = lines[i].match(/^\s*([A-Za-z0-9_]+)\s*=\s*["']?(#[0-9A-Fa-f]{6,8})["']?/);
            if (m) kv[m[1].toLowerCase()] = m[2].length === 9 ? m[2].substring(0, 7) : m[2];
        }
        if (!kv.background && !kv.color0) return null;
        let pick = function() {
            for (let i = 0; i < arguments.length; i++) if (kv[arguments[i]]) return kv[arguments[i]];
            return "";
        };
        let bg = pick("background", "color0");
        let modeMatch = String(text || "").match(/^\s*mode\s*=\s*["']?(light|dark)/m);
        let bgc = Qt.color(bg);
        root.omarchyLight = modeMatch ? modeMatch[1] === "light" : (0.2126 * bgc.r + 0.7152 * bgc.g + 0.0722 * bgc.b) > 0.5;
        root.omarchyAccent = pick("accent", "blue", "color4");
        let fg = pick("foreground", "color7", "color15") || "#cdd6f4";
        let accent = pick("accent", "blue", "color4") || fg;
        let red = pick("red", "color1") || root._mix(bg, "#f38ba8", 0.8);
        let green = pick("green", "color2") || root._mix(bg, "#a6e3a1", 0.8);
        let yellow = pick("yellow", "color3") || root._mix(bg, "#f9e2af", 0.8);
        let blue = pick("blue", "color4") || accent;
        let magenta = pick("magenta", "color5") || root._mix(bg, "#cba6f7", 0.8);
        let cyan = pick("cyan", "color6") || root._mix(bg, "#94e2d5", 0.8);
        return {
            "base": bg,
            "mantle": pick("dark_background") || root._mix(bg, "#000000", 0.18),
            "crust": pick("darker_background") || root._mix(bg, "#000000", 0.32),
            "surface0": pick("lighter_background") || root._mix(bg, fg, 0.10),
            "surface1": root._mix(bg, fg, 0.18),
            "surface2": root._mix(bg, fg, 0.26),
            "overlay0": pick("muted") || root._mix(bg, fg, 0.38),
            "overlay1": root._mix(bg, fg, 0.48),
            "overlay2": root._mix(bg, fg, 0.58),
            "text": fg,
            "subtext0": pick("dark_foreground") || root._mix(bg, fg, 0.72),
            "subtext1": pick("light_foreground") || root._mix(bg, fg, 0.85),
            // Meander's primary colour role is "blue": Omarchy's accent.
            "blue": accent,
            "sapphire": pick("bright_blue", "color12") || blue,
            "peach": pick("orange", "color9") || root._mix(red, yellow, 0.5),
            "green": green,
            "red": red,
            "mauve": magenta,
            "pink": pick("bright_magenta", "color13") || magenta,
            "yellow": yellow,
            "maroon": pick("bright_red", "color9") || red,
            "teal": cyan
        };
    }

    function applyOmarchyPalette() {
        if (!root.omarchyPalette || !root.omarchyPalette.base) return false;
        let pal = root.isMaterialTheme() ? root.materialPalette() : root.omarchyPalette;
        if (!pal) return false;
        root.applyColorObject(pal);
        if (typeof Matugen !== "undefined" && typeof Matugen.generateFromStatic === "function") {
            let t = Config.getSetting("theme", {});
            Matugen.generateFromStatic(pal, t.mode);
        }
        return true;
    }

    function reloadOmarchyPalette() {
        omarchyColorsFile.reload();
    }

    FileView {
        id: omarchyColorsFile
        path: OmarchyHost.currentThemeDir + "/colors.toml"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let p = root.parseOmarchyColors(text());
            if (!p) return;
            root.omarchyPalette = p;
            if (root.isOmarchyTheme()) root.applyOmarchyPalette();
        }
    }

    // `omarchy theme set` swaps the whole current/theme folder, which a file
    // watch can lose track of; theme.name changes on every switch.
    FileView {
        path: OmarchyHost.themeNameFile
        watchChanges: true
        printErrors: false
        onFileChanged: { reload(); themeSwapDelay.restart(); }
    }

    Timer {
        id: themeSwapDelay
        interval: 400
        onTriggered: omarchyColorsFile.reload()
    }

    function isMatugenTheme() {
        if (typeof Matugen !== "undefined" && typeof Matugen.isMatugenTheme === "function") {
            return Matugen.isMatugenTheme();
        }
        let themeConfig = Config.getSetting("theme", { "matugen": false, "omarchy": true, "activePreset": "Omarchy" });
        if (themeConfig.matugen !== undefined) {
            return themeConfig.matugen === true;
        }
        return themeConfig.theme === "matugen"
            || themeConfig.name === "matugen"
            || themeConfig.currentTheme === "matugen"
            || themeConfig.current === "matugen"
            || themeConfig.activePreset === "Matugen";
    }

    function updateActiveFontLoader() {
        if (!root.fontFamily || root.fontFamily === "") return;
        let key = root.fontFamily.toLowerCase();
        let path = root.availableFontPaths ? root.availableFontPaths[key] : "";

        if (path && root.activeFontPath !== path) {
            root.activeFontPath = path;
        }
    }

    FontLoader {
        id: staticFontLoader
        source: (root.activeFontPath && root.activeFontPath !== "") ? ("file://" + root.activeFontPath) : ""
        onStatusChanged: {
            if (status === FontLoader.Ready) {
                let cur = root.fontFamily;
                root.fontFamily = "";
                root.fontFamily = cur;
            }
        }
    }

    Process {
        id: fontFetcher
        property bool forceRescan: false

        command: {
            let sys = Caching.meanderDir ? (Caching.meanderDir + "/assets/fonts") : "";
            let usr = Caching.stateDir ? (Caching.stateDir + "/fonts") : (Caching.home + "/.local/state/meander/fonts");
            let cacheFile = Caching.stateDir ? (Caching.stateDir + "/fonts_cache.txt") : (Caching.home + "/.local/state/meander/fonts_cache.txt");
            let force = forceRescan ? "true" : "false";

            let cmd = "CACHE=\"" + cacheFile + "\"; ";
            cmd += "if [ \"" + force + "\" = \"true\" ] || [ ! -f \"$CACHE\" ]; then ";
            cmd += "mkdir -p \"$(dirname \"$CACHE\")\"; ";
            cmd += "find ";
            if (sys !== "") cmd += "\"" + sys + "\" ";
            cmd += "\"" + usr + "\" -type f \\( -iname \"*.ttf\" -o -iname \"*.otf\" -o -iname \"*.ttc\" \\) -print0 2>/dev/null | sort -z | ";
            cmd += "xargs -0 -r fc-scan -f '%{family[0]}\\t%{style[0]}\\t%{file}\\n' 2>/dev/null | ";
            cmd += "awk -F'\\t' '{ fam=$1; stl=$2; f=$3; if (fam==\"\") { n=split(f,a,\"/\"); fam=a[n]; sub(/\\.[^.]*$/,\"\",fam) } if (stl!=\"\" && stl!=\"Regular\") print fam \" \" stl \"|\" f; else print fam \"|\" f }' ";
            cmd += "> \"$CACHE.tmp\" || true; mv \"$CACHE.tmp\" \"$CACHE\"; ";
            cmd += "fi; ";
            cmd += "cat \"$CACHE\" || true";

            return ["bash", "-c", cmd];
        }
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                fontFetcher.forceRescan = false;

                let lines = this.text.trim().split('\n');
                let newPaths = {};
                let names = [];
                let seen = new Set();

                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i].trim();
                    if (line === "") continue;

                    let idx = line.indexOf('|');
                    if (idx !== -1) {
                        let fName = line.substring(0, idx).trim();
                        if (fName.toLowerCase().indexOf("symbols nerd font") !== -1) continue;

                        let fPath = line.substring(idx + 1).trim();
                        let key = fName.toLowerCase();

                        newPaths[key] = fPath;

                        if (!seen.has(key)) {
                            seen.add(key);
                            names.push(fName);
                        }
                    }
                }

                root.availableFontPaths = newPaths;
                root.bundledNames = names;
                root.updateActiveFontLoader();
                if (staticFontLoader.status === FontLoader.Ready) {
                    let cur = root.fontFamily;
                    root.fontFamily = "";
                    root.fontFamily = cur;
                }
            }
        }
    }

    function scanFonts() {
        fontFetcher.running = false;
        fontFetcher.forceRescan = true;
        fontFetcher.running = true;
    }

    function reloadColors() {
        if (root._readInProgress) return;
        root._readInProgress = true;
        root.updateColors();
    }

    IpcHandler {
        target: "meander.theme"

        function reloadColors() {
            root.reloadColors();
        }
    }

    IpcHandler {
        target: "meander.fonts"
        function rescan() {
            root.scanFonts();
        }
    }

    Connections {
        target: Config
        function onSettingsLoaded() {
            root.updateColors();
        }
        function onRawSettingsChanged() {
            root.syncElementOpacity();
        }
    }

    Connections {
        target: typeof Matugen !== "undefined" ? Matugen : null
        function onGenerationFinished(success) {
            root._readInProgress = false;
            if (success) {
                themeWatcher.reload();
                matugenColorsWatcher.reload();
            }
        }
    }

    function applyMatugenColors(): bool {
        if (root.matugenColors) {
            root.applyColorObject(root.matugenColors);
            return true;
        }
        return false;
    }

    function faded(c) {
        return Qt.alpha(c, root.elementOpacity);
    }

    function syncElementOpacity() {
        const themeConfig = Config.getSetting("theme", {});
        const pct = themeConfig.elementOpacity !== undefined ? Number(themeConfig.elementOpacity) : 100;
        root.blurBackground = themeConfig.blurBackground !== undefined ? Boolean(themeConfig.blurBackground) : false;
        root.blurStyle = themeConfig.blurStyle === "liquid" ? "liquid" : "blur";
        root.elementOpacity = root.liquidGlass ? root.liquidGlassOpacity : (isNaN(pct) ? 1.0 : Math.max(0, Math.min(1.0, pct / 100.0)));
    }

    function updateColors() {
        let themeConfig = Config.getSetting("theme", {});

        if (themeConfig.fontFamily !== undefined) {
            root.fontFamily = themeConfig.fontFamily;
        }
        if (themeConfig.borderRadius !== undefined) {
            root.borderRadius = themeConfig.borderRadius;
        }
        root.syncElementOpacity();

        let customColors = themeConfig.colors || themeConfig.palette || (themeConfig.base !== undefined ? themeConfig : null);

        if (root.isOmarchyTheme()) {
            root._readInProgress = false;
            if (!root.applyOmarchyPalette()) omarchyColorsFile.reload();
        } else if (root.isMatugenTheme()) {
            root.applyMatugenColors();
            let wp = themeConfig.wallpaper || Config.getSetting("wallpaper", "");
            if (typeof Matugen !== "undefined" && typeof Matugen.generate === "function") {
                Matugen.generate(wp, themeConfig.mode, themeConfig.schemeType);
            }
            root._readInProgress = false;
        } else {
            root._readInProgress = false;
            if (customColors) {
                root.applyColorObject(customColors);
                if (typeof Matugen !== "undefined" && typeof Matugen.generateFromStatic === "function") {
                    Matugen.generateFromStatic(customColors, themeConfig.mode);
                }
            } else {
                themeWatcher.reload();
            }
        }
    }

    function applyColorObject(c) {
        if (!c) return;
        if (root.pureBlackOn()) {
            let flat = {};
            for (let k in c) {
                let v = c[k];
                flat[k] = (v && typeof v === "object") ? (v.hex || v.color || (v.default && v.default.hex) || "") : v;
            }
            c = Material.pureBlack(flat);
        }

        let resolveHex = function(val) {
            if (!val) return "";
            if (typeof val === "string") return val;
            if (typeof val === "object") {
                if (val.hex) return val.hex;
                if (val.color) return val.color;
                if (val.default && val.default.hex) return val.default.hex;
            }
            return val.toString();
        };

        let names = ["base", "mantle", "crust", "surface0", "surface1", "surface2",
                     "overlay0", "overlay1", "overlay2", "text", "subtext0", "subtext1",
                     "blue", "sapphire", "peach", "green", "red", "mauve", "pink",
                     "yellow", "maroon", "teal"];

        let queue = [];
        for (let i = 0; i < names.length; i++) {
            let hexColor = resolveHex(c[names[i]]);
            if (!hexColor) continue;
            let nextColor = Qt.color(hexColor);
            let slot = (names[i] === "text" || names[i] === "subtext0" || names[i] === "subtext1") ? "_" + names[i] : names[i];
            if (root[slot].toString() !== nextColor.toString()) {
                queue.push({ name: slot, value: nextColor });
            }
        }

        root._colorQueue = queue;
        if (queue.length > 0) {
            root._flushColorQueue();
            if (root._colorQueue.length > 0) colorStepTimer.restart();
        }
    }

    function _flushColorQueue() {
        let n = Math.min(root.colorsPerFrame, root._colorQueue.length);
        for (let i = 0; i < n; i++) {
            let item = root._colorQueue[i];
            root[item.name] = item.value;
        }
        root._colorQueue = root._colorQueue.slice(n);
    }

    FrameAnimation {
        id: colorStepTimer
        onTriggered: {
            root._flushColorQueue();
            if (root._colorQueue.length === 0) stop();
        }
    }

    FileView {
        id: matugenColorsWatcher
        path: root.matugenConfigPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let txt = text().trim();
            if (txt !== "") {
                try {
                    let c = JSON.parse(txt);
                    let target = c && c.colors ? c.colors : c;
                    if (target) {
                        root.matugenColors = target;
                        if (root.isMatugenTheme()) {
                            root.applyColorObject(target);
                        }
                    }
                } catch(e) {}
            }
        }
    }

    FileView {
        id: themeWatcher
        path: root.configPath.startsWith("~") ? (Quickshell.env("HOME") ?? "") + root.configPath.slice(1) : root.configPath
        watchChanges: false

        onLoaded: {
            root._readInProgress = false;
            let txt = text().trim();
            if (txt !== "") {
                try {
                    let c = JSON.parse(txt);
                    let target = c && c.colors ? c.colors : c;
                    if (target) {
                        if (root.isMatugenTheme()) {
                            root.matugenColors = target;
                        }
                        root.applyColorObject(target);
                    }
                } catch(e) {}
            }
        }
    }

    Component.onCompleted: {
        root._readInProgress = true;
        root.updateColors();
        root.updateActiveFontLoader();
    }
}
