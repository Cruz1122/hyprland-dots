pragma Singleton
import QtQuick

QtObject {
    readonly property var colors: ({ colLayer0: "#141414", colLayer1: "#303030",
        colLayer1Hover: "#404040", colOnLayer1: "#ded8cc",
        colPrimary: "#b5abde", colError: "#d08c86" })
    readonly property var rounding: ({ small: 6, large: 12 })
    readonly property var sizes: ({ barHeight: 40 })
    readonly property var font: ({ pixelSize: { huge: 24, large: 20, normal: 16, small: 14 },
        variableAxes: { main: { wght: 450 } } })
}
