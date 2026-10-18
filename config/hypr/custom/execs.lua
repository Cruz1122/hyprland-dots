
-- User-specific startup integration for Grok Bot.  The launch-scoped rules
-- keep its warm window in a silent special workspace without affecting later
-- manual openings.
hl.on("hyprland.start", function ()
    hl.exec_cmd("$HOME/.config/quickshell/$qsConfig/scripts/grok-start-hidden.sh", {
        workspace = "special:grok-bot silent",
        no_initial_focus = true,
        focus_on_activate = false,
        suppress_event = "activate activatefocus",
    })
end)
