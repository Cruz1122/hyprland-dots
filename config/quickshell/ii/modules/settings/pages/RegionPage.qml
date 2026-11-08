import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.settings.core
import qs.modules.settings.components
import "RegionLogic.js" as RegionLogic

SettingsPage {
    id: root
    pageId: "region"

    readonly property string timeFormat: (SettingsStore.revision, SettingsStore.value("time.format")) ?? "hh:mm"
    readonly property bool seconds: (SettingsStore.revision, SettingsStore.value("time.secondPrecision")) === true

    customDelegates: ({
        "language.ui": languagePicker
    })

    function formatDate(date, format) {
        return Qt.locale().toString(date, String(format ?? ""));
    }

    infoValues: {
        void SettingsStore.revision;
        const now = clock.date;
        const dates = ["time.dateFormat", "time.shortDateFormat", "time.dateWithYearFormat"]
            .map(key => root.formatDate(now, SettingsStore.value(key)));
        return {
            "info.region.timePreview": RegionLogic.formatTime(now, root.timeFormat, root.seconds, root.formatDate),
            "info.region.datePreview": dates.join("  ·  ")
        };
    }

    SystemClock {
        id: clock
        precision: root.seconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    // hyprlock renders its own clock from $TIME or $TIME12; keep it in step
    // with the shell format. Runs only after a committed change, never on load.
    Connections {
        target: SettingsStore
        function onCommitted(key) {
            if (key === "time.format")
                Quickshell.execDetached(["python3", Quickshell.shellPath("scripts/settings/hyprlock-time.py"), RegionLogic.hyprlockMode(SettingsStore.value("time.format"))]);
        }
    }

    Component {
        id: languagePicker

        RowLayout {
            id: picker
            property var row: null
            readonly property string stored: picker.row?.value ?? "auto"
            readonly property var options: RegionLogic.languageChoices(Translation.allAvailableLanguages, picker.stored, Translation.tr("Automatic (system language)"))
            readonly property int storedIndex: picker.options.findIndex(o => o.value === picker.stored)

            StyledComboBox {
                id: combo
                Layout.preferredWidth: 280
                Layout.maximumWidth: 360
                enabled: picker.row?.rowEnabled ?? false
                model: picker.options
                textRole: "label"
                Accessible.name: picker.row?.label ?? ""
                // ComboBox resets currentIndex when its model is replaced
                // (languages and screens arrive asynchronously); reapply.
                onModelChanged: Qt.callLater(() => combo.currentIndex = picker.storedIndex)
                onActivated: index => {
                    const value = picker.options[index].value;
                    if (!RegionLogic.isLanguageValue(value) || !picker.row.commit(value))
                        combo.currentIndex = picker.storedIndex;
                }
            }

            Binding {
                target: combo
                property: "currentIndex"
                value: picker.storedIndex
                restoreMode: Binding.RestoreNone
            }

            Item {
                Layout.fillWidth: true
            }
        }
    }
}
