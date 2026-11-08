pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

Item {
    id: root

    property var locationData: (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.general && Config.rawSettings.general.location) ? Config.rawSettings.general.location : ({})
    property bool isDetecting: false

    readonly property string ip: locationData.ip || ""
    readonly property real latitude: locationData.latitude !== undefined ? Number(locationData.latitude) : 0.0
    readonly property real longitude: locationData.longitude !== undefined ? Number(locationData.longitude) : 0.0
    readonly property string city: locationData.city || "Unknown"
    readonly property string region: locationData.region || "Unknown"
    readonly property string regionCode: locationData.region_code || ""
    readonly property string countryName: locationData.country_name || locationData.country || "Unknown"
    readonly property string countryCode: locationData.country_code || ""
    readonly property string postal: locationData.postal || locationData.zip || ""
    readonly property string timezone: locationData.timezone || "UTC"
    readonly property string utcOffset: locationData.utc_offset || ""
    readonly property string currency: locationData.currency || ""
    readonly property string languages: locationData.languages || ""
    readonly property string asn: locationData.asn || ""
    readonly property string org: locationData.org || ""
    readonly property string source: locationData.source || "unknown"
    readonly property var updatedAt: locationData.updated_at !== undefined ? locationData.updated_at : 0

    readonly property var entries: {
        let arr = [];
        if (root.locationData) {
            for (let key in root.locationData) {
                let val = root.locationData[key];
                if (key === "updated_at" && typeof val === "number") {
                    val = new Date(val * 1000).toLocaleString();
                }
                arr.push({ label: key, value: String(val) });
            }
        }
        return arr;
    }

    signal locationUpdated()

    Connections {
        target: typeof Config !== "undefined" ? Config : null
        function onSettingsLoaded() {
            let gs = Config.getSetting("general", {});
            root.locationData = gs && gs.location ? gs.location : {};
            root.isDetecting = false;
            root.locationUpdated();
        }
    }

    onLocationDataChanged: {
        root.locationUpdated();
    }

    function get(key, fallbackValue) {
        if (root.locationData && root.locationData.hasOwnProperty(key)) {
            return root.locationData[key];
        }
        return fallbackValue !== undefined ? fallbackValue : "";
    }

    function detectAuto() {
        if (!Caching.meanderDir) return;
        root.isDetecting = true;
        autoProcess.running = false;
        autoProcess.running = true;
    }

    function setManual(lat, lon) {
        if (!Caching.meanderDir) return;
        root.isDetecting = true;
        manualProcess.lat = lat.toString();
        manualProcess.lon = lon.toString();
        manualProcess.running = false;
        manualProcess.running = true;
    }

    Process {
        id: autoProcess
        command: ["bash", "-c", Caching.meanderDir + "/scripts/location.sh --auto"]
        onExited: {
            root.isDetecting = false;
        }
    }

    Process {
        id: manualProcess
        property string lat: ""
        property string lon: ""
        command: ["bash", "-c", Caching.meanderDir + "/scripts/location_manual.sh '" + lat + "' '" + lon + "'"]
        onExited: {
            root.isDetecting = false;
        }
    }

    // Meander: the location is Omarchy's (omarchy-weather-location's
    // weather.json, see scripts/location.sh). Follow edits to it live, as
    // Omarchy's weather panel does; location.sh is a no-op while the cached
    // general.location already matches.
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/weather.json"
        watchChanges: true
        printErrors: false
        onFileChanged: omarchySync.restart()
        onLoaded: omarchySync.restart()
        onLoadFailed: omarchySync.restart()
    }

    Timer {
        id: omarchySync
        interval: 1500
        onTriggered: {
            if (!Caching.meanderDir || autoProcess.running || manualProcess.running) return;
            syncProcess.running = false;
            syncProcess.running = true;
        }
    }

    Process {
        id: syncProcess
        command: ["bash", "-c", Caching.meanderDir + "/scripts/location.sh >/dev/null"]
    }

    Component.onCompleted: {
        if (typeof Config !== "undefined" && Config.dataReady) {
            let gs = Config.getSetting("general", {});
            if (gs && gs.location) {
                root.locationData = gs.location;
            }
        }
    }
}
