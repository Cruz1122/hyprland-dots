import QtQuick
import QtTest
import "../../config/quickshell/ii/modules/common/functions/TimeFormat.js" as TimeFormat

// Clock text of services/DateTime.qml: time.format with time.secondPrecision
// ("Show seconds") and the lock screen rule.
TestCase {
    name: "TimeFormat"

    // 14:05:09, a time where 12-hour, 24-hour and seconds all differ.
    readonly property var afternoon: new Date(2026, 10, 8, 14, 5, 9)
    readonly property var midnight: new Date(2026, 10, 8, 0, 7, 3)

    function cFormat(date, format) {
        return Qt.locale("C").toString(date, format);
    }

    function text(date, format, secondPrecision, locked) {
        return TimeFormat.formatTime(date, format, secondPrecision, locked, cFormat);
    }

    function test_with_seconds_goes_right_after_the_minutes() {
        compare(TimeFormat.withSeconds("hh:mm"), "hh:mm:ss");
        compare(TimeFormat.withSeconds("h:mm"), "h:mm:ss");
        compare(TimeFormat.withSeconds("h:mm ap"), "h:mm:ss ap");
        compare(TimeFormat.withSeconds("h:mm AP"), "h:mm:ss AP");
        compare(TimeFormat.withSeconds("HH.mm 'Uhr'"), "HH.mm.ss 'Uhr'");
        compare(TimeFormat.withSeconds("h:m"), "h:m:ss");
    }

    function test_with_seconds_skips_quotes_existing_seconds_and_no_minutes() {
        compare(TimeFormat.withSeconds("'mm' hh:mm"), "'mm' hh:mm:ss");
        compare(TimeFormat.withSeconds("'it''s' hh:mm"), "'it''s' hh:mm:ss");
        compare(TimeFormat.withSeconds("hh:mm:ss"), "hh:mm:ss");
        compare(TimeFormat.withSeconds("hh 'sharp'"), "hh 'sharp'");
        compare(TimeFormat.withSeconds("hh"), "hh");
        compare(TimeFormat.withSeconds(""), "");
        compare(TimeFormat.withSeconds(undefined), "");
    }

    function test_show_seconds_off_changes_nothing() {
        compare(text(afternoon, "hh:mm", false, false), "14:05");
        compare(text(afternoon, "h:mm", false, false), "2:05");
        compare(text(afternoon, "h:mm ap", false, false), "2:05 pm");
        compare(text(afternoon, "h:mm AP", false, false), "2:05 PM");
        compare(text(midnight, "h:mm", false, false), "12:07");
    }

    function test_show_seconds_on_adds_seconds_to_every_format() {
        compare(text(afternoon, "hh:mm", true, false), "14:05:09");
        compare(text(afternoon, "h:mm", true, false), "2:05:09");
        compare(text(afternoon, "h:mm ap", true, false), "2:05:09 pm");
        compare(text(afternoon, "h:mm AP", true, false), "2:05:09 PM");
        compare(text(afternoon, "HH.mm 'Uhr'", true, false), "14.05.09 Uhr");
        compare(text(midnight, "h:mm", true, false), "12:07:03");
    }

    function test_locked_screen_keeps_its_old_rule() {
        // Seconds only in the plain 12-hour format while locked, as before.
        compare(text(afternoon, "h:mm", false, true), "2:05:09");
        compare(text(afternoon, "hh:mm", false, true), "14:05");
        compare(text(afternoon, "h:mm ap", false, true), "2:05 pm");
        compare(text(afternoon, "hh:mm", true, true), "14:05:09");
        verify(TimeFormat.secondsShown("h:mm", false, true));
        verify(!TimeFormat.secondsShown("hh:mm", false, true));
        verify(TimeFormat.secondsShown("hh:mm", true, false));
        verify(!TimeFormat.secondsShown("h:mm", false, false));
    }
}
