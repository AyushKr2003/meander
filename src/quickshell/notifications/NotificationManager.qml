pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Io
import "../"

Item {
    id: root

    property var liveNotifs: ({})
    property int popupCounter: 0
    property bool isStartup: true
    property bool sysPanelOpen: false
    property real lastNotifTime: 0
    property bool _isBatchUpdating: false

    ListModel { id: historyModel }
    ListModel { id: popupsModel }
    ListModel { id: groupedHistoryModel }

    property alias globalNotificationHistory: historyModel
    property alias activePopupsModel: popupsModel
    property alias groupedHistory: groupedHistoryModel

    property var _resolveCache: ({})
    property var manualAliasTable: ({
        "telegram": "org.telegram.desktop",
        "discord": "discord",
        "slack": "slack",
        "spotify": "spotify"
    })

    signal popupAdded(int uid, var notif)

    // ---------------------------------------------------------- history
    // Upstream's history held only notifications still open: an entry left
    // as its notification closed (the app withdrew it, it expired, its popup
    // was closed) and with the shell. Omarchy's daemon keeps closed ones
    // until they are cleared, and that history is what Omacale's sidebar
    // shows, so Meander keeps them too, on disk, with Omarchy's retention
    // (its Store.js: newest first, 100 rows, 24 hours). Notifications
    // Omarchy's daemon recorded before Meander took over are read in once
    // from its history.json (rc/edge/dev layout; read only).
    readonly property int historyLimit: 100
    readonly property real historyRetentionMs: 24 * 3600 * 1000
    readonly property string historyPath: Caching.getStateDir("notifications") + "/history.json"
    readonly property string omarchyHistoryPath: Caching.home + "/.local/state/omarchy/notifications/history.json"
    property bool historyLoaded: false
    // closed_ts (seconds) of the newest Omarchy row already read in, so a
    // row the user dismissed here doesn't come back on the next start.
    property real omarchyImportedUntil: 0
    property var _storedRows: []

    function _storable(nData) {
        let image = String(nData.image || "");
        // image:// URLs belong to the live notification and die with it.
        if (image.indexOf("image://") === 0) image = "";
        return {
            "appName": String(nData.appName || "System"),
            "summary": String(nData.summary || ""),
            "body": String(nData.body || ""),
            "iconPath": String(nData.iconPath || ""),
            "image": image,
            // A qsimage picture dies with the notification; a file path stays.
            "senderImage": /^image:\/\/qsimage\//.test(String(nData.senderImage || "")) ? "" : String(nData.senderImage || ""),
            "desktopEntry": String(nData.desktopEntry || ""),
            "glyph": String(nData.glyph || ""),
            "timestamp": Number(nData.timestamp) || Date.now(),
            "urgency": Number(nData.urgency) || 0,
            "read": Boolean(nData.read)
        };
    }

    function _restored(row) {
        root.popupCounter++;
        let image = String(row.image || "");
        return {
            "appName": String(row.appName || "System"),
            "summary": String(row.summary || ""),
            "body": String(row.body || ""),
            "iconPath": String(row.iconPath || ""),
            "image": image,
            "imagePath": image,
            "senderImage": String(row.senderImage || ""),
            "desktopEntry": String(row.desktopEntry || ""),
            "glyph": String(row.glyph || ""),
            // Its actions went with the sender's notification.
            "actionsJson": "[]",
            "hasActions": false,
            "uid": root.popupCounter,
            "timestamp": Number(row.timestamp) || 0,
            "urgency": Number(row.urgency) || 0,
            "read": Boolean(row.read)
        };
    }

    // Drops what Omarchy's retention would: past the row limit or the window.
    function pruneHistory() {
        let cutoff = Date.now() - root.historyRetentionMs;
        let changed = false;
        root._isBatchUpdating = true;
        for (let i = historyModel.count - 1; i >= 0; i--) {
            let nData = historyModel.get(i);
            if (i >= root.historyLimit || !nData || (Number(nData.timestamp) || 0) < cutoff) {
                if (nData) delete root.liveNotifs[nData.uid];
                historyModel.remove(i, 1);
                changed = true;
            }
        }
        root._isBatchUpdating = false;
        if (changed) rebuildGroups();
    }

    function _finishHistoryLoad(omarchyText) {
        let rows = root._storedRows.slice();
        let until = root.omarchyImportedUntil;
        let list = [];
        try { list = JSON.parse(omarchyText || "[]"); } catch (e) { list = []; }
        if (Array.isArray(list)) {
            for (let i = 0; i < list.length; i++) {
                let r = list[i];
                let closed = r ? Number(r.closed_ts) || 0 : 0;
                if (!r || typeof r !== "object" || closed <= root.omarchyImportedUntil) continue;
                until = Math.max(until, closed);
                rows.push({
                    "appName": String(r.app || "System"),
                    "summary": String(r.summary || ""),
                    "body": String(r.body || ""),
                    "iconPath": String(r.appIcon || ""),
                    "image": "",
                    "senderImage": "",
                    "desktopEntry": "",
                    "glyph": String(r.glyph || ""),
                    "timestamp": Math.round((Number(r.ts) || closed) * 1000),
                    "urgency": Number(r.urgency) || 0,
                    "read": true
                });
            }
        }
        root.omarchyImportedUntil = until;
        rows.sort((a, b) => (Number(b.timestamp) || 0) - (Number(a.timestamp) || 0));

        // Anything that arrived while the files were read is newer: it stays on top.
        root._isBatchUpdating = true;
        for (let i = 0; i < rows.length && historyModel.count < root.historyLimit; i++)
            historyModel.append(_restored(rows[i]));
        root._isBatchUpdating = false;
        root._storedRows = [];
        root.historyLoaded = true;
        pruneHistory();
        rebuildGroups();
        saveTimer.restart();
    }

    function saveHistory() {
        if (!root.historyLoaded) return;
        let entries = [];
        for (let i = 0; i < historyModel.count && entries.length < root.historyLimit; i++) {
            let nData = historyModel.get(i);
            if (nData) entries.push(_storable(nData));
        }
        historyFile.setText(JSON.stringify({
            "version": 1,
            "omarchyImportedUntil": root.omarchyImportedUntil,
            "entries": entries
        }));
    }

    FileView {
        id: historyFile
        path: root.historyPath
        atomicWrites: true
        printErrors: false
        onLoaded: {
            if (root.historyLoaded) return;
            try {
                let d = JSON.parse(text());
                root._storedRows = Array.isArray(d.entries) ? d.entries.filter(r => r && typeof r === "object") : [];
                root.omarchyImportedUntil = Number(d.omarchyImportedUntil) || 0;
            } catch (e) {
                root._storedRows = [];
            }
            omarchyHistoryFile.path = root.omarchyHistoryPath;
        }
        onLoadFailed: {
            if (root.historyLoaded) return;
            omarchyHistoryFile.path = root.omarchyHistoryPath;
        }
    }

    FileView {
        id: omarchyHistoryFile
        path: ""
        printErrors: false
        onLoaded: if (!root.historyLoaded) root._finishHistoryLoad(text())
        onLoadFailed: if (!root.historyLoaded) root._finishHistoryLoad("[]")
    }

    Timer {
        id: saveTimer
        interval: 400
        onTriggered: root.saveHistory()
    }

    Timer {
        interval: 10 * 60 * 1000
        running: root.historyLoaded
        repeat: true
        onTriggered: root.pruneHistory()
    }

    onSysPanelOpenChanged: {
        if (sysPanelOpen) {
            popupsModel.clear();
            _resolveCache = {};
        }
    }

    Timer {
        id: startupGraceTimer
        interval: 500
        running: true
        onTriggered: root.isStartup = false
    }

    function resolveApp(n) {
        if (!n) return { groupKey: "system", displayName: "System", icon: "", desktopEntry: null };

        let rawAppName = n.appName || "";
        let appName = rawAppName.toLowerCase().trim();
        appName = appName.replace(/\s*(canary|beta|nightly|-git|git|dev|development)\s*$/g, "");

        let desktopEntry = (n.desktopEntry || "").trim();
        let key = (desktopEntry + "|" + appName);
        if (_resolveCache[key] !== undefined) return _resolveCache[key];

        let entry = null;
        if (desktopEntry) {
            entry = DesktopEntries.byId(desktopEntry);
        }
        if (!entry && appName) {
            let alias = manualAliasTable[appName];
            if (alias) {
                entry = DesktopEntries.byId(alias);
            } else {
                entry = DesktopEntries.heuristicLookup(rawAppName);
            }
        }

        let resolved = {
            groupKey: entry ? entry.id : (appName || "system"),
            displayName: entry ? entry.name : (rawAppName || "System"),
            icon: n.appIcon || (entry ? entry.icon : ""),
            desktopEntry: entry
        };
        _resolveCache[key] = resolved;
        return resolved;
    }

    function markGroupRead(groupKey) {
        let changed = false;
        for (let i = 0; i < historyModel.count; i++) {
            let nData = historyModel.get(i);
            if (!nData) continue;
            let resolved = resolveApp(nData);
            let gKey = resolved.groupKey;
            if (nData.urgency === 2) {
                gKey += "_crit_" + nData.uid;
            }
            if (gKey === groupKey && !nData.read) {
                historyModel.setProperty(i, "read", true);
                changed = true;
            }
        }
        if (changed) rebuildGroups();
    }

    function markAsRead(uid) {
        let changed = false;
        for (let i = 0; i < historyModel.count; i++) {
            let nData = historyModel.get(i);
            if (nData && nData.uid === uid && !nData.read) {
                historyModel.setProperty(i, "read", true);
                changed = true;
                break;
            }
        }
        if (changed) rebuildGroups();
    }

    function rebuildGroups() {
        if (root.historyLoaded) saveTimer.restart();
        let groupedMap = {};
        let newOrder = [];

        for (let i = 0; i < historyModel.count; i++) {
            let nData = historyModel.get(i);
            if (!nData) continue;
            let n = root.liveNotifs[nData.uid] || nData.notif;
            let resolved = resolveApp(n || nData);
            let gKey = resolved.groupKey;

            if (nData.urgency === 2) {
                gKey += "_crit_" + nData.uid;
            }

            if (!groupedMap[gKey]) {
                groupedMap[gKey] = {
                    groupKey: gKey,
                    displayName: resolved.displayName,
                    icon: resolved.icon,
                    members: [],
                    count: 0,
                    unreadCount: 0,
                    latestSummary: nData.summary,
                    latestBody: nData.body,
                    latestTimestamp: (n && n.timestamp) ? n.timestamp : (nData.timestamp || Date.now())
                };
                newOrder.push(gKey);
            }

            let ts = (n && n.timestamp) ? n.timestamp : (nData.timestamp || Date.now());
            if (ts >= groupedMap[gKey].latestTimestamp) {
                groupedMap[gKey].latestTimestamp = ts;
                groupedMap[gKey].latestSummary = nData.summary;
                groupedMap[gKey].latestBody = nData.body;
            }

            groupedMap[gKey].members.push({
                "appName": nData.appName,
                "summary": nData.summary,
                "body": nData.body,
                "iconPath": nData.iconPath,
                "image": nData.image,
                "imagePath": nData.imagePath,
                "senderImage": nData.senderImage,
                "desktopEntry": nData.desktopEntry,
                "glyph": nData.glyph,
                "actionsJson": nData.actionsJson,
                "hasActions": nData.hasActions,
                "uid": nData.uid,
                "timestamp": ts,
                "urgency": nData.urgency,
                "read": nData.read
            });
            groupedMap[gKey].count = groupedMap[gKey].members.length;
            if (!nData.read) {
                groupedMap[gKey].unreadCount++;
            }
        }

        for (let i = groupedHistoryModel.count - 1; i >= 0; i--) {
            let item = groupedHistoryModel.get(i);
            if (!item || !groupedMap[item.groupKey]) {
                groupedHistoryModel.remove(i, 1);
            }
        }

        for (let i = 0; i < newOrder.length; i++) {
            let gKey = newOrder[i];
            let gData = groupedMap[gKey];
            let itemsJsonStr = JSON.stringify(gData.members);

            let existingIndex = -1;
            for (let j = 0; j < groupedHistoryModel.count; j++) {
                let item = groupedHistoryModel.get(j);
                if (item && item.groupKey === gKey) {
                    existingIndex = j;
                    break;
                }
            }

            let modelEntry = {
                "groupKey": gKey,
                "displayName": gData.displayName,
                "icon": gData.icon,
                "count": gData.count,
                "unreadCount": gData.unreadCount,
                "latestSummary": gData.latestSummary,
                "latestBody": gData.latestBody,
                "latestTimestamp": gData.latestTimestamp,
                "itemsJson": itemsJsonStr
            };

            if (existingIndex === -1) {
                groupedHistoryModel.insert(i, modelEntry);
            } else {
                if (existingIndex !== i && existingIndex < groupedHistoryModel.count && i < groupedHistoryModel.count) {
                    groupedHistoryModel.move(existingIndex, i, 1);
                }
                let item = groupedHistoryModel.get(i);
                if (item) {
                    if (item.displayName !== modelEntry.displayName) item.displayName = modelEntry.displayName;
                    if (item.icon !== modelEntry.icon) item.icon = modelEntry.icon;
                    if (item.count !== modelEntry.count) item.count = modelEntry.count;
                    if (item.unreadCount !== modelEntry.unreadCount) item.unreadCount = modelEntry.unreadCount;
                    if (item.latestSummary !== modelEntry.latestSummary) item.latestSummary = modelEntry.latestSummary;
                    if (item.latestBody !== modelEntry.latestBody) item.latestBody = modelEntry.latestBody;
                    if (item.latestTimestamp !== modelEntry.latestTimestamp) item.latestTimestamp = modelEntry.latestTimestamp;
                    if (item.itemsJson !== modelEntry.itemsJson) item.itemsJson = modelEntry.itemsJson;
                }
            }
        }
    }

    Connections {
        target: historyModel
        function onCountChanged() {
            if (!root._isBatchUpdating) {
                root.rebuildGroups();
            }
        }
    }

    function clearNotifications(): void {
        root._isBatchUpdating = true;
        let live = root.liveNotifs;
        root.liveNotifs = {};
        for (let key in live) {
            let n = live[key];
            if (n) {
                if (typeof n.dismiss === "function") {
                    n.dismiss();
                } else if (typeof n.close === "function") {
                    n.close();
                }
            }
        }
        historyModel.clear();
        popupsModel.clear();
        groupedHistoryModel.clear();
        root._isBatchUpdating = false;
        if (root.historyLoaded) saveTimer.restart();
    }

    // Omarchy's dismissOne/dismissAll: the popups close, their notifications
    // go on in the history (as Omarchy's toasts do), unlike clearNotifications.
    function dismissPopups(newestOnly) {
        let uids = [];
        for (let i = 0; i < popupsModel.count; i++) {
            let p = popupsModel.get(i);
            if (!p) continue;
            let list = [p.uid];
            try { let u = JSON.parse(p.uidsJson || "[]"); if (Array.isArray(u)) list = list.concat(u); } catch (e) {}
            uids = uids.concat(list);
            if (newestOnly) break;
        }
        if (uids.length === 0) return false;
        for (let i = 0; i < uids.length; i++) {
            let n = root.liveNotifs[uids[i]];
            if (n && typeof n.dismiss === "function") n.dismiss();
            removePopup(uids[i]);
        }
        return true;
    }

    function dismissNotification(uid) {
        if (!historyModel || historyModel.count === 0) return;
        let n = root.liveNotifs[uid];
        delete root.liveNotifs[uid];

        if (n) {
            if (typeof n.dismiss === "function") n.dismiss();
            else if (typeof n.close === "function") n.close();
        }

        for (let i = 0; i < historyModel.count; i++) {
            let nData = historyModel.get(i);
            if (nData && nData.uid === uid) {
                historyModel.remove(i, 1);
                break;
            }
        }
    }

    function dismissGroup(groupKey) {
        if (!historyModel || historyModel.count === 0) return;
        root._isBatchUpdating = true;
        for (let i = historyModel.count - 1; i >= 0; i--) {
            let nData = historyModel.get(i);
            if (!nData) continue;
            let n = root.liveNotifs[nData.uid] || nData.notif;
            let resolved = resolveApp(n || nData);
            let gKey = resolved.groupKey;
            
            if (nData.urgency === 2) {
                gKey += "_crit_" + nData.uid;
            }

            if (gKey === groupKey) {
                delete root.liveNotifs[nData.uid];
                if (n) {
                    if (typeof n.dismiss === "function") n.dismiss();
                    else if (typeof n.close === "function") n.close();
                }
                if (i < historyModel.count) {
                    historyModel.remove(i, 1);
                }
            }
        }
        root._isBatchUpdating = false;
        rebuildGroups();
    }

    function removePopup(uid) {
        if (!popupsModel || popupsModel.count === 0) return;
        for (let i = popupsModel.count - 1; i >= 0; i--) {
            let p = popupsModel.get(i);
            if (!p) continue;
            let matches = (p.uid === uid || p.latestUid === uid);
            if (!matches && p.uidsJson) {
                try {
                    let uList = JSON.parse(p.uidsJson);
                    if (Array.isArray(uList) && uList.indexOf(uid) !== -1) {
                        matches = true;
                    }
                } catch (e) {}
            }
            if (matches) {
                if (i < popupsModel.count) {
                    popupsModel.remove(i, 1);
                }
                break;
            }
        }
    }

    // Only one notification daemon can own org.freedesktop.Notifications, and
    // the Omarchy shell has its own: Meander's starts once Omarchy's is off
    // (see OmarchyHost).
    LazyLoader {
        active: OmarchyHost.ownsNotifications

    NotificationServer {
        id: globalNotificationServer
        bodySupported: true
        actionsSupported: true
        imageSupported: true

        onNotification: (n) => {
            let now = Date.now();
            if (n.urgency !== 2 && now - root.lastNotifTime < 100) {
                return;
            }
            root.lastNotifTime = now;

            n.tracked = true;

            let extractedActions = [];
            if (n.actions) {
                for (let i = 0; i < n.actions.length; i++) {
                    extractedActions.push({
                        "id": n.actions[i].identifier || "",
                        "text": n.actions[i].text || n.actions[i].name || "Action"
                    });
                }
            }

            root.popupCounter++;
            let currentUid = root.popupCounter;
            root.liveNotifs[currentUid] = n;

            if (n.closed) {
                // Upstream removed the entry here; it stays in the history
                // now (see "history" above), only its actions are gone.
                n.closed.connect(() => {
                    if (root.liveNotifs[currentUid]) {
                        delete root.liveNotifs[currentUid];
                        for (let i = 0; i < historyModel.count; i++) {
                            let item = historyModel.get(i);
                            if (item && item.uid === currentUid) {
                                historyModel.setProperty(i, "actionsJson", "[]");
                                historyModel.setProperty(i, "hasActions", false);
                                break;
                            }
                        }
                        if (!root._isBatchUpdating) root.rebuildGroups();
                    }
                });
            }

            let hasAct = extractedActions.length > 0;
            let resolved = resolveApp(n);

            let summaryText = n.summary !== "" ? n.summary : "No Title";
            let bodyText = n.body !== "" ? n.body : "";
            let imageVal = (n.image ? n.image.toString() : "") || (n.imagePath ? n.imagePath.toString() : "") || (n.appIcon ? n.appIcon.toString() : "");

            // What the icon slot needs to choose as Omarchy does (NotifIcons):
            // the sender's raw image, its desktop-entry hint, the glyph hint.
            let senderImage = n.image ? String(n.image) : "";
            let desktopEntryHint = n.desktopEntry ? String(n.desktopEntry) : "";
            let glyphHint = "";
            try { glyphHint = n.hints && typeof n.hints["omarchy-glyph"] === "string" ? n.hints["omarchy-glyph"] : ""; } catch (e) {}

            let notifData = {
                "appName":     n.appName !== "" ? n.appName : "System",
                "summary":     summaryText,
                "body":        bodyText,
                "iconPath":    n.appIcon !== "" ? n.appIcon : "",
                "image":       imageVal,
                "imagePath":   imageVal,
                "senderImage": senderImage,
                "desktopEntry": desktopEntryHint,
                "glyph":       glyphHint,
                "actionsJson": JSON.stringify(extractedActions),
                "hasActions":  hasAct,
                "uid":         currentUid,
                // No "notif" here: the live object is in liveNotifs, and rows
                // restored from disk have none. Every row keeps the same roles,
                // since a QObject role added to a ListModel that already holds
                // rows crashes it (QQmlListModel::data).
                "timestamp":   now,
                "urgency":     n.urgency,
                "read":        false
            };

            historyModel.insert(0, notifData);
            if (historyModel.count > root.historyLimit) root.pruneHistory();

            if (!root.isStartup && !root.sysPanelOpen) {
                let newPopup = {
                    "uid":           currentUid,
                    "latestUid":     currentUid,
                    "uidsJson":      JSON.stringify([currentUid]),
                    "groupKey":      resolved.groupKey,
                    "appName":       resolved.displayName,
                    "displayName":   resolved.displayName,
                    "icon":          resolved.icon || notifData.iconPath,
                    "image":         imageVal,
                    "imagePath":     imageVal,
                    "senderImage":   senderImage,
                    "desktopEntry":  desktopEntryHint,
                    "glyph":         glyphHint,
                    "summary":       summaryText,
                    "body":          bodyText,
                    "combinedBody":  bodyText,
                    "messagesJson":  JSON.stringify(bodyText !== "" ? [bodyText] : []),
                    "messagesCount": 1,
                    "iconPath":      notifData.iconPath,
                    "actionsJson":   JSON.stringify(extractedActions),
                    "hasActions":    hasAct,
                    "notif":         n,
                    "urgency":       n.urgency,
                    "timestamp":     now
                };
                popupsModel.insert(0, newPopup);
                root.popupAdded(currentUid, n);
            }
        }
    }
    }
}
