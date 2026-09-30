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
            visible: index < 5
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
