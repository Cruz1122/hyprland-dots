pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Look of the login screen. The greeter runs as the `greeter` user and cannot
// read the user's home, so install-greeter.sh snapshots the shell's matugen
// colors, the title font and the avatar into the theme directory. Every value
// has a fallback so a missing snapshot still renders a usable screen.
Singleton {
    id: root

    // GREETER_THEME_DIR lets the preview point at a scratch snapshot.
    readonly property string dir: Quickshell.env("GREETER_THEME_DIR") || `${Quickshell.shellDir}/theme`

    property var palette: ({})
    function pick(key, fallback) {
        return palette[key] ?? fallback;
    }

    // Same roles the shell maps from matugen (colLayer0, colOnLayer0, ...).
    // Not named on*: QML would read those as signal handlers.
    readonly property color layer0: pick("background", "#131313")
    readonly property color layer1: pick("surface_container_low", "#1b1b1b")
    readonly property color layer2: pick("surface_container", "#1f1f1f")
    readonly property color layer3: pick("surface_container_high", "#2a2a2a")
    readonly property color ink: pick("on_background", "#e2e2e2")
    readonly property color subtext: pick("on_surface_variant", "#c6c6c6")
    readonly property color outline: pick("outline_variant", "#474747")
    readonly property color primary: pick("primary", "#c6c6c6")
    readonly property color primaryInk: pick("on_primary", "#1b1b1b")
    readonly property color error: pick("error", "#ffb4ab")

    readonly property string titleFont: titleLoader.status === FontLoader.Ready ? titleLoader.name : "Google Sans Flex"
    readonly property string iconFont: "Material Symbols Rounded"

    // May not exist; the card falls back to an initial.
    readonly property string avatar: `file://${root.dir}/avatar`
    // name, displayName and the shell's timeFormat (install-greeter.sh).
    property var user: ({ name: "", displayName: "", timeFormat: "" })

    // Expressive curves and durations from the shell (Appearance.qml).
    readonly property list<real> fastSpatial: [0.42, 1.67, 0.21, 0.90, 1, 1]
    readonly property list<real> defaultSpatial: [0.38, 1.21, 0.22, 1.00, 1, 1]
    readonly property list<real> effects: [0.34, 0.80, 0.34, 1.00, 1, 1]
    readonly property int fastSpatialDuration: 350
    readonly property int defaultSpatialDuration: 500
    readonly property int effectsDuration: 200

    FontLoader {
        id: titleLoader
        source: `file://${root.dir}/fonts/title.ttf`
    }

    FileView {
        path: `${root.dir}/colors.json`
        onLoaded: {
            try {
                root.palette = JSON.parse(text());
            } catch (e) {
                console.warn(`greeter: colors.json is not valid JSON, using fallbacks: ${e}`);
            }
        }
        onLoadFailed: error => console.warn(`greeter: no color snapshot (${FileViewError.toString(error)}), using fallbacks`)
    }

    FileView {
        path: `${root.dir}/user.json`
        onLoaded: {
            try {
                root.user = JSON.parse(text());
            } catch (e) {
                console.warn(`greeter: user.json is not valid JSON: ${e}`);
            }
        }
        onLoadFailed: error => console.warn(`greeter: no user.json (${FileViewError.toString(error)})`)
    }

    // The greeter has no access to the shell's Translation service; it only
    // needs a handful of strings.
    readonly property bool spanish: Qt.locale().name.startsWith("es")
    readonly property var spanishStrings: ({
        "Incorrect password": "Contraseña incorrecta",
        "Unsupported authentication step": "Paso de autenticación no soportado",
        "greetd error: %1": "Error de greetd: %1",
        "Could not run %1 (exit %2)": "No se pudo ejecutar %1 (código %2)",
        "Password": "Contraseña",
        "Signing in": "Iniciando sesión",
        "Suspend": "Suspender",
        "Restart": "Reiniciar",
        "Shut down": "Apagar",
        "Session": "Sesión",
        "Preview: the password is \"demo\"": "Vista previa: la contraseña es \"demo\""
    })
    function tr(text) {
        return spanish ? (spanishStrings[text] ?? text) : text;
    }
}
