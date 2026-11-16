hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Edit user keybinds"} )
hl.bind("SUPER + SHIFT + Z", hl.dsp.global("quickshell:regionQr"), {description = "Utilities: Scan QR and open link"})
hl.bind("SUPER + ALT + G", hl.dsp.exec_cmd("$HOME/.config/quickshell/$qsConfig/scripts/grok-open-bot.sh --focus"),
    {description = "Grok Bot: Open or focus"})
hl.bind("SUPER + ALT + D", hl.dsp.global("quickshell:dictationToggle"), {description = "Shell: Dictate (press again to finish)"})
