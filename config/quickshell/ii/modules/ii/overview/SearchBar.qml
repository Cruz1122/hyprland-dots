pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.bar

// Launcher search field: a single pill with a leading icon that reflects the
// active search prefix and a trailing clear button.
Item {
    id: root
    property bool animateWidth: false
    // When true the input stretches to the available width instead of using
    // the collapsed/expanded fixed widths.
    property bool fillWidth: false
    property alias searchInput: searchInput
    property string searchingText

    function forceFocus() {
        searchInput.forceActiveFocus();
    }

    enum SearchPrefixType { Action, App, Clipboard, Emojis, Math, ShellCommand, WebSearch, DefaultSearch }

    property var searchPrefixType: {
        if (root.searchingText.startsWith(Config.options.search.prefix.action)) return SearchBar.SearchPrefixType.Action;
        if (root.searchingText.startsWith(Config.options.search.prefix.app)) return SearchBar.SearchPrefixType.App;
        if (root.searchingText.startsWith(Config.options.search.prefix.clipboard)) return SearchBar.SearchPrefixType.Clipboard;
        if (root.searchingText.startsWith(Config.options.search.prefix.emojis)) return SearchBar.SearchPrefixType.Emojis;
        if (root.searchingText.startsWith(Config.options.search.prefix.math)) return SearchBar.SearchPrefixType.Math;
        if (root.searchingText.startsWith(Config.options.search.prefix.shellCommand)) return SearchBar.SearchPrefixType.ShellCommand;
        if (root.searchingText.startsWith(Config.options.search.prefix.webSearch)) return SearchBar.SearchPrefixType.WebSearch;
        return SearchBar.SearchPrefixType.DefaultSearch;
    }
    readonly property string prefixIcon: switch (root.searchPrefixType) {
        case SearchBar.SearchPrefixType.Action: return "settings_suggest";
        case SearchBar.SearchPrefixType.App: return "apps";
        case SearchBar.SearchPrefixType.Clipboard: return "content_paste_search";
        case SearchBar.SearchPrefixType.Emojis: return "add_reaction";
        case SearchBar.SearchPrefixType.Math: return "calculate";
        case SearchBar.SearchPrefixType.ShellCommand: return "terminal";
        case SearchBar.SearchPrefixType.WebSearch: return "travel_explore";
        default: return "search";
    }
    readonly property bool hasText: root.searchingText.length > 0

    implicitWidth: row.implicitWidth + row.anchors.leftMargin + row.anchors.rightMargin
    implicitHeight: 50

    // Rim that lights up while typing: the launcher's edge light, on the field.
    IridescentFill {
        active: root.hasText
    }

    Rectangle { // Field surface
        anchors.fill: parent
        anchors.margins: root.hasText ? 1.5 : 0
        radius: height / 2
        // Opaque, so the rim behind it only shows as a ring.
        color: Appearance.m3colors.m3surfaceContainerHigh
        Behavior on anchors.margins {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    RowLayout {
        id: row
        anchors {
            fill: parent
            leftMargin: 18
            rightMargin: 9
        }
        spacing: 4

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: root.prefixIcon
            animateChange: true
            iconSize: Appearance.font.pixelSize.huge
            color: root.hasText ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        ToolbarTextField { // Search box
            id: searchInput
            Layout.fillWidth: root.fillWidth
            Layout.fillHeight: true
            colBackground: "transparent"
            padding: 8
            focus: GlobalStates.overviewOpen
            font.pixelSize: Appearance.font.pixelSize.large
            placeholderText: Translation.tr("Search, calculate or run")
            implicitWidth: root.searchingText == "" ? Appearance.sizes.searchWidthCollapsed : Appearance.sizes.searchWidth

            Behavior on implicitWidth {
                id: searchWidthBehavior
                enabled: root.animateWidth
                NumberAnimation {
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                }
            }

            onTextChanged: LauncherSearch.query = text

            onAccepted: {
                if (appResults.count > 0) {
                    // Get the first visible delegate and trigger its click
                    let firstItem = appResults.itemAtIndex(0);
                    if (firstItem && firstItem.clicked) {
                        firstItem.clicked();
                    }
                }
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Tab) {
                    if (LauncherSearch.results.length === 0) return;
                    const tabbedText = LauncherSearch.results[0].name;
                    LauncherSearch.query = tabbedText;
                    searchInput.text = tabbedText;
                    event.accepted = true;
                }
            }
        }

        Rectangle { // Clear button
            id: clearButton
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 32
            implicitHeight: 32
            radius: width / 2
            color: clearArea.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
            opacity: root.hasText ? 1 : 0
            visible: opacity > 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            MaterialSymbol {
                anchors.centerIn: parent
                text: "close"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colSubtext
            }
            MouseArea {
                id: clearArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    searchInput.text = "";
                    root.forceFocus();
                }
            }
        }
    }
}
