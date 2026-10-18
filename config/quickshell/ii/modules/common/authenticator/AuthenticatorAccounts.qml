import qs.modules.common
import qs.modules.common.widgets
import "AuthenticatorModel.js" as Model
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    objectName: "authenticatorAccounts"
    property var store: null
    signal copyRequested(string code)
    signal deleteRequested(int index, string label)
    property real now: Date.now() / 1000
    readonly property var entries: root.store?.entries ?? []
    readonly property bool loading: root.store !== null && !root.store.loaded
    readonly property bool failed: root.store?.loadError || root.store?.codeError || false

    Timer {
        id: countdownClock
        objectName: "authenticatorCountdownClock"
        interval: 100
        running: root.visible && !root.loading && !root.failed && root.entries.length > 0
        repeat: true
        onTriggered: root.now = Date.now() / 1000
    }

    ColumnLayout {
        id: status
        objectName: "authenticatorAccountStatus"
        anchors.centerIn: parent
        width: Math.max(0, parent.width - 24)
        spacing: 12
        visible: root.loading || root.failed || root.entries.length === 0

        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            text: root.loading ? "hourglass_empty" : root.failed ? "error_outline" : "lock_clock"
            iconSize: 48
            color: Appearance.colors.colOnLayer1
        }
        StyledText {
            objectName: "authenticatorEmptyCopy"
            Layout.fillWidth: true
            text: root.loading ? "Cargando tus códigos…" : root.failed ? "No se pudieron cargar los códigos." : "Aún no tienes códigos guardados."
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            color: Appearance.colors.colOnLayer1
        }
        Button {
            Layout.alignment: Qt.AlignHCenter
            text: "Reintentar"
            visible: root.failed
            onClicked: root.store?.retry()
        }
    }

    ListView {
        id: accounts
        objectName: "authenticatorAccountList"
        anchors.fill: parent
        anchors.margins: 12
        clip: true
        spacing: 8
        visible: !root.loading && !root.failed && root.entries.length > 0
        model: root.entries
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        delegate: Button {
            id: row
            objectName: "authenticatorAccountButton"
            required property var modelData
            required property int index
            property bool copied: false
            readonly property string currentCode: {
                root.now;
                return root.store?.codeFor(row.modelData) ?? "";
            }
            readonly property bool canCopy: /^(?:[0-9]{6}|[0-9]{8})$/.test(row.currentCode)
            width: accounts.width
            implicitHeight: textColumn.implicitHeight + 24
            padding: 12
            enabled: true
            hoverEnabled: true
            scale: row.down ? 0.98 : 1
            Accessible.name: (row.canCopy ? "Copiar código de " : "Código de ") + (row.modelData.issuer || row.modelData.account)
            Accessible.description: "Clic derecho para eliminar este código"
            onClicked: {
                // Re-read at activation, not from the potentially expired rendered text.
                const code = root.store?.codeFor(row.modelData) ?? "";
                if (!/^(?:[0-9]{6}|[0-9]{8})$/.test(code)) return;
                root.copyRequested(code);
                row.copied = true;
                copiedTimeout.restart();
            }

            HoverHandler {
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: root.deleteRequested(row.index,
                    row.modelData.issuer ? row.modelData.issuer + " · " + row.modelData.account : row.modelData.account)
            }
            Behavior on scale {
                NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
            }
            Timer {
                id: copiedTimeout
                objectName: "authenticatorCopyTimeout"
                interval: 1200
                onTriggered: row.copied = false
            }
            background: Rectangle {
                radius: Appearance.rounding.small
                color: row.copied ? Qt.tint(Appearance.colors.colLayer1, "#30f6d77a")
                    : row.hovered || row.visualFocus ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
                border.width: row.copied || row.visualFocus ? 1 : 0
                border.color: "#f6d77a"
                Behavior on color {
                    ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
                }
            }

            contentItem: RowLayout {
                spacing: 12

                ColumnLayout {
                    id: textColumn
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 4

                    StyledText {
                        objectName: "authenticatorCode"
                        Layout.fillWidth: true
                        text: {
                            return Model.formattedCode(row.currentCode);
                        }
                        textFormat: Text.PlainText
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.DemiBold
                        font.variableAxes: Object.assign({}, Appearance.font.variableAxes.main, { "wght": 600 })
                        elide: Text.ElideRight
                        color: Appearance.colors.colOnLayer1
                    }
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: Math.max(accountCaption.implicitHeight, copiedCaption.implicitHeight)

                        StyledText {
                            id: accountCaption
                            objectName: "authenticatorAccountCaption"
                            anchors.left: parent.left
                            anchors.right: parent.right
                            text: row.modelData.issuer ? row.modelData.issuer + " · " + row.modelData.account : row.modelData.account
                            textFormat: Text.PlainText
                            font.pixelSize: Appearance.font.pixelSize.small
                            wrapMode: Text.WordWrap
                            color: Appearance.colors.colOnLayer1
                            opacity: row.copied ? 0 : 0.75
                            Accessible.ignored: row.copied
                            Behavior on opacity {
                                NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                            }
                        }
                        StyledText {
                            id: copiedCaption
                            objectName: "authenticatorCopyFeedback"
                            anchors.left: parent.left
                            anchors.right: parent.right
                            text: "Copiado"
                            textFormat: Text.PlainText
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: "#f6d77a"
                            opacity: row.copied ? 1 : 0
                            Accessible.ignored: !row.copied
                            Behavior on opacity {
                                NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                            }
                        }
                    }
                }

                AuthenticatorCountdown {
                    objectName: "authenticatorCountdown"
                    Layout.alignment: Qt.AlignVCenter
                    remaining: Model.remainingFraction(row.modelData.period, root.now)
                    Accessible.role: Accessible.ProgressBar
                    Accessible.name: "Tiempo hasta renovar el código"
                    Accessible.description: Math.ceil(remaining * row.modelData.period) + " segundos"
                }
            }
        }
    }
}
