/*
    Mistletoe Launcher: a corner button that opens a fullscreen, transparent
    overlay where applications bloom radially out of the corner.

    Apps, favorites and search come from Plasma's kicker models (the same
    ones Kickoff and the Application Dashboard use).
*/
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.kicker as Kicker

PlasmoidItem {
    id: kicker

    property Item button: null
    // Drill-down stack of models inside a category (for nested folders).
    property var stack: []
    property int railIndex: 0
    property var rail: []

    readonly property var favorites: rootModel.favoritesModel
    // Fetched imperatively: modelForRow() builds a new model on every call,
    // so calling it from a binding would churn models and restart the fan.
    property var baseModel: null
    readonly property var currentModel: fan.query.length > 0
        ? (runnerModel.count > 0 ? runnerModel.modelForRow(0) : null)
        : (stack.length > 0 ? stack[stack.length - 1] : baseModel)

    // The button is the *full* representation, shown inline: with a null
    // full representation Plasma never instantiates a compact one. This
    // is the same arrangement Plasma's Application Dashboard uses.
    preferredRepresentation: fullRepresentation
    compactRepresentation: null
    fullRepresentation: CompactButton {
        id: cornerButton
        open: overlay.visible
        onClicked: kicker.toggle()
        Component.onCompleted: kicker.button = cornerButton
    }
    activationTogglesExpanded: false

    // Rail slot 0 is Favorites; the rest map onto rootModel rows.
    function railRow(i) {
        return rail[i] ? rail[i].row : -1;
    }

    function rebuildRail() {
        const r = [{ name: i18n("Favorites"), icon: "bookmarks", row: -1 }];
        for (let i = 0; i < rootModel.count; ++i) {
            const idx = rootModel.index(i, 0);
            const name = rootModel.data(idx, Qt.DisplayRole);
            if (!name) {
                continue; // separator rows
            }
            r.push({
                name: name,
                icon: rootModel.data(idx, Qt.DecorationRole),
                row: i
            });
        }
        rail = r;
    }

    function selectRail(i) {
        fan.keyTarget.text = "";
        stack = [];
        railIndex = i;
        baseModel = i === 0 ? favorites : rootModel.modelForRow(railRow(i));
    }

    function toggle() {
        if (overlay.visible) {
            fan.close();
            return;
        }
        selectRail(0);
        overlay.open();
        Qt.callLater(openFan);
    }

    function openFan() {
        // The fan grows out of the button, wherever it sits on screen.
        if (button) {
            fan.origin = button.centerOnScreen();
        }
        fan.open();
    }

    function launch(index, hasChildren) {
        const m = currentModel;
        if (!m) {
            return;
        }
        if (hasChildren) {
            stack = stack.concat([m.modelForRow(index)]);
            return;
        }
        m.trigger(index, "", null);
        fan.close();
    }

    function toggleFavorite(id) {
        if (!id) {
            return;
        }
        if (favorites.isFavorite(id)) {
            favorites.removeFavorite(id);
        } else {
            favorites.addFavorite(id);
        }
    }

    Connections {
        target: Plasmoid
        function onActivated() {
            kicker.toggle();
        }
    }

    Kicker.RootModel {
        id: rootModel

        autoPopulate: false
        appletInterface: kicker
        appNameFormat: 0
        flat: true
        sorted: true
        showSeparators: false
        showTopLevelItems: false
        showAllApps: true
        showAllAppsCategorized: false
        showRecentApps: false
        showRecentDocs: false
        showRecentFolders: false
        showPowerSession: true
        showFavoritesPlaceholder: false
        showRootSeparator: false

        // A refresh replaces the child models, so fetch the current one again.
        onRefreshed: {
            kicker.rebuildRail();
            kicker.selectRail(Math.min(kicker.railIndex, kicker.rail.length - 1));
        }

        Component.onCompleted: {
            favoritesModel.initForClient("org.mistletoe.launcher.favorites.instance-" + Plasmoid.id);
            if (!Plasmoid.configuration.favoritesPortedToKAstats) {
                if (favoritesModel.count < 1) {
                    favoritesModel.portOldFavorites(Plasmoid.configuration.favoriteApps);
                }
                Plasmoid.configuration.favoritesPortedToKAstats = true;
            }
            refresh();
        }
    }

    Kicker.RunnerModel {
        id: runnerModel

        appletInterface: kicker
        favoritesModel: rootModel.favoritesModel
        mergeResults: true
        runners: ["krunner_services", "krunner_systemsettings", "krunner_sessions", "calculator"]
        query: fan.query
    }

    Overlay {
        id: overlay

        anchorItem: kicker.button
        focusItem: fan.keyTarget
        onDeactivated: fan.close()

        RadialFan {
            id: fan

            anchors.fill: parent
            model: kicker.currentModel
            rail: kicker.rail
            railIndex: kicker.railIndex
            title: kicker.rail[kicker.railIndex] ? kicker.rail[kicker.railIndex].name : ""

            onItemActivated: (index, hasChildren) => kicker.launch(index, hasChildren)
            onItemAltActivated: (index, favoriteId) => kicker.toggleFavorite(favoriteId)
            onRailActivated: (index) => kicker.selectRail(index)
            onBackRequested: {
                if (kicker.stack.length > 0) {
                    kicker.stack = kicker.stack.slice(0, -1);
                }
            }
            onEscapePressed: {
                if (fan.query.length > 0) {
                    fan.keyTarget.text = "";
                } else if (kicker.stack.length > 0) {
                    kicker.stack = kicker.stack.slice(0, -1);
                } else {
                    fan.close();
                }
            }
            onClosed: overlay.hide()
        }
    }
}
