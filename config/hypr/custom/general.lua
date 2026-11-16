
-- The shell's "External" display mode turns the laptop panel off. Unplugging
-- that external display then leaves no screen at all, and the panel stays
-- black. When the last enabled display goes away, turn the panel back on.
local function restore_laptop_panel()
    local monitors = hl.get_monitors({ all = true })
    for _, monitor in ipairs(monitors) do
        -- FALLBACK is Hyprland's own placeholder for "no display".
        if monitor.enabled and monitor.name ~= "FALLBACK" then
            return
        end
    end
    for _, monitor in ipairs(monitors) do
        if monitor.name:match("^eDP%-") or monitor.name:match("^LVDS%-") then
            hl.monitor({ output = monitor.name, mode = "preferred", position = "auto", scale = 1, disabled = false })
        end
    end
end

hl.on("monitor.removed", function()
    -- Checked a moment later: the event fires while the display is still listed.
    hl.timer(restore_laptop_panel, { timeout = 500, type = "oneshot" })
end)
