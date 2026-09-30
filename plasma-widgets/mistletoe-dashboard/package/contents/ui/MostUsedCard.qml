/*
    Most used card: the five apps you start most often, ranked.
*/
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.private.kicker as Kicker

ColumnLayout {
    id: card

    required property var dash

    spacing: 2

    // Rows that fit under the heading (each row is 38px + 2px spacing).
    readonly property int rowsFit: Math.max(1, Math.min(12, Math.floor((height - 32) / 40)))

    Kicker.RecentUsageModel {
        id: mostUsed
        ordering: 1 // Popular
        shownItems: Kicker.RecentUsageModel.OnlyApps
    }

    SectionLabel {
        Layout.fillWidth: true
        Layout.bottomMargin: 10
        text: i18n("Most used")
        gold: card.dash.gold
        bone: card.dash.bone
    }
    Repeater {
        model: mostUsed
        delegate: AppRow {
            required property int index
            required property var model
            Layout.fillWidth: true
            visible: index < card.rowsFit
            rank: index + 1
            iconSource: model.decoration
            title: model.display
            ink: card.dash.ink
            bone: card.dash.bone
            gold: card.dash.gold
            onClicked: mostUsed.trigger(index, "", null)
        }
    }
    Item {
        Layout.fillHeight: true
    }
}
