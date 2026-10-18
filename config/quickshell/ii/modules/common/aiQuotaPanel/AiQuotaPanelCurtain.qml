import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import "../../ii/bar/AiQuotaPresentation.js" as Quota

// Layout prototype for the AI quota panel. It mirrors the authenticator curtain
// (grow-from-bar reveal, footer close handle, Esc) but drops the header and lays
// the body out as six equal cards in a 3x2 grid, one per provider brand.
Item {
    id: root
    property real revealProgress: 0
    property bool dragInProgress: false
    property bool suppressHandleClick: false
    property real upwardDrag: 0
    property real dragStartSceneY: 0
    readonly property real closeDragDistance: 72
    readonly property real expansion: Math.max(0, Math.min(1, root.revealProgress))
    readonly property real collapsedHeight: Math.min(root.height, Appearance.sizes.barHeight)
    // Drives the relative reset countdown so it stays current while open.
    property double clockMs: Date.now()
    signal closeRequested()
    signal dragStarted()
    signal dragMoved(real distance)
    signal dragFinished(bool dismiss)

    // Uniform content frame for every brand cell. The icon is padded identically
    // to the last bar, and both distances derive from the same numbers.
    readonly property real cellPadding: 40
    // Vertical inset leaves enough room under the icons for providers that report
    // two rows of quota windows (up to four windows) on a 1080p screen, while
    // keeping every card's icon and label aligned.
    readonly property real cellVerticalInset: 66
    readonly property real cellGap: 20
    // One entry per provider brand. scale is an optical factor applied by sizing
    // the image inside its fixed-height slot (never by transforming the layered
    // item) so all glyphs keep the same visual height.
    readonly property var columns: [
        { name: "OpenAI", file: "openai", scale: 1.016 },
        { name: "OpenCode", file: "opencode", scale: 1.0 },
        { name: "Antigravity", file: "antigravity", scale: 1.024 },
        { name: "Zed", file: "zed", scale: 1.0 },
        { name: "Cursor", file: "cursor", scale: 1.0 },
        { name: "Claude", file: "claude", scale: 1.008 }
    ]
    // Every glyph is laid out to the exact same height; the width follows the
    // source aspect ratio, so there is no letterboxing and no brand stands out.
    readonly property int iconSize: 128

    function openRequestedConnection() {
        const provider = AiQuotaUsage.requestedProvider;
        if (!provider || connectDialog.submitting) return;
        const brand = root.columns.find(item => (item.file === "openai" ? "codex" : item.file) === provider);
        AiQuotaUsage.requestedProvider = "";
        if (!brand) return;
        connectDialog.provider = provider;
        connectDialog.providerName = brand.name;
        connectDialog.source = (AiQuotaUsage.snapshot(provider).sources ?? [])[0] ?? "";
        connectDialog.accountId = "";
        connectDialog.reconnectMode = false;
        connectDialog.show = true;
    }

    Connections {
        target: AiQuotaUsage
        function onRequestedProviderChanged() { root.openRequestedConnection(); }
    }

    focus: true
    Component.onCompleted: {
        root.forceActiveFocus();
        root.openRequestedConnection();
    }
    Keys.onEscapePressed: event => {
        root.closeRequested();
        event.accepted = true;
    }

    Timer {
        interval: 30000
        repeat: true
        running: root.expansion > 0
        onTriggered: root.clockMs = Date.now()
    }

    // Grow from the top bar's band, keeping the full-size content layout stable.
    Item {
        id: revealViewport
        width: root.width
        height: root.collapsedHeight + (root.height - root.collapsedHeight) * root.expansion
        opacity: Math.min(1, root.expansion * 12)
        clip: true

        Rectangle {
            id: surface
            width: root.width
            height: root.height
            color: Appearance.colors.colLayer0

            GridLayout {
                id: grid
                objectName: "aiQuotaPanelBody"
                anchors.fill: parent
                anchors.margins: Appearance.rounding.large
                anchors.bottomMargin: Appearance.rounding.large * 2 + footer.height
                columns: 3
                rows: 2
                rowSpacing: Appearance.rounding.large
                columnSpacing: Appearance.rounding.large

                Repeater {
                    model: root.columns

                    delegate: Rectangle {
                        id: cell
                        required property var modelData
                        objectName: "aiQuotaPanelColumn"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumWidth: 0
                        Layout.minimumHeight: 0
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer1
                        // Uniform frame across cards: every icon occupies the same
                        // height and starts at the same offset, so icons and labels
                        // line up vertically across the whole grid.
                        readonly property real iconHeight: root.iconSize
                        readonly property string providerId: cell.modelData.file === "openai" ? "codex" : cell.modelData.file
                        // The Zed card shows the local Grok Bot weekly reading by
                        // default; the top-corner switch reveals the Zed budget.
                        readonly property bool switchable: cell.providerId === "zed"
                        property bool altView: true
                        readonly property string activeProviderId: cell.switchable && cell.altView ? "grokbot" : cell.providerId
                        readonly property var snapshot: AiQuotaUsage.snapshot(cell.activeProviderId)
                        readonly property bool authenticated: Quota.connected(cell.snapshot)
                        readonly property bool showBars: cell.authenticated || (cell.switchable && cell.altView)
                        readonly property int windowCount: (cell.snapshot.windows ?? []).length
                        // Largest bars area that still fits under the icon and title.
                        readonly property real barsMaxHeight: Math.max(0,
                            cellColumn.height - cell.iconHeight - titleText.implicitHeight - root.cellGap * 3)

                        ColumnLayout {
                            id: cellColumn
                            anchors.fill: parent
                            anchors.leftMargin: root.cellPadding
                            anchors.rightMargin: root.cellPadding
                            anchors.topMargin: root.cellVerticalInset
                            anchors.bottomMargin: root.cellVerticalInset
                            spacing: root.cellGap

                            // Brand glyph slot. The switchable Zed card cross-fades
                            // between its own glyph and the Grok Bot mascot.
                            Item {
                                id: iconSlot
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredHeight: cell.iconHeight
                                Layout.preferredWidth: cell.iconHeight * (brandIcon.implicitWidth / Math.max(1, brandIcon.implicitHeight))

                                Image {
                                    id: brandIcon
                                    // Size the image for optical parity instead of
                                    // scaling the layered item: a transformed layer
                                    // resamples its texture with nearest filtering,
                                    // flattening glyph tips that touch the trimmed
                                    // viewBox edge. The slot keeps the layout height.
                                    anchors.centerIn: parent
                                    width: parent.width * cell.modelData.scale
                                    height: parent.height * cell.modelData.scale
                                    sourceSize: Qt.size(256, 256)
                                    fillMode: Image.PreserveAspectFit
                                    source: Qt.resolvedUrl("../../../assets/icons/ai/" + cell.modelData.file + ".svg")
                                    opacity: (cell.switchable && cell.altView) ? 0 : 1
                                    layer.enabled: true
                                    layer.smooth: true
                                    layer.effect: ColorOverlay {
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    Behavior on opacity {
                                        NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
                                    }
                                }

                                Image {
                                    id: altIcon
                                    anchors.fill: parent
                                    visible: cell.switchable
                                    sourceSize: Qt.size(256, 256)
                                    fillMode: Image.PreserveAspectFit
                                    // Official Grok Bot logo (its own shading), not recolored.
                                    source: Qt.resolvedUrl("../../../assets/icons/ai/grokbot.png")
                                    opacity: (cell.switchable && cell.altView) ? 1 : 0
                                    Behavior on opacity {
                                        NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
                                    }
                                }
                            }

                            StyledText {
                                id: titleText
                                objectName: "aiQuotaPanelColumnTitle"
                                Layout.fillWidth: true
                                text: (cell.switchable && cell.altView) ? "GROK BOT" : cell.modelData.name.toUpperCase()
                                horizontalAlignment: Text.AlignHCenter
                                font.weight: Font.ExtraBold
                                font.variableAxes: Object.assign({}, Appearance.font.variableAxes.main, { "wght": 800 })
                                color: Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                            }

                            // Elastic gap: the icon and label stay pinned to the top
                            // (aligned across cards) while the bars sit at the bottom,
                            // so the gap above the icon equals the gap below the bars.
                            Item { Layout.fillHeight: true }

                            // Per-cell state: a connect action when no account is
                            // bound, otherwise one availability bar per quota window
                            // (weekly, daily or hourly depending on what the provider
                            // reports). The bars live in a clipped, scrollable area
                            // so a provider reporting many windows can never spill
                            // out of the container.
                            Item {
                                id: barsHolder
                                Layout.fillWidth: true
                                // Content-sized, but never taller than the space left
                                // under the icon and title, so it scrolls instead of
                                // overflowing the cell.
                                Layout.preferredHeight: cell.showBars
                                    ? Math.min(barsColumn.implicitHeight, cell.barsMaxHeight)
                                    : connectButton.implicitHeight
                                clip: true

                                Item {
                                    id: connectSlot
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    height: connectButton.implicitHeight
                                    visible: AiQuotaUsage.available && !cell.showBars

                                    Button {
                                        id: connectButton
                                        objectName: "aiQuotaPanelConnect"
                                        anchors.centerIn: parent
                                        implicitWidth: 168
                                        implicitHeight: 52
                                        padding: 0
                                        text: "Conectar"
                                        Accessible.name: "Conectar " + cell.modelData.name
                                        onClicked: {
                                            connectDialog.provider = cell.providerId;
                                            connectDialog.providerName = cell.modelData.name;
                                            connectDialog.source = (cell.snapshot.sources ?? [])[0] ?? "";
                                            connectDialog.accountId = "";
                                            connectDialog.reconnectMode = false;
                                            connectDialog.show = true;
                                        }
                                        background: Rectangle {
                                            // Square corners on purpose.
                                            radius: 0
                                            color: connectButton.hovered ? Appearance.colors.colPrimaryContainerHover
                                                : Appearance.colors.colPrimaryContainer
                                        }
                                        contentItem: StyledText {
                                            // Same typography as the cell headers.
                                            text: connectButton.text.toUpperCase()
                                            color: Appearance.colors.colOnPrimaryContainer
                                            font.weight: Font.ExtraBold
                                            font.variableAxes: Object.assign({}, Appearance.font.variableAxes.main, { "wght": 800 })
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                    }
                                }

                                Flickable {
                                    id: barsView
                                    anchors.fill: parent
                                    visible: cell.showBars
                                    clip: true
                                    contentWidth: width
                                    contentHeight: barsColumn.implicitHeight
                                    boundsBehavior: Flickable.StopAtBounds
                                    ScrollBar.vertical: ScrollBar {
                                        policy: ScrollBar.AsNeeded
                                    }

                                    ColumnLayout {
                                        id: barsColumn
                                        width: barsView.width
                                        spacing: 10

                                        // More than two windows wrap into two per row;
                                        // one or two stay full width.
                                        GridLayout {
                                            id: barsGrid
                                            Layout.fillWidth: true
                                            readonly property int columnCount: Quota.windowColumns((cell.snapshot.windows ?? []).length)
                                            // Exactly equal columns: two windows split the row
                                            // evenly, one spans the full width.
                                            readonly property real columnWidth: columnCount > 1
                                                ? Math.max(0, (width - columnSpacing * (columnCount - 1)) / columnCount)
                                                : width
                                            columns: columnCount
                                            columnSpacing: 16
                                            rowSpacing: 12

                                            Repeater {
                                                model: cell.snapshot.windows ?? []

                                                delegate: ColumnLayout {
                                                    required property var modelData
                                                    required property int index
                                                    Layout.fillWidth: true
                                                    // An odd trailing bar spans the full row
                                                    // instead of leaving half of it empty.
                                                    readonly property bool spansRow: Quota.spansFullRow(
                                                        index, cell.windowCount, barsGrid.columnCount)
                                                    Layout.columnSpan: spansRow ? barsGrid.columnCount : 1
                                                    Layout.preferredWidth: spansRow ? barsGrid.width : barsGrid.columnWidth
                                                    spacing: 4

                                                    // Relative time left, never an absolute instant.
                                                    readonly property string countdown:
                                                        Quota.resetCountdown(modelData.resetsAt, root.clockMs)
                                                        ?? modelData.resetText ?? ""
                                                    readonly property string usageText:
                                                        modelData.usedAmount !== null && modelData.usedAmount !== undefined
                                                            ? "Uso: " + modelData.usedAmount + (modelData.limitAmount != null
                                                                ? " / " + modelData.limitAmount : "")
                                                            : ""
                                                    // Prefer the reset countdown; fall back to the usage amount.
                                                    readonly property string secondaryText: countdown.length > 0 ? countdown : usageText
                                                    readonly property string percentText:
                                                        Quota.remainingPercent(modelData) === null ? "—"
                                                            : Math.round(Quota.remainingPercent(modelData)) + "%"

                                                    // Full-width range label (5 h, Semanal, …) so the
                                                    // percentage never squeezes it.
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: modelData.label
                                                        color: "#f6d77a"
                                                        font.pixelSize: Appearance.font.pixelSize.small
                                                        font.weight: Font.Bold
                                                        font.variableAxes: Object.assign({}, Appearance.font.variableAxes.main, { "wght": 700 })
                                                        wrapMode: Text.Wrap
                                                        maximumLineCount: 2
                                                        elide: Text.ElideRight
                                                    }

                                                    Rectangle {
                                                        Layout.fillWidth: true
                                                        implicitHeight: 6
                                                        radius: height / 2
                                                        color: Appearance.colors.colLayer2

                                                        Rectangle {
                                                            readonly property real remaining: Quota.remainingPercent(modelData) ?? 0
                                                            width: parent.width * remaining / 100
                                                            height: parent.height
                                                            radius: parent.radius
                                                            color: remaining <= 15 ? Appearance.colors.colError
                                                                : Appearance.colors.colPrimary
                                                        }
                                                    }

                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 6

                                                        StyledText {
                                                            Layout.fillWidth: true
                                                            visible: secondaryText.length > 0
                                                            text: secondaryText
                                                            textFormat: Text.PlainText
                                                            color: Appearance.colors.colOnSurfaceVariant
                                                            font.pixelSize: Appearance.font.pixelSize.small
                                                            elide: Text.ElideRight
                                                        }
                                                        StyledText {
                                                            Layout.alignment: Qt.AlignRight
                                                            text: percentText
                                                            color: Appearance.colors.colOnLayer1
                                                            font.pixelSize: Appearance.font.pixelSize.small
                                                            font.weight: Font.DemiBold
                                                        }
                                                    }
                                                }
                                        }
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            visible: (cell.snapshot.windows ?? []).length === 0
                                            text: cell.snapshot.message ?? "Cuota no disponible"
                                            textFormat: Text.PlainText
                                            wrapMode: Text.Wrap
                                            color: Appearance.colors.colOnSurfaceVariant
                                            font.pixelSize: Appearance.font.pixelSize.small
                                        }

                                        Button {
                                            visible: !(cell.switchable && cell.altView)
                                                && cell.snapshot.status !== "ready" && cell.snapshot.status !== "loading"
                                                && cell.snapshot.status !== "waiting-usage"
                                            text: "Reconectar"
                                            onClicked: {
                                                connectDialog.provider = cell.providerId;
                                                connectDialog.providerName = cell.modelData.name;
                                                connectDialog.source = cell.snapshot.source;
                                                connectDialog.accountId = cell.snapshot.accountId;
                                                connectDialog.reconnectMode = true;
                                                connectDialog.show = true;
                                            }
                                        }
                                    }
                                }

                                StyledText {
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    visible: !AiQuotaUsage.available
                                    text: "Servicio de cuotas no disponible."
                                    textFormat: Text.PlainText
                                    wrapMode: Text.Wrap
                                    color: Appearance.colors.colOnSurfaceVariant
                                    font.pixelSize: Appearance.font.pixelSize.small
                                }
                            }
                        }

                        // Top-corner switch: reveals the Zed budget while the card
                        // shows the local Grok Bot weekly reading by default.
                        Button {
                            id: viewSwitch
                            objectName: "aiQuotaPanelViewSwitch"
                            visible: cell.switchable
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 14
                            implicitWidth: 32
                            implicitHeight: 32
                            padding: 0
                            Accessible.name: "Alternar Zed y Grok Bot"
                            Accessible.description: cell.altView
                                ? "Mostrar el límite de Zed" : "Mostrar el límite de Grok Bot"
                            onClicked: cell.altView = !cell.altView
                            background: Rectangle {
                                radius: height / 2
                                color: viewSwitch.hovered || viewSwitch.visualFocus
                                    ? Appearance.colors.colLayer1Hover : "transparent"
                            }
                            contentItem: Image {
                                source: Qt.resolvedUrl("../../../assets/icons/swap-symbolic.svg")
                                sourceSize: Qt.size(64, 64)
                                fillMode: Image.PreserveAspectFit
                                // Half-turn on toggle so the switch reads as animated.
                                rotation: cell.altView ? 180 : 0
                                Behavior on rotation {
                                    NumberAnimation { duration: 260; easing.type: Easing.InOutCubic }
                                }
                                layer.enabled: true
                                layer.effect: ColorOverlay {
                                    color: cell.altView ? "#f6d77a" : Appearance.colors.colOnLayer1
                                }
                            }
                        }
                    }
                }
            }
        }

        // Follow the moving curtain edge without reflowing the column layout.
        Item {
            id: footer
            objectName: "aiQuotaPanelFooter"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Appearance.rounding.large
            height: closeHandle.implicitHeight
            visible: root.expansion > 0.2 || root.dragInProgress

            Button {
                id: closeHandle
                objectName: "aiQuotaPanelCloseHandle"
                anchors.centerIn: parent
                implicitWidth: 112
                implicitHeight: 48
                padding: 0
                Accessible.name: "Cerrar panel de cuotas de IA"
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

    // GUI connect flow: credential entry happens here, never in a terminal.
    AiQuotaConnectDialog {
        id: connectDialog
        onDismissed: connectDialog.show = false
    }
}
