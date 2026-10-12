# hyprland-dots

Cruz1122's Hyprland + Quickshell desktop, customized from
[illogical-impulse](https://github.com/end-4/dots-hyprland).

This repository brings together the live desktop customizations and the
previous local development work. It is a maintained source copy, not an
upstream installer that replaces the desktop with stock dots.

## What's here

- Customized top bar, clock, battery indicators and utility buttons.
- Left sidebar with persistent notes, media controls and desktop actions.
- Settings UI, recording controls, microphone selection and QR capture.
- Authentication/display-control components and supporting Python scripts.
- Hyprland configuration, app theming templates and a portable wallpaper.
- Safe capture/install tooling and a pinned Quickshell recipe with the Qt 6.12 fix.

## Install

**Target: Arch Linux / CachyOS, x86-64, Hyprland 0.56+.** Start with an installed
OS, internet access and a normal user with sudo. Other distributions are not
supported. Fresh-machine end-to-end validation is still pending.

```bash
sudo pacman -Syu --needed git python
git clone https://github.com/Cruz1122/hyprland-dots.git
cd hyprland-dots
./install.sh
```

The installer shows the scope and asks before proceeding. It prepares packages
and the Python environment, then copies configuration. AUR/package managers
may ask additional review questions and the initial build takes time.

It backs up current config privately, **never deletes extra files**, preserves
existing `hypr/custom/` and settings by default, and does not restart your
session or automatically restore an old snapshot. GPU drivers, display manager
and optional privileged device services remain under your control.

Preview without changing anything:

```bash
./install.sh --dry-run
```

See [installation and maintenance](docs/installation.md) for options, optional
device setup, backup verification, compatibility checks and limitations.

## Keep your changes

- `config/` is the versioned desktop source; installation makes regular copies.
- `packaging/` contains dependency recipes, not generated packages.
- `scripts/` contains capture, installation, rebuild and verification tools.
- `tests/` checks contracts and filesystem safety in temporary environments.
- `docs/` records installation, provenance and settings contracts.

If you edit files directly under `~/.config`, capture them before any deployment:

```bash
python3 scripts/dotsctl.py capture --dry-run
python3 scripts/dotsctl.py capture --yes
git diff
```

Capture saves the previous repo configuration, takes live files at conflicting
paths and preserves repo-only work. **Review the diff before committing**:
capture replaces home paths with placeholders but is not a secret scrubber.
Never publish API keys, keyrings, notes, chats or authenticator state.

## Qt updates

```bash
quickshell --private-check-compat
bash scripts/rebuild-quickshell.sh
```

The rebuild script prints the package installation command; it does not install
the package or stop the running shell. Configuration and binary updates are
separate operations.

## Development checks

Python 3.12+ and the test dependencies are required. On Arch/CachyOS they are
installed with the desktop dependencies. Otherwise use an isolated environment:

```bash
python3 -m venv .venv
.venv/bin/pip install -r tests/requirements.txt
```

```bash
env PATH="$PWD/.venv/bin:$PATH" bash scripts/verify.sh
```

Checks do not need a live desktop or a previous user's backup. Visual/hardware
validation is separate; a passing test suite is not a guarantee for every PC.

## Credits and license

Based on end-4's illogical-impulse/dots-hyprland and its contributors, with local
modifications by Cruz1122. See [provenance](docs/provenance.md),
[package sources](packaging/README.md) and [GPL-3.0](LICENSE).
Third-party assets and dependency sources retain their own notices/licenses.
Quickshell is separately licensed LGPL-3.0; build sources are linked in its
recipe. Fonts are installed from their source repositories, not bundled here.

The public repository starts from a sanitized baseline. The original local
repository and its seven development commits are retained privately rather
than publishing historical personal paths and downloaded-video thumbnails.
