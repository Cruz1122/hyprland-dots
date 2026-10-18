import os
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "config/quickshell/ii/scripts/grok-open-bot.sh"
VALID_ID = "861e7ebb-7152-4967-8c4a-3b8336fdc094"


class GrokOpenBotTests(unittest.TestCase):
    def test_invalid_id_is_rejected_before_external_commands(self):
        result = subprocess.run([SCRIPT, "not-an-id"], check=False)
        self.assertEqual(result.returncode, 2)

    def make_bin(self, temp: str, client_json: str) -> tuple[Path, Path, dict[str, str]]:
        bin_dir = Path(temp) / "bin"
        bin_dir.mkdir()
        log = Path(temp) / "log"
        (bin_dir / "xdg-open").write_text(
            f"#!/bin/sh\nprintf '%s\\n' \"$1\" >> '{log}'\n", encoding="utf-8"
        )
        (bin_dir / "hyprctl").write_text(
            "#!/bin/sh\n"
            "case \"$1 $2\" in\n"
            "  'activeworkspace -j') printf '{\"name\":\"2\"}';;\n"
            f"  'clients -j') printf '%s' '{client_json}';;\n"
            f"  *) printf '%s\\n' \"$*\" >> '{log}';;\n"
            "esac\n",
            encoding="utf-8",
        )
        for command in (bin_dir / "xdg-open", bin_dir / "hyprctl"):
            command.chmod(0o755)
        environment = {**os.environ, "PATH": f"{bin_dir}:{os.environ.get('PATH', '')}"}
        return bin_dir, log, environment

    def test_warm_instance_on_normal_workspace_is_focused_without_moving(self):
        with tempfile.TemporaryDirectory() as temp:
            _, log, environment = self.make_bin(
                temp,
                '[{"address":"0xabc","class":"grok-bot","workspace":{"name":"3"}}]',
            )
            result = subprocess.run([SCRIPT, VALID_ID], env=environment, check=False)

            self.assertEqual(result.returncode, 0)
            lines = log.read_text(encoding="utf-8").splitlines()
            self.assertIn(f"grokbot://app/v1/agent?id={VALID_ID}", lines)
            self.assertIn("dispatch focuswindow address:0xabc", lines)
            self.assertFalse(any("movetoworkspace" in line for line in lines))

    def test_hidden_startup_window_is_moved_once_then_only_focused(self):
        with tempfile.TemporaryDirectory() as temp:
            bin_dir = Path(temp) / "bin"
            bin_dir.mkdir()
            log = Path(temp) / "log"
            workspace_state = Path(temp) / "workspace"
            workspace_state.write_text("special:grok-bot", encoding="utf-8")
            (bin_dir / "xdg-open").write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            (bin_dir / "hyprctl").write_text(
                "#!/bin/bash\n"
                "case \"$1 $2\" in\n"
                "  'activeworkspace -j') printf '{\"name\":\"2\"}';;\n"
                "  'clients -j') printf '[{\"address\":\"0xabc\",\"class\":\"grok-bot\",\"workspace\":{\"name\":\"%s\"}}]' \"$(cat '" + str(workspace_state) + "')\";;\n"
                "  'dispatch movetoworkspace') printf '%s' \"${3%%,*}\" > '" + str(workspace_state) + "'; printf '%s\\n' \"$*\" >> '" + str(log) + "';;\n"
                "  *) printf '%s\\n' \"$*\" >> '" + str(log) + "';;\n"
                "esac\n",
                encoding="utf-8",
            )
            for command in (bin_dir / "xdg-open", bin_dir / "hyprctl"):
                command.chmod(0o755)
            environment = {**os.environ, "PATH": f"{bin_dir}:{os.environ.get('PATH', '')}"}

            for _ in range(2):
                result = subprocess.run([SCRIPT, VALID_ID], env=environment, check=False)
                self.assertEqual(result.returncode, 0)

            lines = log.read_text(encoding="utf-8").splitlines()
            moves = [line for line in lines if "movetoworkspace" in line]
            focuses = [line for line in lines if "focuswindow" in line]
            self.assertEqual(moves, ["dispatch movetoworkspace 2,address:0xabc"])
            self.assertEqual(focuses, [
                "dispatch focuswindow address:0xabc",
                "dispatch focuswindow address:0xabc",
            ])

    def test_lua_provider_uses_focus_and_move_dispatchers(self):
        with tempfile.TemporaryDirectory() as temp:
            bin_dir = Path(temp) / "bin"
            bin_dir.mkdir()
            log = Path(temp) / "log"
            (bin_dir / "xdg-open").write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            (bin_dir / "hyprctl").write_text(
                "#!/bin/bash\n"
                "if [[ \"$1\" == systeminfo ]]; then printf 'configProvider: lua\\n'; exit 0; fi\n"
                "case \"$1 $2\" in\n"
                "  'activeworkspace -j') printf '{\"name\":\"2\"}';;\n"
                "  'clients -j') printf '[{\"address\":\"0xabc\",\"class\":\"grok-bot\",\"workspace\":{\"name\":\"special:grok-bot\"}}]';;\n"
                "  *) printf '%s\\n' \"$*\" >> '" + str(log) + "';;\n"
                "esac\n",
                encoding="utf-8",
            )
            for command in (bin_dir / "xdg-open", bin_dir / "hyprctl"):
                command.chmod(0o755)
            environment = {**os.environ, "PATH": f"{bin_dir}:{os.environ.get('PATH', '')}"}

            result = subprocess.run([SCRIPT, VALID_ID], env=environment, check=False)

            self.assertEqual(result.returncode, 0)
            lines = log.read_text(encoding="utf-8").splitlines()
            self.assertIn(
                'dispatch hl.dsp.window.move({ workspace = "2", follow = false, window = "address:0xabc" })',
                lines,
            )
            self.assertIn('dispatch hl.dsp.focus({ window = "address:0xabc" })', lines)


if __name__ == "__main__":
    unittest.main()
