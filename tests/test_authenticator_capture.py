"""QR capture helper tests with synthetic images and stubbed image/QR tools."""
from __future__ import annotations

import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "config/quickshell/ii/scripts/authenticator-capture-qr.sh"
PARSER = ROOT / "config/quickshell/ii/scripts/authenticator.py"
PYTHON = Path("/usr/bin/python")
IMAGE_HELPER = ROOT / "config/quickshell/ii/scripts/authenticator-open-image-qr.sh"
BACKUP_HELPER = ROOT / "config/quickshell/ii/scripts/authenticator-read-backup.sh"


class AuthenticatorCaptureTest(unittest.TestCase):
    def invoke(self, qr_text: str | None, dimensions: tuple[str, str, str, str] = ("2", "3", "40", "40"),
               soft_edges: bool = False) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory(prefix="authenticator-qr-fixture-") as temporary:
            root = Path(temporary)
            image = root / "synthetic-screen.png"
            image.write_bytes(b"synthetic fixture only; no real screen capture")
            bin_dir = root / "bin"
            bin_dir.mkdir()
            magick = bin_dir / "magick"
            magick.write_text("#!/usr/bin/python\nimport pathlib, sys\npathlib.Path(sys.argv[-1]).write_bytes(b'synthetic-crop')\n")
            magick.chmod(0o755)
            zbar = bin_dir / "zbarimg"
            if qr_text is None:
                zbar.write_text("#!/usr/bin/python\nraise SystemExit(4)\n")
            elif soft_edges:
                # Simulates a scaled screen capture: the direct scan fails once,
                # and the binarized retry (second invocation) succeeds.
                zbar.write_text(
                    "#!/usr/bin/python\n"
                    "import os, pathlib, sys\n"
                    "marker = pathlib.Path(os.environ['AUTHENTICATOR_TEST_MARKER'])\n"
                    "if not marker.exists():\n"
                    "    marker.write_text('attempted')\n"
                    "    raise SystemExit(4)\n"
                    "sys.stdout.write(os.environ['AUTHENTICATOR_TEST_QR'] + '\\n')\n"
                )
            else:
                zbar.write_text("#!/usr/bin/python\nimport os, sys\nsys.stdout.write(os.environ['AUTHENTICATOR_TEST_QR'] + '\\n')\n")
            zbar.chmod(0o755)
            environment = {
                **os.environ,
                "PATH": str(bin_dir) + os.pathsep + os.defpath,
                "TMPDIR": str(root),
                "AUTHENTICATOR_TEST_QR": qr_text or "",
                "AUTHENTICATOR_TEST_MARKER": str(root / "attempt-marker"),
            }
            result = subprocess.run(
                ["/usr/bin/bash", str(SCRIPT), str(image), str(PYTHON), str(PARSER), *dimensions],
                env=environment, capture_output=True, text=True, timeout=15,
            )
            self.assertTrue(image.exists(), "the scanner must not unlink an arbitrary source path")
            self.assertEqual(list(root.glob("illogical-authenticator-qr.*.png")), [])
            return result

    def test_totp_uri_is_returned_without_clipboard_or_temp_image(self) -> None:
        uri = "otpauth://totp/Fixture%3Ademo?secret=JBSWY3DPEHPK3PXP&issuer=Fixture"
        result = self.invoke(uri)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), uri)
        self.assertEqual(result.stderr, "")

    def test_google_migration_qr_returns_validated_account_batch(self) -> None:
        uri = ("otpauth-migration://offline?data="
               "CjgKFDEyMzQ1Njc4OTAxMjM0NTY3ODkwEhFhbGljZUBleGFtcGxlLmNvbRoHRXhhbXBsZSABKAEwAgo2ChQxMjM0NTY3ODkwMTIzNDU2Nzg5MBIPYm9iQGV4YW1wbGUubmV0GgdFeGFtcGxlIAIoAjACEAEYASAAKCo=")
        result = self.invoke(uri)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertTrue(result.stdout.startswith("[{"))
        self.assertIn('"account": "alice@example.com"', result.stdout)
        self.assertIn('"account": "bob@example.net"', result.stdout)

    def test_no_qr_returns_failure_and_cleans_source(self) -> None:
        result = self.invoke(None)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertEqual(result.stderr, "")

    def test_soft_edges_are_retried_with_binarization(self) -> None:
        uri = "otpauth://totp/Fixture%3Ademo?secret=JBSWY3DPEHPK3PXP&issuer=Fixture"
        result = self.invoke(uri, soft_edges=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), uri)

    def test_invalid_geometry_is_rejected(self) -> None:
        result = self.invoke("otpauth://totp/Fixture:demo?secret=JBSWY3DPEHPK3PXP",
                             ("-1", "0", "40", "40"))
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")

    def test_contract_keeps_payload_out_of_argv_clipboard_and_logs(self) -> None:
        script = SCRIPT.read_text(encoding="utf-8")
        self.assertIn('timeout 10s magick "$image"', script)
        self.assertIn('timeout 10s "$python" "$parser" qr "$crop" 2>/dev/null', script)
        self.assertIn('-auto-threshold OTSU', script)
        self.assertIn('[[ $status -eq 1 ]] || exit "$status"', script)
        self.assertIn('trap cleanup EXIT', script)
        self.assertIn('umask 077', script)
        screenshot_process = (ROOT / "config/quickshell/ii/modules/common/utils/TempScreenshotProcess.qml").read_text()
        self.assertIn('Quickshell.shellPath("scripts/authenticator-private-screenshot.sh")', screenshot_process)
        method_grid = (ROOT / "config/quickshell/ii/modules/common/authenticator/AuthenticatorMethodGrid.qml").read_text()
        self.assertIn('property bool available: root.storeReady && root.enabledMethods.indexOf(modelData.id) !== -1', method_grid)
        self.assertIn('Quickshell.screens.forEach(screen => Quickshell.execDetached(["rm", "-f", "--", `${Directories.screenshotTemp}/image-${screen.name}`]))',
                      (ROOT / "config/quickshell/ii/modules/ii/regionSelector/RegionSelector.qml").read_text())
        self.assertNotIn("wl-copy", script)
        self.assertNotIn("notify-send", script)
        self.assertNotIn("echo", script)
        self.assertNotIn("xclip", script)

    @unittest.skipUnless(shutil.which("qrencode") and shutil.which("magick") and shutil.which("zbarimg"),
                         "real image/QR tools are unavailable")
    def test_real_toolchain_scans_generated_qr_and_rejects_blank_region(self) -> None:
        uri = "otpauth://totp/Example:alice%40example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example"
        with tempfile.TemporaryDirectory(prefix="authenticator-real-qr-") as temporary:
            root = Path(temporary)
            qr = root / "synthetic-qr.png"
            subprocess.run(["qrencode", "-o", str(qr), "-s", "6", "-m", "4", uri],
                           check=True, capture_output=True)
            size = subprocess.run(["magick", "identify", "-format", "%w %h", str(qr)],
                                  check=True, capture_output=True, text=True).stdout.split()
            width, height = int(size[0]), int(size[1])
            canvas = root / "synthetic-screen.png"
            subprocess.run(["magick", "-size", "800x600", "xc:white", str(qr),
                            "-geometry", "+120+90", "-composite", str(canvas)],
                           check=True, capture_output=True)
            scanned = subprocess.run(
                ["/usr/bin/bash", str(SCRIPT), str(canvas), str(PYTHON), str(PARSER),
                 "120", "90", str(width), str(height)],
                capture_output=True, text=True, timeout=30)
            self.assertEqual(scanned.returncode, 0, scanned.stderr)
            self.assertEqual(scanned.stdout.strip(), uri)
            self.assertTrue(canvas.exists(), "the scanner must not unlink its source image")
            blank = subprocess.run(
                ["/usr/bin/bash", str(SCRIPT), str(canvas), str(PYTHON), str(PARSER),
                 "0", "0", "20", "20"],
                capture_output=True, text=True, timeout=30)
            self.assertEqual(blank.returncode, 1)
            self.assertEqual(blank.stdout, "")

    def test_private_screenshot_helper_secures_new_and_preexisting_paths(self) -> None:
        helper = ROOT / "config/quickshell/ii/scripts/authenticator-private-screenshot.sh"
        for existing in (False, True):
            with self.subTest(existing=existing), tempfile.TemporaryDirectory(prefix="authenticator-screen-") as temporary:
                root = Path(temporary)
                image = root / "image-eDP-1.png"
                if existing:
                    image.write_bytes(b"stale screenshot fixture")
                    image.chmod(0o644)
                bin_dir = root / "bin"
                bin_dir.mkdir()
                grim = bin_dir / "grim"
                grim.write_text("#!/usr/bin/python\nimport pathlib, sys\npathlib.Path(sys.argv[3]).write_bytes(b'new private screenshot')\n")
                grim.chmod(0o755)
                result = subprocess.run(
                    ["/usr/bin/bash", str(helper), "eDP-1", str(root), str(image)],
                    env={**os.environ, "PATH": str(bin_dir) + os.pathsep + os.defpath},
                    capture_output=True, text=True, timeout=5,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(stat.S_IMODE(image.stat().st_mode), 0o600)
                self.assertEqual(image.read_bytes(), b"new private screenshot")

    def test_open_image_helper_decodes_local_files_and_rejects_oversized_images(self) -> None:
        uri = "otpauth://totp/Fixture:demo?secret=JBSWY3DPEHPK3PXP&issuer=Fixture"
        with tempfile.TemporaryDirectory(prefix="authenticator-image-import-") as temporary:
            root = Path(temporary)
            image = root / "QR image with spaces.png"
            image.write_bytes(b"synthetic local image")
            bin_dir = root / "bin"
            bin_dir.mkdir()
            magick = bin_dir / "magick"
            magick.write_text(
                "#!/usr/bin/python\n"
                "import pathlib, sys\n"
                "if sys.argv[1] == 'identify': print('64 64')\n"
                "else: pathlib.Path(sys.argv[-1]).write_bytes(b'synthetic crop')\n"
            )
            magick.chmod(0o755)
            zbar = bin_dir / "zbarimg"
            zbar.write_text("#!/usr/bin/python\nimport os, sys\nsys.stdout.write(os.environ['AUTHENTICATOR_TEST_QR'] + '\\n')\n")
            zbar.chmod(0o755)
            environment = {**os.environ, "PATH": str(bin_dir) + os.pathsep + os.defpath,
                           "TMPDIR": str(root), "AUTHENTICATOR_TEST_QR": uri}
            result = subprocess.run(
                ["/usr/bin/bash", str(IMAGE_HELPER), str(image), str(PYTHON), str(PARSER)],
                env=environment, capture_output=True, text=True, timeout=15,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), uri)
            self.assertTrue(image.exists(), "image import must preserve the selected source file")
            self.assertEqual(list(root.glob("illogical-authenticator-qr.*.png")), [])

            oversized = root / "oversized.png"
            with oversized.open("wb") as file:
                file.seek(25 * 1024 * 1024)
                file.write(b"x")
            rejected = subprocess.run(
                ["/usr/bin/bash", str(IMAGE_HELPER), str(oversized), str(PYTHON), str(PARSER)],
                env=environment, capture_output=True, text=True, timeout=5,
            )
            self.assertEqual(rejected.returncode, 3)
            self.assertEqual(rejected.stdout, "")

    def test_encrypted_backup_reader_bounds_size_and_preserves_source(self) -> None:
        package = '{"format":"ii-authenticator-v1","salt":"fixture","nonce":"fixture","data":"ciphertext"}'
        with tempfile.TemporaryDirectory(prefix="authenticator-backup-read-") as temporary:
            root = Path(temporary)
            backup = root / "local backup with spaces.ii-auth"
            backup.write_text(package)
            result = subprocess.run(
                ["/usr/bin/bash", str(BACKUP_HELPER), str(backup)],
                capture_output=True, text=True, timeout=5,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, package)
            self.assertTrue(backup.exists())

            oversized = root / "oversized.ii-auth"
            with oversized.open("wb") as file:
                file.seek(5 * 1024 * 1024)
                file.write(b"x")
            rejected = subprocess.run(
                ["/usr/bin/bash", str(BACKUP_HELPER), str(oversized)],
                capture_output=True, text=True, timeout=5,
            )
            self.assertEqual(rejected.returncode, 3)
            self.assertEqual(rejected.stdout, "")

if __name__ == "__main__":
    unittest.main()
