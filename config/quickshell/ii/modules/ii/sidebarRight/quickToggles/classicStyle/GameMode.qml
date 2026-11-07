import qs.modules.common.models.quickToggles
import qs.modules.common.widgets
import qs.services

QuickToggleButton {
    id: root

    // Same model as the Android-style panel and the waffle action center, so
    // every Game Mode button shares one state and one apply/restore path.
    property GameModeToggle model: GameModeToggle {}

    buttonIcon: "gamepad"
    toggled: root.model.toggled
    onClicked: root.model.mainAction()

    StyledToolTip {
        text: Translation.tr("Game mode")
    }
}
