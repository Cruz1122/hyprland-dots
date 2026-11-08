import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.settings.components

SettingsPage {
    id: aboutPage
    pageId: "about"

    customDelegates: ({
        "info.about.distro": distro,
        "info.about.dotfiles": dotfiles
    })

    Component {
        id: distro

        ProjectCard {
            iconName: SystemInfo.logo
            fallbackSymbol: "computer"
            name: SystemInfo.distroName
            url: SystemInfo.homeUrl
            links: [
                { icon: "auto_stories", text: Translation.tr("Documentation"), url: SystemInfo.documentationUrl },
                { icon: "support", text: Translation.tr("Help & Support"), url: SystemInfo.supportUrl },
                { icon: "bug_report", text: Translation.tr("Report a Bug"), url: SystemInfo.bugReportUrl },
                { icon: "policy", text: Translation.tr("Privacy Policy"), url: SystemInfo.privacyPolicyUrl }
            ]
        }
    }

    Component {
        id: dotfiles

        ProjectCard {
            iconName: "illogical-impulse"
            fallbackSymbol: "folder_managed"
            name: Translation.tr("illogical-impulse")
            url: "https://github.com/end-4/dots-hyprland"
            links: [
                { icon: "auto_stories", text: Translation.tr("Documentation"), url: "https://end-4.github.io/dots-hyprland-wiki/en/ii-qs/02usage/" },
                { icon: "adjust", text: Translation.tr("Issues"), url: "https://github.com/end-4/dots-hyprland/issues" },
                { icon: "forum", text: Translation.tr("Discussions"), url: "https://github.com/end-4/dots-hyprland/discussions" },
                { icon: "favorite", text: Translation.tr("Donate"), url: "https://github.com/sponsors/end-4" }
            ]
        }
    }

    component ProjectCard: ColumnLayout {
        id: card
        property var row: null
        property string iconName: ""
        property string fallbackSymbol: ""
        // check=true returns "" for a missing theme icon instead of warning.
        readonly property string iconSource: card.iconName.length > 0 ? Quickshell.iconPath(card.iconName, true) : ""
        property string name: ""
        property string url: ""
        property var links: []

        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            IconImage {
                visible: card.iconSource.length > 0
                implicitSize: 64
                source: card.iconSource
            }

            MaterialSymbol {
                visible: card.iconSource.length === 0
                text: card.fallbackSymbol
                iconSize: 56
                color: Appearance.colors.colPrimary
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: card.name
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.title
                }

                StyledText {
                    visible: card.url.length > 0
                    Layout.fillWidth: true
                    text: card.url
                    textFormat: Text.PlainText
                    elide: Text.ElideMiddle
                    color: Appearance.colors.colPrimary
                    TapHandler {
                        onTapped: Qt.openUrlExternally(card.url)
                    }
                    HoverHandler {
                        cursorShape: Qt.PointingHandCursor
                    }
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: card.links.filter(link => link.url.length > 0)

                delegate: SettingsButton {
                    required property var modelData
                    kind: "tonal"
                    iconName: modelData.icon
                    text: modelData.text
                    onClicked: Qt.openUrlExternally(modelData.url)
                }
            }
        }
    }
}
