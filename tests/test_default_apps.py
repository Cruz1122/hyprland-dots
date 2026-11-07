from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/settings/default-apps.py"
FIXTURES = ROOT / "tests/fixtures/default-apps"


class DefaultAppsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        shutil.copytree(FIXTURES / "data-user", self.root / "data-home")
        shutil.copytree(FIXTURES / "data-sys", self.root / "share")
        self.config = self.root / "config"
        self.config.mkdir()
        (self.root / "etc").mkdir()
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        fake = bin_dir / "fakeapp"
        fake.write_text("#!/bin/sh\n")
        fake.chmod(0o755)
        self.env = {
            "HOME": str(self.root),
            "PATH": str(bin_dir),
            "XDG_DATA_HOME": str(self.root / "data-home"),
            "XDG_DATA_DIRS": str(self.root / "share"),
            "XDG_CONFIG_HOME": str(self.config),
            "XDG_CONFIG_DIRS": str(self.root / "etc"),
            "XDG_CURRENT_DESKTOP": "Hyprland",
            "LANG": "es_CO.UTF-8",
        }

    def tearDown(self):
        self.temp.cleanup()

    def run_cli(self, *args, **env):
        return subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True, text=True,
                              env={**self.env, **env}, timeout=30)

    def roles(self, **env):
        result = self.run_cli("list", "--json", **env)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)["roles"]

    def mimeapps(self, text, name="mimeapps.list", directory=None):
        path = (directory or self.config) / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def ids(self, role):
        return [c["id"] for c in role["candidates"]]

    def test_list_reports_every_role_with_candidates(self):
        roles = self.roles()
        self.assertEqual(list(roles), ["browser", "fileManager", "mail", "image", "video", "audio", "text", "pdf"])
        browser = {c["id"]: c for c in roles["browser"]["candidates"]}
        self.assertTrue(browser["firefox.desktop"]["handlesAll"])
        self.assertFalse(browser["chromium.desktop"]["handlesAll"])
        self.assertEqual(browser["firefox.desktop"]["icon"], "firefox-user")
        self.assertEqual(roles["browser"]["primaryType"], "x-scheme-handler/http")
        self.assertIn("org-pdfviewer.desktop", self.ids(roles["pdf"]))
        self.assertEqual(roles["mail"]["candidates"], [])
        self.assertIsNone(roles["mail"]["current"])
        self.assertFalse(roles["mail"]["mixed"])
        self.assertFalse(next(c for c in roles["video"]["candidates"] if c["id"] == "mpv.desktop")["handlesAll"])

    def test_name_localization_falls_back(self):
        def name(**env):
            return next(c["name"] for c in self.roles(**env)["image"]["candidates"] if c["id"] == "imv.desktop")
        self.assertEqual(name(), "Visor (Colombia)")
        self.assertEqual(name(LANG="es_MX.UTF-8"), "Visor de imágenes")
        self.assertEqual(name(LANG="de_DE.UTF-8"), "Image Viewer")
        self.assertEqual(name(LANG="C"), "Image Viewer")
        self.assertEqual(name(LC_ALL="es_MX.UTF-8", LANG="de_DE.UTF-8"), "Visor de imágenes")

    def test_data_home_entry_shadows_system_entry(self):
        browser = self.roles()["browser"]
        names = [c["name"] for c in browser["candidates"] if c["id"] == "firefox.desktop"]
        self.assertEqual(names, ["Firefox (user)"])

    def test_hidden_entry_masks_lower_entry_and_invalid_default(self):
        self.mimeapps("[Default Applications]\nx-scheme-handler/http=oldbrowser.desktop;chromium.desktop;\n")
        browser = self.roles()["browser"]
        self.assertNotIn("oldbrowser.desktop", self.ids(browser))
        self.assertEqual(browser["current"], "chromium.desktop")
        self.assertTrue(browser["explicit"])

    def test_visibility_rules_filter_candidates(self):
        self.assertEqual(sorted(self.ids(self.roles()["text"])), ["editor.desktop", "tryexec-present.desktop"])
        gnome = self.ids(self.roles(XDG_CURRENT_DESKTOP="GNOME")["text"])
        self.assertIn("gnome-only.desktop", gnome)
        self.assertIn("not-hyprland.desktop", gnome)

    def test_config_precedence_and_desktop_specific_file(self):
        self.mimeapps("[Default Applications]\ntext/plain=nodisplay.desktop;\n",
                      directory=self.root / "data-home/applications")
        self.assertEqual(self.roles()["text"]["current"], "nodisplay.desktop")
        self.mimeapps("[Default Applications]\ntext/plain=tryexec-present.desktop;\n", directory=self.root / "etc")
        self.assertEqual(self.roles()["text"]["current"], "tryexec-present.desktop")
        self.mimeapps("[Default Applications]\ntext/plain=tryexec-present.desktop;\n")
        self.mimeapps("[Default Applications]\ntext/plain=editor.desktop;\n", name="hyprland-mimeapps.list")
        text = self.roles()["text"]
        self.assertEqual(text["current"], "editor.desktop")
        self.assertEqual(text["currentName"], "Text Editor")
        self.assertEqual(self.roles(XDG_CURRENT_DESKTOP="GNOME")["text"]["current"], "tryexec-present.desktop")

    def test_mixed_detection(self):
        self.mimeapps("[Default Applications]\nimage/png=imv.desktop;\nimage/jpeg=viewer2.desktop;\n")
        image = self.roles()["image"]
        self.assertEqual(image["current"], "imv.desktop")
        self.assertTrue(image["mixed"])
        self.assertEqual(image["defaults"]["image/jpeg"], "viewer2.desktop")

    def test_association_fallback_without_defaults(self):
        pdf = self.roles()["pdf"]
        self.assertEqual(pdf["current"], "org-pdfviewer.desktop")
        self.assertFalse(pdf["explicit"])
        self.mimeapps("[Added Associations]\nx-scheme-handler/http=chromium.desktop;\n"
                      "[Removed Associations]\ntext/plain=editor.desktop;\n")
        roles = self.roles()
        self.assertEqual(roles["browser"]["current"], "chromium.desktop")
        self.assertNotEqual(roles["text"]["current"], "editor.desktop")

    def test_set_preserves_other_content_and_mode(self):
        original = ("# user comment\n[Added Associations]\ntext/html=chromium.desktop;\n\n"
                    "[Default Applications]\nx-scheme-handler/http=chromium.desktop;\n"
                    "image/png=imv.desktop;\nx-scheme-handler/http=duplicate.desktop;\n\n"
                    "[Removed Associations]\n# keep me\naudio/flac=mpv.desktop;\n")
        path = self.mimeapps(original)
        path.chmod(0o600)
        result = self.run_cli("set", "browser", "firefox.desktop")
        self.assertEqual(result.returncode, 0, result.stderr)
        output = json.loads(result.stdout)
        self.assertEqual(output["written"], [str(path)])
        self.assertEqual(output["role"]["current"], "firefox.desktop")
        self.assertFalse(output["role"]["mixed"])
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        self.assertEqual(path.read_text(), (
            "# user comment\n[Added Associations]\ntext/html=chromium.desktop;\n\n"
            "[Default Applications]\nx-scheme-handler/http=firefox.desktop;\n"
            "image/png=imv.desktop;\nx-scheme-handler/https=firefox.desktop;\ntext/html=firefox.desktop;\n\n"
            "[Removed Associations]\n# keep me\naudio/flac=mpv.desktop;\n"))
        self.assertEqual(list(self.config.iterdir()), [path])

    def test_set_creates_file_and_updates_shadowing_desktop_file(self):
        shadow = self.mimeapps("[Default Applications]\nimage/png=viewer2.desktop;\n", name="hyprland-mimeapps.list")
        result = self.run_cli("set", "image", "imv.desktop")
        self.assertEqual(result.returncode, 0, result.stderr)
        image = json.loads(result.stdout)["role"]
        self.assertEqual(image["current"], "imv.desktop")
        self.assertFalse(image["mixed"])
        self.assertEqual(shadow.read_text(), "[Default Applications]\nimage/png=imv.desktop;\n")
        written = (self.config / "mimeapps.list").read_text()
        self.assertTrue(written.startswith("[Default Applications]\nimage/png=imv.desktop;\n"))
        self.assertIn("image/tiff=imv.desktop;\n", written)

    def test_set_only_claims_types_the_app_declares(self):
        # chromium declares http and https but not text/html.
        path = self.mimeapps("[Default Applications]\ntext/html=firefox.desktop;\n")
        result = self.run_cli("set", "browser", "chromium.desktop")
        self.assertEqual(result.returncode, 0, result.stderr)
        browser = json.loads(result.stdout)["role"]
        self.assertEqual(browser["current"], "chromium.desktop")
        self.assertEqual(browser["defaults"]["text/html"], "firefox.desktop")
        self.assertTrue(browser["mixed"])
        self.assertEqual(path.read_text(), "[Default Applications]\ntext/html=firefox.desktop;\n"
                                           "x-scheme-handler/http=chromium.desktop;\n"
                                           "x-scheme-handler/https=chromium.desktop;\n")

    def test_candidates_must_open_the_primary_type(self):
        # viewer2 declares image/jpeg only; the image role shows image/png.
        self.assertNotIn("viewer2.desktop", self.ids(self.roles()["image"]))
        path = self.mimeapps("[Default Applications]\n")
        result = self.run_cli("set", "image", "viewer2.desktop")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(path.read_text(), "[Default Applications]\n")

    def test_set_writes_through_symlink(self):
        real = self.root / "dotfiles/mimeapps.list"
        real.parent.mkdir()
        real.write_text("[Default Applications]\n")
        (self.config / "mimeapps.list").symlink_to(real)
        result = self.run_cli("set", "pdf", "org-pdfviewer.desktop")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.config / "mimeapps.list").is_symlink())
        self.assertEqual(real.read_text(), "[Default Applications]\napplication/pdf=org-pdfviewer.desktop;\n")

    def test_set_rejects_invalid_input_without_writing(self):
        path = self.mimeapps("[Default Applications]\n")
        cases = [("set", "nope", "firefox.desktop"), ("set", "browser", "missing.desktop"),
                 ("set", "browser", "oldbrowser.desktop"), ("set", "text", "nodisplay.desktop"),
                 ("set", "browser", "imv.desktop"), ("set", "browser"), ("frobnicate",)]
        for args in cases:
            with self.subTest(args=args):
                result = self.run_cli(*args)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, "")
                self.assertTrue(result.stderr)
        self.assertEqual(path.read_text(), "[Default Applications]\n")

    def test_set_reports_io_error(self):
        blocker = self.root / "not-a-dir"
        blocker.write_text("")
        result = self.run_cli("set", "pdf", "org-pdfviewer.desktop", XDG_CONFIG_HOME=str(blocker))
        self.assertEqual(result.returncode, 1)
        self.assertIn("error", result.stderr)

    def test_malformed_inputs_are_skipped_with_warnings(self):
        (self.root / "share/applications/bad-bytes.desktop").write_bytes(
            b"[Desktop Entry]\nType=Application\nName=\xff\xfe\nMimeType=text/plain;\n")
        (self.root / "share/applications/no-name.desktop").write_text(
            "[Desktop Entry]\nType=Application\nMimeType=text/plain;\n")
        self.mimeapps("garbage before group\n[Default Applications]\nnot a pair\ntext/plain=editor.desktop;\n")
        (self.root / "etc/mimeapps.list").write_bytes(b"[Default Applications]\nimage/png=\xff;\n")
        result = self.run_cli("list", "--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        roles = json.loads(result.stdout)["roles"]
        self.assertEqual(roles["text"]["current"], "editor.desktop")
        self.assertNotIn("bad-bytes.desktop", self.ids(roles["text"]))
        self.assertNotIn("no-name.desktop", self.ids(roles["text"]))
        for needle in ("bad-bytes.desktop", "no-name.desktop", "no-group.desktop", "editor.desktop:",
                       "malformed line", "etc/mimeapps.list"):
            self.assertIn(needle, result.stderr)

    def test_set_preserves_undecodable_bytes(self):
        path = self.config / "mimeapps.list"
        path.write_bytes(b"# caf\xe9\n[Default Applications]\n")
        result = self.run_cli("set", "pdf", "org-pdfviewer.desktop")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(path.read_bytes(),
                         b"# caf\xe9\n[Default Applications]\napplication/pdf=org-pdfviewer.desktop;\n")


if __name__ == "__main__":
    unittest.main()
