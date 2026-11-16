# Login screen (greetd + Quickshell)

A login screen in the shell's style: greetd starts a minimal Hyprland as the
`greeter` user, which runs the Quickshell config in `system/greeter/quickshell`.
After authentication Quickshell asks greetd to launch the chosen session and
quits; Hyprland exits with it and greetd starts the session on the same VT.

| Path in repo | Installed to |
| --- | --- |
| `system/greeter/quickshell/` | `/etc/greetd/quickshell/` |
| `system/greeter/hyprland.lua` | `/etc/greetd/hyprland.lua` |
| `system/greeter/greetd/config.toml` | `/etc/greetd/config.toml` |
| `system/greeter/greetd/pam.d/greetd` | `/etc/pam.d/greetd` |

The greeter cannot read your home, so the installer snapshots into
`/etc/greetd/quickshell/theme/`: the matugen colors, Google Sans Flex, the
display name (`--name`), the shell's time format, the avatar (`--avatar`, else
`~/.face`, else SDDM's `/usr/share/sddm/faces/$USER.face.icon`) and an optional
wallpaper. Rerun it after changing any of them.

Everything is monochrome. `TimeFormat.js` is a copy of the shell's; the
contract test keeps them identical.

The shell's lock screen (`modules/ii/lock/LockSurface.qml`, Super+L) uses the
same layout and reads the display name and avatar from the snapshot above, so
both screens show the same person.

The PAM file unlocks gnome-keyring with the login password, as SDDM did.
`kb_layout` in `hyprland.lua` must match the session's layout
(`tests/test_greeter_contract.py` checks it).

## Preview (no root, no greetd)

```sh
GREETER_THEME_DIR=<theme dir> qs -p system/greeter/quickshell
```

Without greetd the screen uses a fake backend: the password `demo` succeeds.
Add `GREETER_SNAPSHOT=out.png` to render one 1920x1080 frame and exit. The theme dir has the same layout the installer writes (`colors.json`,
`user.json`, `fonts/title.ttf`, `avatar`, `wallpaper`); every file is optional.

## Install

```sh
sudo pacman -S greetd
scripts/install-greeter.sh --dry-run --name "Your Name"
scripts/install-greeter.sh --name "Your Name" [--wallpaper FILE]
```

The installer keeps the distribution's `config.toml` and `pam.d/greetd` as
`*.pre-ii` once. It does not enable greetd.

## Test on another VT before switching

With the current display manager still running:

```sh
sed 's/^vt = 1/vt = 5/' /etc/greetd/config.toml | sudo tee /etc/greetd/test-vt5.toml
sudo greetd -c /etc/greetd/test-vt5.toml
```

Check the screen on VT 5 (wrong password, power buttons hover). Do not log in
there: it would start a second session. Return with `Ctrl+Alt+F1`, stop
greetd with `Ctrl+C` and delete the test config.

## Switch and roll back

```sh
sudo systemctl disable sddm && sudo systemctl enable greetd   # takes effect on reboot
```

If the greeter does not come up, log in on a text console (`Ctrl+Alt+F3`):

```sh
sudo systemctl disable greetd && sudo systemctl enable sddm && sudo reboot
sudo mv /etc/pam.d/greetd.pre-ii /etc/pam.d/greetd   # optional: restore PAM
```

The greeter's Quickshell log is under `/run/user/<greeter uid>/quickshell/`.
