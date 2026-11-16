.pragma library

// Clock text of services/DateTime.qml (time.format and time.secondPrecision).
// Greeter copy of config/quickshell/ii/modules/common/functions/TimeFormat.js;
// keep the two identical (tests/test_greeter_contract.py checks it).
//
// "Show seconds" puts ":ss" right after the minutes of any format, so the
// 24-hour "hh:mm" becomes "hh:mm:ss" and "h:mm ap" becomes "h:mm:ss ap".
// While the screen is locked the lock screen has always shown seconds in the
// "h:mm" format only, whatever the setting; that rule is kept as it was.
//
// "h:mm" is a 12-hour clock without an am/pm marker. Qt reads "h" as 24-hour
// when the format has no AP, so that one format is built by hand.

var TWELVE_HOUR_PLAIN = "h:mm";

function secondsShown(format, secondPrecision, locked) {
    return secondPrecision === true || (locked === true && format === TWELVE_HOUR_PLAIN);
}

// Qt date format with ":ss" after its first minute field ("m" or "mm"); a "."
// in front of the minutes is reused ("HH.mm" gives "HH.mm.ss"). Text in single
// quotes is literal (a doubled '' is a quote). A format that already has
// seconds, or has no minutes, is returned unchanged.
function withSeconds(format) {
    var text = String(format ?? "");
    var quoted = false;
    var minuteEnd = -1;
    var separator = ":";
    for (var i = 0; i < text.length; i++) {
        var c = text[i];
        if (c === "'") {
            quoted = !quoted;
            continue;
        }
        if (quoted)
            continue;
        if (c === "s")
            return text;
        if (c === "m" && minuteEnd < 0) {
            var end = i;
            while (end < text.length && text[end] === "m")
                end++;
            minuteEnd = end;
            if (i > 0 && text[i - 1] === ".")
                separator = ".";
            i = end - 1;
        }
    }
    if (minuteEnd < 0)
        return text;
    return text.slice(0, minuteEnd) + separator + "ss" + text.slice(minuteEnd);
}

function pad2(value) {
    return String(value).padStart(2, "0");
}

// formatter(date, qtFormat) renders a Qt format, e.g. Qt.locale().toString.
function formatTime(date, format, secondPrecision, locked, formatter) {
    var fmt = String(format ?? "");
    var seconds = secondsShown(fmt, secondPrecision, locked);
    if (fmt === TWELVE_HOUR_PLAIN) {
        var hours = date.getHours() % 12;
        if (hours === 0)
            hours = 12;
        var text = hours + ":" + pad2(date.getMinutes());
        if (seconds)
            text += ":" + pad2(date.getSeconds());
        return text;
    }
    return formatter(date, seconds ? withSeconds(fmt) : fmt);
}
