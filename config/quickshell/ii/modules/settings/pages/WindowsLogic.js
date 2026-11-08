.pragma library

// Pure helpers of WindowsPage.qml.

// Setting key of the row that contains `item` (objectName "row:<key>"), or "".
function rowKeyOf(item) {
    for (var p = item; p; p = p.parent) {
        var name = String(p.objectName || "");
        if (name.indexOf("row:") === 0)
            return name.slice(4);
    }
    return "";
}

// Hovered key after the row of `key` reports `hovered`: entering a row makes it
// the hovered one; leaving it clears the key only if that row still owns it,
// so leaving row A after entering row B keeps B.
function nextHoveredKey(current, key, hovered) {
    if (hovered)
        return key;
    return current === key ? "" : current;
}
