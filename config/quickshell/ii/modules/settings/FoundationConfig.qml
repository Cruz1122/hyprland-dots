import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.components

SettingsPage {
    forceWidth: true

    SettingsSection {
        icon: "foundation"
        title: Translation.tr("Settings foundation")

        SettingsBanner {
            Layout.fillWidth: true
            materialIcon: "verified"
            text: Translation.tr("This page uses the new SettingsRegistry and SettingsStore path. Changes are validated before touching Config.options.")
        }

        SettingsResponsiveRow {
            uniform: true
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Schema version")
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                text: SettingsRegistry.schemaVersion.toString()
                color: Appearance.colors.colPrimary
            }
        }

        SettingsResponsiveRow {
            uniform: true
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Last operation")
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                text: `${SettingsStore.lastStatus}: ${SettingsStore.lastMessage}`
                color: SettingsStore.lastStatus === "error" ? Appearance.colors.colError : Appearance.colors.colPrimary
            }
        }
    }

    SettingsSection {
        icon: "palette"
        title: Translation.tr("Validated appearance settings")

        SettingsSwitchRow {
            buttonIcon: "opacity"
            text: Translation.tr("Transparency")
            checked: Config.options.appearance.transparency.enable ?? false
            onCheckedChanged: Config.options.appearance.transparency.enable = checked
        }

        SettingsNumberRow {
            icon: "opacity"
            text: Translation.tr("Background transparency (%)")
            from: 0
            to: 100
            stepSize: 1
            value: Math.round((Config.options.appearance.transparency.backgroundTransparency ?? 0) * 100)
            onValueChanged: Config.options.appearance.transparency.backgroundTransparency = value / 100
        }
    }

    SettingsSection {
        icon: "settings_applications"
        title: Translation.tr("Validated system settings")

        SettingsSwitchRow {
            buttonIcon: "hearing"
            text: Translation.tr("Ear protection")
            checked: Config.options.audio.protection.enable ?? false
            onCheckedChanged: Config.options.audio.protection.enable = checked
        }
    }
}
