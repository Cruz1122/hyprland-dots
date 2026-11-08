import QtQuick
import QtTest
import "../../config/quickshell/ii/modules/common/functions/MotionScale.js" as MotionScale

// Pure cases of the shell motion helper (contracts phase A, section 6).
TestCase {
    name: "MotionScale"

    function test_factor_follows_scale() {
        compare(MotionScale.factor(1, false), 1);
        compare(MotionScale.factor(0.5, false), 0.5);
        compare(MotionScale.factor(2, false), 2);
    }

    function test_factor_clamps_to_quarter_and_three() {
        compare(MotionScale.factor(0.1, false), 0.25);
        compare(MotionScale.factor(0, false), 0.25);
        compare(MotionScale.factor(-4, false), 0.25);
        compare(MotionScale.factor(3, false), 3);
        compare(MotionScale.factor(10, false), 3);
        compare(MotionScale.factor(Infinity, false), 1);
    }

    function test_factor_ignores_malformed_scale() {
        compare(MotionScale.factor(undefined, false), 1);
        compare(MotionScale.factor(null, false), 1);
        compare(MotionScale.factor("", false), 1);
        compare(MotionScale.factor("fast", false), 1);
        compare(MotionScale.factor(NaN, false), 1);
        compare(MotionScale.factor("0.5", false), 0.5);
    }

    function test_reduce_wins_over_scale() {
        compare(MotionScale.factor(0.5, true), 0);
        compare(MotionScale.factor(2, true), 0);
        compare(MotionScale.factor(undefined, true), 0);
        // Only a real boolean true reduces motion.
        compare(MotionScale.factor(1, "true"), 1);
        compare(MotionScale.factor(1, undefined), 1);
    }

    function test_duration_scales_and_rounds() {
        compare(MotionScale.duration(500, 1), 500);
        compare(MotionScale.duration(500, 0.5), 250);
        compare(MotionScale.duration(350, 0.75), 263); // 262.5 rounds up
        compare(MotionScale.duration(200, 1.5), 300);
        compare(MotionScale.duration(333, 0.25), 83); // 83.25
        compare(MotionScale.duration(500, 3), 1500);
    }

    function test_duration_floor_is_one_ms() {
        compare(MotionScale.duration(500, 0), 1);
        compare(MotionScale.duration(1, 0.25), 1);
        compare(MotionScale.duration(0.2, 1), 1);
    }

    function test_duration_keeps_zero_negative_and_infinite() {
        compare(MotionScale.duration(0, 0.5), 0);
        compare(MotionScale.duration(0, 0), 0);
        compare(MotionScale.duration(-1, 0.5), -1);
        compare(MotionScale.duration(-1, 0), -1);
        compare(MotionScale.duration(Infinity, 0.5), Infinity);
        verify(isNaN(MotionScale.duration(NaN, 0.5)));
    }

    function test_velocity_is_divided_by_factor() {
        compare(MotionScale.velocity(650, 1), 650);
        compare(MotionScale.velocity(650, 0.5), 1300);
        compare(MotionScale.velocity(850, 2), 425);
        compare(MotionScale.velocity(650, 0), 1e6);
        compare(MotionScale.velocity(650, -1), 1e6);
    }

    function test_interval_follows_duration_rule() {
        compare(MotionScale.interval(200, 0.5), 100);
        compare(MotionScale.interval(250, 0), 1);
        compare(MotionScale.interval(0, 0.5), 0);
    }

    function test_reduce_end_to_end() {
        const f = MotionScale.factor(1, true);
        compare(MotionScale.duration(500, f), 1);
        compare(MotionScale.duration(200, f), 1);
        compare(MotionScale.velocity(650, f), 1e6);
    }
}
