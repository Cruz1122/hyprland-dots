pragma ComponentBehavior: Bound
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root
    property real buttonSize: 48
    // Window y just above the revealed dock body, where popups attach.
    property real popupBaseY: 0
    property real maxWindowPreviewHeight: 200
    property real maxWindowPreviewWidth: 300
    property real windowControlsHeight: 30
    readonly property real nameRowHeight: 24

    property Item lastHoveredButton: null
    property bool buttonHovered: false
    // Entry whose context menu is open, or null.
    property Item menuButton: null
    readonly property bool requestDockShow: previewPopup.show || menuButton !== null

    implicitWidth: listView.implicitWidth
    implicitHeight: buttonSize

    function popupCenterXForButton(button) {
        if (!button || !root.QsWindow)
            return 0;
        return root.QsWindow.mapFromItem(button, button.width / 2, 0).x;
    }

    function openMenu(button) {
        root.buttonHovered = false;
        root.menuButton = button;
        // Only once the menu is showing: a grab that activates in the same
        // binding pass as the popup's visibility leaves the popup out of it,
        // and every click on the menu then counts as a click outside.
        Qt.callLater(() => menuGrab.active = root.menuButton !== null);
    }
    function closeMenu() {
        menuGrab.active = false;
        root.menuButton = null;
    }

    StyledListView {
        id: listView
        spacing: 2
        orientation: ListView.Horizontal
        interactive: false
        anchors {
            top: parent.top
            bottom: parent.bottom
        }
        implicitWidth: contentWidth

        Behavior on implicitWidth {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        model: ScriptModel {
            objectProp: "appId"
            values: TaskbarApps.dockApps
        }
        delegate: DockAppButton {
            required property var modelData
            entry: modelData
            appListRoot: root
            size: root.buttonSize
        }
    }

    DockMenu {
        id: dockMenu
        anchor.window: root.QsWindow.window
        button: root.menuButton
        anchorX: root.popupCenterXForButton(root.menuButton)
        anchorY: root.popupBaseY
        onDismissed: root.closeMenu()
    }
    HyprlandFocusGrab { // Clicking anywhere else closes the menu
        id: menuGrab
        windows: [root.QsWindow?.window, dockMenu]
        onCleared: root.closeMenu()
    }

    PopupWindow {
        id: previewPopup
        property var appEntry: root.lastHoveredButton?.entry

        property bool shouldShow: (popupMouseArea.containsMouse || root.buttonHovered) && root.menuButton === null && (appEntry?.toplevels?.length ?? 0) > 0

        property bool show: false
        property real cachedCenterX: 0

        Connections {
            target: root
            function onLastHoveredButtonChanged() {
                if (root.lastHoveredButton && root.QsWindow)
                    previewPopup.cachedCenterX = root.popupCenterXForButton(root.lastHoveredButton);
            }
            function onButtonHoveredChanged() {
                if (root.buttonHovered && root.lastHoveredButton && root.QsWindow)
                    previewPopup.cachedCenterX = root.popupCenterXForButton(root.lastHoveredButton);
                updateTimer.restart();
            }
        }

        onShouldShowChanged: {
            updateTimer.restart();
        }

        Timer {
            id: updateTimer
            interval: 100
            onTriggered: {
                previewPopup.show = previewPopup.shouldShow;
            }
        }

        anchor {
            window: root.QsWindow.window
            // Explicit size: an empty rect would stand for the whole window.
            rect.x: 0
            rect.y: root.popupBaseY
            rect.width: root.QsWindow.window?.width ?? 1
            rect.height: 1
            adjustment: PopupAdjustment.None
            gravity: Edges.Top | Edges.Right
            edges: Edges.Top | Edges.Left
        }

        visible: popupBackground.opacity > 0
        color: "transparent"
        implicitWidth: root.QsWindow.window?.width ?? 1
        implicitHeight: popupMouseArea.implicitHeight + root.windowControlsHeight + Appearance.sizes.elevationMargin * 2

        MouseArea {
            id: popupMouseArea
            anchors.bottom: parent.bottom
            implicitWidth: popupBackground.implicitWidth + Appearance.sizes.elevationMargin * 2
            implicitHeight: root.maxWindowPreviewHeight + root.windowControlsHeight + root.nameRowHeight + Appearance.sizes.elevationMargin * 2
            hoverEnabled: true
            x: previewPopup.cachedCenterX - width / 2

            StyledRectangularShadow {
                target: popupBackground
                opacity: previewPopup.show ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            Rectangle {
                id: popupBackground
                property real padding: 5
                opacity: previewPopup.show ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                clip: true
                // The dock's own surface and corner radius.
                color: Appearance.colors.colLayer0
                radius: Appearance.rounding.large
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Appearance.sizes.elevationMargin
                anchors.horizontalCenter: parent.horizontalCenter
                implicitHeight: previewColumn.implicitHeight + padding * 2
                implicitWidth: previewColumn.implicitWidth + padding * 2
                Behavior on implicitWidth {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on implicitHeight {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                ColumnLayout {
                    id: previewColumn
                    anchors.centerIn: parent
                    spacing: 2

                    StyledText {
                        Layout.leftMargin: 6
                        Layout.topMargin: 2
                        Layout.maximumWidth: previewRowLayout.implicitWidth
                        text: root.lastHoveredButton?.displayName ?? ""
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer0
                    }

                    RowLayout {
                        id: previewRowLayout
                        Repeater {
                            model: ScriptModel {
                                values: previewPopup.appEntry?.toplevels ?? []
                            }
                            RippleButton {
                                id: windowButton
                                Layout.fillHeight: true
                                required property var modelData
                                padding: 0
                                middleClickAction: () => {
                                    windowButton.modelData?.close();
                                }
                                onClicked: {
                                    root.lastHoveredButton?.focusWindow(windowButton.modelData);
                                }
                                contentItem: ColumnLayout {
                                    implicitWidth: screencopyView.implicitWidth
                                    implicitHeight: screencopyView.implicitHeight

                                    ButtonGroup {
                                        contentWidth: parent.width - anchors.margins * 2
                                        StyledText {
                                            Layout.margins: 5
                                            Layout.fillWidth: true
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            text: windowButton.modelData?.title
                                            elide: Text.ElideRight
                                            color: Appearance.colors.colOnLayer0
                                        }
                                        GroupButton {
                                            id: closeButton
                                            colBackground: ColorUtils.transparentize(Appearance.colors.colLayer0)
                                            baseWidth: root.windowControlsHeight
                                            baseHeight: root.windowControlsHeight
                                            buttonRadius: Appearance.rounding.full
                                            contentItem: MaterialSymbol {
                                                anchors.centerIn: parent
                                                horizontalAlignment: Text.AlignHCenter
                                                text: "close"
                                                iconSize: Appearance.font.pixelSize.normal
                                                color: Appearance.colors.colOnLayer0
                                            }
                                            onClicked: {
                                                windowButton.modelData?.close();
                                            }
                                        }
                                    }
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        implicitHeight: screencopyView.height
                                        implicitWidth: screencopyView.width
                                        ScreencopyView {
                                            id: screencopyView
                                            anchors.centerIn: parent
                                            captureSource: windowButton.modelData
                                            live: true
                                            paintCursor: true
                                            constraintSize: Qt.size(root.maxWindowPreviewWidth, root.maxWindowPreviewHeight)
                                            layer.enabled: true
                                            layer.effect: OpacityMask {
                                                maskSource: Rectangle {
                                                    width: screencopyView.width
                                                    height: screencopyView.height
                                                    radius: Appearance.rounding.small
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
