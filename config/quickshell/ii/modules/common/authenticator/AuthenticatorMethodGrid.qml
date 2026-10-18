import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    objectName: "authenticatorMethodGrid"
    property bool storeReady: false
    property var enabledMethods: []
    signal methodSelected(string method)

    readonly property var methods: [
        { id: "capture-screen-qr", icon: "screenshot_region", title: "Capturar QR", description: "Usar un código en pantalla" },
        { id: "open-qr-image", icon: "image", title: "Abrir imagen", description: "Leer un código desde una imagen" },
        { id: "manual-secret", icon: "key", title: "Clave manual", description: "Introducir la clave secreta" },
        { id: "paste-otp-uri", icon: "link", title: "Pegar URI", description: "Usar un enlace otpauth" },
        { id: "google-migration", icon: "move_to_inbox", title: "Migrar cuentas", description: "Desde Google Authenticator" },
        { id: "encrypted-backup", icon: "folder_open", title: "Importar copia", description: "Cargar un respaldo cifrado" }
    ]

    GridLayout {
        id: grid
        objectName: "authenticatorMethodOptions"
        anchors.fill: parent
        anchors.margins: 16
        columns: 3
        rows: 2
        rowSpacing: 12
        columnSpacing: 12

        Repeater {
            model: root.methods

            delegate: Button {
                id: option
                objectName: "authenticatorMethodOption"
                required property var modelData
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 0
                Layout.minimumHeight: 0
                property bool available: root.storeReady && root.enabledMethods.indexOf(modelData.id) !== -1
                enabled: available
                hoverEnabled: true
                onClicked: root.methodSelected(modelData.id)
                HoverHandler {
                    cursorShape: option.available ? Qt.PointingHandCursor : Qt.ArrowCursor
                }
                Accessible.name: modelData.title + ". " + modelData.description
                Accessible.description: available ? modelData.description
                    : "Disponible cuando se cargue el almacén seguro"
                opacity: available ? 1 : 0.72
                background: Rectangle {
                    radius: Appearance.rounding.small
                    color: option.hovered ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
                    Behavior on color {
                        ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
                    }
                }

                ColumnLayout {
                    id: tileContent
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 10

                    ColumnLayout {
                        Layout.alignment: Qt.AlignCenter
                        Layout.fillWidth: true
                        spacing: 12

                        MaterialSymbol {
                            objectName: "authenticatorMethodIcon"
                            Layout.alignment: Qt.AlignHCenter
                            text: option.modelData.icon
                            iconSize: Math.min(48, Math.max(28, option.height * 0.15))
                            color: Appearance.colors.colOnLayer1
                        }

                        StyledText {
                            objectName: "authenticatorMethodTitle"
                            Layout.alignment: Qt.AlignHCenter
                            Layout.fillWidth: true
                            text: option.modelData.title
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            color: Appearance.colors.colOnLayer1
                        }

                        StyledText {
                            objectName: "authenticatorMethodDescription"
                            Layout.alignment: Qt.AlignHCenter
                            Layout.fillWidth: true
                            text: option.modelData.description
                            font.pixelSize: Appearance.font.pixelSize.small
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            color: Appearance.colors.colOnLayer1
                            opacity: 0.75
                        }
                    }
                }
            }
        }
    }
}
