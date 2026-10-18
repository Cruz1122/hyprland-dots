import QtQuick
import QtTest
import "../../config/quickshell/ii/modules/ii/bar/AiQuotaPresentation.js" as Presentation

TestCase {
    name: "AiQuotaPresentation"

    function test_dialog_has_sources_before_backend_initial_frame() {
        compare(Presentation.defaultSource("cursor"), "browser-extension");
        compare(Presentation.defaultSource("zed"), "browser-extension");
        compare(Presentation.defaultSource("antigravity"), "agy-cli");
        compare(Presentation.defaultSource("claude"), "claude-statusline");
        compare(Presentation.defaultSource("codex"), "opencode-bridge");
        compare(Presentation.defaultSource("unknown"), "");
    }

    function test_authorization_url_allowlist() {
        verify(Presentation.authorizationUrlAllowed("https://auth.openai.com/oauth/authorize?state=test"));
        for (const url of ["http://auth.openai.com/oauth/authorize", "https://auth.openai.com.evil.invalid/oauth/authorize",
            "https://auth.openai.com@evil.invalid/oauth/authorize", "file:///tmp/login", "https://auth.openai.com/oauth/authorize#x"])
            verify(!Presentation.authorizationUrlAllowed(url));
        verify(Presentation.authorizationUrlAllowed("https://accounts.google.com/o/oauth2/v2/auth?state=test", "antigravity"));
        verify(Presentation.authorizationUrlAllowed("https://claude.ai/oauth/authorize?state=test", "claude"));
        verify(!Presentation.authorizationUrlAllowed("https://accounts.google.com.evil.invalid/o/oauth2/auth", "antigravity"));
        verify(!Presentation.authorizationUrlAllowed("https://evil.invalid/oauth/authorize", "claude"));
    }

    function test_late_backend_frame_does_not_acknowledge_selection() {
        const pending = { accountId: "B", generation: 4 };
        verify(!Presentation.selectionAcknowledged(pending, "A", { generation: 3 }));
        verify(!Presentation.selectionAcknowledged(pending, "B", { generation: 3 }));
        verify(!Presentation.selectionAcknowledged(pending, "B", null));
        verify(Presentation.selectionAcknowledged(pending, "B", { generation: 4 }));
        verify(Presentation.selectionAcknowledged(pending, "B", { generation: 5 }));
    }

    function test_disabling_requires_generation_acknowledgement() {
        const pending = { accountId: null, generation: 2 };
        verify(!Presentation.selectionAcknowledged(pending, null, { generation: 1 }));
        verify(Presentation.selectionAcknowledged(pending, null, { generation: 2 }));
    }

    function test_emblem_hover_hides_resource_popup() {
        // The quota hover tooltip was removed, so resource hover only needs to
        // yield while the emblem itself is hovered.
        verify(Presentation.resourceHovered(true, false));
        verify(!Presentation.resourceHovered(true, true));
        verify(!Presentation.resourceHovered(false, false));
        verify(!Presentation.resourceHovered(false, true));
    }

    function test_connected_requires_a_bound_account() {
        verify(!Presentation.connected(null));
        verify(!Presentation.connected({ status: "unconfigured", windows: [] }));
        verify(!Presentation.connected({ accountId: null }));
        verify(!Presentation.connected({ accountId: "" }));
        verify(Presentation.connected({ accountId: "account-1" }));
    }

    function test_remaining_percent_from_used_percent() {
        compare(Presentation.remainingPercent({ usedPercent: 0 }), 100);
        compare(Presentation.remainingPercent({ usedPercent: 25 }), 75);
        compare(Presentation.remainingPercent({ usedPercent: 100 }), 0);
        compare(Presentation.remainingPercent({ usedPercent: 140 }), 0);
        compare(Presentation.remainingPercent({ usedPercent: -10 }), 100);
        compare(Presentation.remainingPercent(null), null);
    }

    function test_remaining_percent_from_amounts_or_unknown() {
        compare(Presentation.remainingPercent({ usedAmount: 2, limitAmount: 10 }), 80);
        compare(Presentation.remainingPercent({ usedAmount: 0, limitAmount: 0 }), null);
        compare(Presentation.remainingPercent({ usedAmount: null, limitAmount: 10 }), null);
        compare(Presentation.remainingPercent({}), null);
    }

    function test_reset_countdown_is_relative_and_never_absent_instants() {
        const now = Date.parse("2026-10-18T12:00:00Z");
        compare(Presentation.resetCountdown("2026-10-18T12:30:00Z", now), "Faltan 30 min");
        compare(Presentation.resetCountdown("2026-10-18T12:01:00Z", now), "Falta 1 min");
        compare(Presentation.resetCountdown("2026-10-18T13:00:00Z", now), "Falta 1 hora");
        compare(Presentation.resetCountdown("2026-10-18T14:00:00Z", now), "Faltan 2 horas");
        compare(Presentation.resetCountdown("2026-10-19T12:00:00Z", now), "Falta 1 día");
        compare(Presentation.resetCountdown("2026-10-20T12:00:00Z", now), "Faltan 2 días");
        compare(Presentation.resetCountdown("2026-10-18T11:00:00Z", now), "Se reinicia ahora");
        compare(Presentation.resetCountdown(null, now), null);
        compare(Presentation.resetCountdown("not-a-date", now), null);
    }

    function test_only_more_than_two_windows_use_two_columns() {
        compare(Presentation.windowColumns(0), 1);
        compare(Presentation.windowColumns(1), 1);
        compare(Presentation.windowColumns(2), 1);
        compare(Presentation.windowColumns(3), 2);
        compare(Presentation.windowColumns(6), 2);
    }

    function test_odd_trailing_window_spans_the_full_row() {
        // Three windows in two columns: index 2 (last) spans.
        verify(Presentation.spansFullRow(2, 3, 2));
        verify(!Presentation.spansFullRow(0, 3, 2));
        verify(!Presentation.spansFullRow(1, 3, 2));
        // Five windows: only the last one spans.
        verify(Presentation.spansFullRow(4, 5, 2));
        verify(!Presentation.spansFullRow(3, 5, 2));
        // Even counts and single-column layouts never span.
        verify(!Presentation.spansFullRow(3, 4, 2));
        verify(!Presentation.spansFullRow(0, 3, 1));
    }
}
