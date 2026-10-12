import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.settings.components

Item {
    id: root

    property var pages: []
    property int currentIndex: 0
    property bool ready: Config.ready

    Loader {
        id: pageLoader
        anchors.fill: parent
        active: root.ready && root.pages && root.pages.length > 0
        source: root.pages && root.pages.length > 0 ? Quickshell.shellPath(root.pages[root.currentIndex].component) : ""
        opacity: 1

        Connections {
            target: root
            function onCurrentIndexChanged() {
                pageSwitch.complete()
                pageSwitch.start()
            }
        }

        SequentialAnimation {
            id: pageSwitch

            NumberAnimation {
                target: pageLoader
                property: "opacity"
                from: 1
                to: 0
                duration: 100
                easing.type: Appearance.animation.elementMoveExit.type
                easing.bezierCurve: Appearance.animationCurves.emphasizedFirstHalf
            }

            ParallelAnimation {
                PropertyAction {
                    target: pageLoader
                    property: "source"
                    value: root.pages && root.pages.length > 0 ? Quickshell.shellPath(root.pages[root.currentIndex].component) : ""
                }
                PropertyAction {
                    target: pageLoader
                    property: "anchors.topMargin"
                    value: 20
                }
            }

            ParallelAnimation {
                NumberAnimation {
                    target: pageLoader
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: 200
                    easing.type: Appearance.animation.elementMoveEnter.type
                    easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                }
                NumberAnimation {
                    target: pageLoader
                    property: "anchors.topMargin"
                    to: 0
                    duration: 200
                    easing.type: Appearance.animation.elementMoveEnter.type
                    easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                }
            }
        }
    }
}
