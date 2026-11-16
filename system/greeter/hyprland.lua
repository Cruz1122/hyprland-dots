-- Minimal compositor for the login screen. greetd runs it as the `greeter`
-- user (see greetd/config.toml); it only hosts the Quickshell greeter.

-- The greeter user's home is / and not writable: keep Quickshell's and
-- Hyprland's cache and state in the per-login runtime directory.
local runtime = os.getenv("XDG_RUNTIME_DIR") or "/tmp"
hl.env("XDG_CACHE_HOME", runtime .. "/cache")
hl.env("XDG_STATE_HOME", runtime .. "/state")
hl.env("XDG_DATA_HOME", runtime .. "/data")

hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = 1
})

hl.config({
    input = {
        -- Keep in sync with config/hypr/hyprland/general.lua, or the password
        -- typed here will not match the one typed in the session.
        kb_layout = "latam",
        numlock_by_default = true,
        repeat_delay = 250,
        repeat_rate = 35
    },
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        background_color = "rgb(131313)"
    }
})

hl.on("hyprland.start", function()
    hl.exec_cmd("hyprctl setcursor Bibata-Modern-Classic 24")
    -- The compositor lives exactly as long as the greeter: when Quickshell
    -- quits after handing the session to greetd (or crashes), Hyprland exits
    -- and greetd starts the user session or restarts the greeter.
    hl.exec_cmd("sh -c 'qs -p /etc/greetd/quickshell; hyprctl dispatch \"hl.dsp.exit()\"'")
end)
