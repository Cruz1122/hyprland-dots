from __future__ import annotations

import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
BATTERY_SERVICE = REPO_ROOT / "config/quickshell/ii/services/Battery.qml"
BATTERY_POPUP = REPO_ROOT / "config/quickshell/ii/modules/ii/bar/BatteryPopup.qml"


class BatteryContractTest(unittest.TestCase):
    def test_pending_charge_is_exposed_as_charging_for_the_ui(self) -> None:
        battery = BATTERY_SERVICE.read_text(encoding="utf-8")

        self.assertIn("chargeState == UPowerDeviceState.Charging || chargeState == UPowerDeviceState.PendingCharge", battery)
        self.assertIn("property bool isPluggedIn: isCharging", battery)
        self.assertIn("UPowerDeviceState.FullyCharged", battery)

    def test_battery_popup_uses_shared_state_properties(self) -> None:
        popup = BATTERY_POPUP.read_text(encoding="utf-8")

        self.assertIn("Battery.isFullyCharged", popup)
        self.assertIn("Battery.isCharging", popup)
        self.assertNotRegex(popup, r"Battery\.chargeState\s*==\s*[14]")
        self.assertNotRegex(popup, r"Battery\.chargeState\s*!=\s*4")


if __name__ == "__main__":
    unittest.main()
