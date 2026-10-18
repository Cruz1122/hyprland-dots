import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    property real revealProgress: 0
    property var store: null
    property bool dragInProgress: false
    property bool suppressHandleClick: false
    property real upwardDrag: 0
    property real dragStartSceneY: 0
    readonly property real closeDragDistance: 72
    readonly property real expansion: Math.max(0, Math.min(1, root.revealProgress))
    readonly property real collapsedHeight: Math.min(root.height, Appearance.sizes.barHeight)
    signal closeRequested()
    signal methodSelected(string method)
    signal codeCopyRequested(string code)
    signal deleteRequested(int index, string label)
    signal dialogAccepted(var formData)
    signal dialogDismissed()
    property bool dialogVisible: false
    property bool dialogConfirm: false
    property bool dialogDanger: false
    property bool dialogBusy: false
    property string dialogMode: "message"
    property string dialogConfirmText: "Entendido"
    property string dialogTitle: ""
    property string dialogMessage: ""
    property string dialogIcon: "info"
    property string manualIssuer: ""
    property string manualAccount: ""
    property string manualSecret: ""
    property int manualDigits: 6
    property int manualPeriod: 30
    property string manualAlgorithm: "SHA1"
    property string backupPasswordInput: ""
    signal dragStarted()
    signal dragMoved(real distance)
    signal dragFinished(bool dismiss)

    focus: true
    Component.onCompleted: root.forceActiveFocus()
    Keys.onEscapePressed: event => {
        if (root.dialogVisible) root.dialogDismissed();
        else root.closeRequested();
        event.accepted = true;
    }

    onDialogModeChanged: {
        if (root.dialogMode !== "manual") {
            root.manualIssuer = "";
            root.manualAccount = "";
            root.manualSecret = "";
            root.manualDigits = 6;
            root.manualPeriod = 30;
            root.manualAlgorithm = "SHA1";
        }
        if (root.dialogMode !== "backup-password") root.backupPasswordInput = "";
    }

    function dialogFormData(): var {
        if (root.dialogMode === "manual") return {
            issuer: root.manualIssuer.trim(), account: root.manualAccount.trim(),
            secret: root.manualSecret, digits: root.manualDigits, period: root.manualPeriod,
            algorithm: root.manualAlgorithm
        };
        if (root.dialogMode === "backup-password") return { password: root.backupPasswordInput };
        return ({});
    }

    // Grow from the top bar's band, keeping the full-size content layout stable.
    Item {
        id: revealViewport
        width: root.width
        height: root.collapsedHeight + (root.height - root.collapsedHeight) * root.expansion
        // Blend the first/last bar-sized frames instead of popping the surface in/out.
        opacity: Math.min(1, root.expansion * 12)
        clip: true

        Rectangle {
            id: surface
            width: root.width
            height: root.height
            color: Appearance.colors.colLayer0

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Appearance.rounding.large
                anchors.bottomMargin: Appearance.rounding.large * 2 + footer.height
                spacing: Appearance.rounding.large

                Rectangle {
                    id: header
                    Layout.fillWidth: true
                    implicitHeight: headerContent.implicitHeight
                    color: "transparent"
                    border.width: 0
                    radius: Appearance.rounding.small

                    ColumnLayout {
                        id: headerContent
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 2

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: "heart_smile"
                            iconSize: Appearance.font.pixelSize.huge * 2
                            fill: 0
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: "AUTENTICADOR"
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.ExtraBold
                            font.variableAxes: Object.assign({}, Appearance.font.variableAxes.main, { "wght": 800 })
                        }
                    }

                }

                RowLayout {
                    id: body
                    objectName: "authenticatorBody"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Appearance.rounding.large
                    readonly property real availableWidth: Math.max(0, width - spacing)

                    Rectangle {
                        id: navigationPanel
                        objectName: "authenticatorNavigation"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: body.availableWidth * 0.2
                        color: "transparent"
                        border.width: 0
                        radius: Appearance.rounding.small
                        AuthenticatorAccounts {
                            anchors.fill: parent
                            store: root.store
                            onCopyRequested: code => root.codeCopyRequested(code)
                            onDeleteRequested: (index, label) => root.deleteRequested(index, label)
                        }
                    }

                    Rectangle {
                        id: contentPanel
                        objectName: "authenticatorContent"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: body.availableWidth * 0.8
                        color: "transparent"
                        border.width: 0
                        radius: Appearance.rounding.small
                        AuthenticatorMethodGrid {
                            anchors.fill: parent
                            storeReady: root.store?.loaded === true && root.store.loadError !== true
                            enabledMethods: ["capture-screen-qr", "open-qr-image", "manual-secret", "paste-otp-uri", "google-migration", "encrypted-backup"]
                            onMethodSelected: method => root.methodSelected(method)
                        }
                    }
                }

            }
        }

        // Follow the moving curtain edge without reflowing the account layout.
        Item {
            id: footer
            objectName: "authenticatorFooter"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Appearance.rounding.large
            height: closeHandle.implicitHeight
            visible: root.expansion > 0.2 || root.dragInProgress

            Button {
                id: closeHandle
                objectName: "authenticatorCloseHandle"
                anchors.centerIn: parent
                implicitWidth: 112
                implicitHeight: 48
                padding: 0
                Accessible.name: "Cerrar autenticador"
                Accessible.description: "Pulsa o arrastra hacia arriba para cerrar"
                onPressed: root.suppressHandleClick = false
                onClicked: {
                    if (!root.suppressHandleClick) root.closeRequested();
                }
                background: Rectangle {
                    radius: height / 2
                    color: parent.hovered || parent.visualFocus ? Appearance.colors.colLayer1Hover : "transparent"
                }
                contentItem: Item {
                    Rectangle {
                        anchors.centerIn: parent
                        width: 64
                        height: 5
                        radius: height / 2
                        color: Appearance.colors.colOnLayer1
                    }
                }
                DragHandler {
                    id: closeDrag
                    target: null
                    xAxis.enabled: false
                    yAxis.enabled: true
                    dragThreshold: 8
                    onActiveChanged: {
                        if (active) {
                            root.dragInProgress = true;
                            root.suppressHandleClick = true;
                            root.upwardDrag = 0;
                            root.dragStartSceneY = centroid.scenePosition.y;
                            root.dragStarted();
                        } else if (root.dragInProgress) {
                            root.dragInProgress = false;
                            root.dragFinished(root.upwardDrag >= root.closeDragDistance);
                        }
                    }
                    onActiveTranslationChanged: {
                        if (!active) return;
                        // Scene coordinates stay stable while the handle follows the edge.
                        root.upwardDrag = Math.max(0, root.dragStartSceneY - centroid.scenePosition.y);
                        root.dragMoved(root.upwardDrag);
                    }
                    onCanceled: {
                        if (!root.dragInProgress) return;
                        root.dragInProgress = false;
                        root.dragFinished(false);
                    }
                }
            }
        }
    }

    WindowDialog {
        id: feedbackDialog
        objectName: "authenticatorFeedbackDialog"
        anchors.fill: parent
        z: 1000
        backgroundWidth: root.dialogMode === "manual" ? Math.min(root.width - 48, 680)
            : root.dialogMode === "backup-password" ? Math.min(root.width - 48, 560)
            : root.dialogConfirm ? 460 : 420
        // Keep forms scrollable on short displays instead of clipping their fields.
        backgroundHeight: root.dialogMode === "manual" ? Math.min(root.height - 48, 680)
            : root.dialogMode === "backup-password" ? Math.min(root.height - 48, 420)
            : root.dialogBusy ? 280
            : root.dialogConfirm ? 280 : 250
        show: root.dialogVisible
        visible: root.dialogVisible
        onDismiss: root.dialogDismissed()

        MaterialSymbol {
            objectName: "authenticatorDialogIcon"
            Layout.alignment: Qt.AlignHCenter
            text: root.dialogIcon
            iconSize: 42
            color: root.dialogDanger ? Appearance.colors.colError : Appearance.colors.colPrimary
        }

        WindowDialogTitle {
            objectName: "authenticatorDialogTitle"
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.dialogTitle
        }

        WindowDialogParagraph {
            objectName: "authenticatorDialogMessage"
            Layout.fillWidth: true
            visible: root.dialogMessage.length > 0
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: root.dialogMessage
        }

        ScrollView {
            objectName: "authenticatorManualFormScroll"
            Layout.fillWidth: true
            Layout.preferredHeight: 350
            Layout.maximumHeight: Math.max(180, root.height - 300)
            visible: root.dialogMode === "manual"
            clip: true
            contentWidth: availableWidth
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            ColumnLayout {
                id: manualForm
                objectName: "authenticatorManualForm"
                width: Math.min(parent.width, 520)
                x: (parent.width - width) / 2
                spacing: 12

                MaterialTextField {
                    objectName: "authenticatorManualIssuer"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 54
                    placeholderText: "Servicio / emisor (opcional)"
                    text: root.manualIssuer
                    onTextEdited: root.manualIssuer = text
                    Accessible.name: "Servicio o emisor"
                }
                MaterialTextField {
                    objectName: "authenticatorManualAccount"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 54
                    placeholderText: "Cuenta (correo o usuario)"
                    text: root.manualAccount
                    onTextEdited: root.manualAccount = text
                    Accessible.name: "Cuenta"
                }
                MaterialTextField {
                    id: manualSecretField
                    objectName: "authenticatorManualSecret"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 54
                    placeholderText: "Clave secreta Base32"
                    echoMode: TextInput.Password
                    maximumLength: 512
                    text: root.manualSecret
                    onTextEdited: root.manualSecret = text
                    Accessible.name: "Clave secreta Base32"
                }
                RowLayout {
                    Layout.fillWidth: true
                    StyledComboBox {
                        id: manualAlgorithmField
                        objectName: "authenticatorManualAlgorithm"
                        Layout.fillWidth: true
                        buttonRadius: Appearance.rounding.small
                        model: ["SHA1", "SHA256", "SHA512"]
                        currentIndex: Math.max(0, model.indexOf(root.manualAlgorithm))
                        onActivated: root.manualAlgorithm = currentText
                        Accessible.name: "Algoritmo"
                    }
                    StyledComboBox {
                        id: manualDigitsField
                        objectName: "authenticatorManualDigits"
                        Layout.fillWidth: true
                        buttonRadius: Appearance.rounding.small
                        model: ["6", "8"]
                        currentIndex: root.manualDigits === 8 ? 1 : 0
                        onActivated: root.manualDigits = Number(currentText)
                        Accessible.name: "Dígitos del código"
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    StyledText {
                        Layout.fillWidth: true
                        text: "Periodo (segundos)"
                        color: Appearance.colors.colOnLayer1
                        Accessible.name: "Periodo en segundos"
                    }
                    StyledSpinBox {
                        objectName: "authenticatorManualPeriod"
                        Layout.preferredWidth: 150
                        from: 1
                        to: 3600
                        value: root.manualPeriod
                        onValueModified: root.manualPeriod = value
                        Accessible.name: "Periodo en segundos"
                    }
                }
            }
        }

        ColumnLayout {
            objectName: "authenticatorBackupPasswordForm"
            Layout.fillWidth: true
            visible: root.dialogMode === "backup-password"

            MaterialTextField {
                id: backupPasswordField
                objectName: "authenticatorBackupPassword"
                Layout.fillWidth: true
                Layout.preferredHeight: 54
                placeholderText: "Contraseña de la copia"
                echoMode: TextInput.Password
                maximumLength: 4096
                text: root.backupPasswordInput
                onTextEdited: root.backupPasswordInput = text
                Accessible.name: "Contraseña de la copia cifrada"
            }
        }

        WindowDialogButtonRow {
            Item {
                Layout.fillWidth: true
                implicitHeight: dialogButtons.implicitHeight

                RowLayout {
                    id: dialogButtons
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 4

                    DialogButton {
                        objectName: "authenticatorDialogCancel"
                        visible: root.dialogConfirm
                        buttonText: "Cancelar"
                        onClicked: feedbackDialog.dismiss()
                    }

                    DialogButton {
                        objectName: "authenticatorDialogConfirm"
                        visible: root.dialogConfirm && !root.dialogBusy
                        buttonText: root.dialogConfirmText
                        colEnabled: root.dialogDanger ? Appearance.colors.colError : Appearance.colors.colPrimary
                        onClicked: root.dialogAccepted(root.dialogFormData())
                    }

                    DialogButton {
                        objectName: "authenticatorDialogAcknowledge"
                        visible: !root.dialogConfirm
                        buttonText: root.dialogConfirmText
                        onClicked: feedbackDialog.dismiss()
                    }
                }
            }
        }
    }
}
