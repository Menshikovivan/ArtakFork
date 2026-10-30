import importlib.util
from pathlib import Path
import unittest
from unittest.mock import Mock, patch


SCRIPT = Path(__file__).resolve().parents[1] / "prepare_artak_bootstrap.py"
spec = importlib.util.spec_from_file_location("artak_bootstrap", SCRIPT)
bootstrap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bootstrap)


class BootstrapPinTests(unittest.TestCase):
    def test_latest_guard_and_explicit_pinned_release(self):
        with patch.object(bootstrap, "api") as api_mock:
            root = Path("unused")
            installer = Mock()
            installer.read_text.return_value = "BASE_VERSION=1.0.5\nENGINE_VERSION=1.14.3-extended-2.7.3\n"
            calls = []

            def fake_api(path):
                calls.append(path)
                if path.endswith("/releases/latest"):
                    return {"tag_name": "2.0.0", "draft": False, "prerelease": False}
                if "/commits/" in path:
                    return {"sha": "a" * 40}
                repo, tag = path.split("/releases/tags/")
                names = ([f"{p}_{tag}.apk" for p in ("forkop", "luci-app-forkop", "luci-i18n-forkop-ru")]
                         if repo == "ushan0v/forkop" else
                         ["sing-box-extended_1.14.3-extended-2.7.3_openwrt_aarch64_cortex-a53.apk"])
                return {"tag_name": tag, "draft": False, "prerelease": False, "assets": [
                    {"name": name, "digest": "sha256:" + "b" * 64, "size": 1,
                     "browser_download_url": f"https://github.com/{repo}/releases/download/{tag}/{name}"}
                    for name in names]}

            api_mock.side_effect = fake_api
            with self.assertRaises(ValueError):
                bootstrap.prepare(installer, root, check_only=True)
            bootstrap.prepare(installer, root, check_only=True, use_pinned=True)
            self.assertIn("ushan0v/forkop/releases/tags/1.0.5", calls)
            self.assertIn("shtorm-7/sing-box-extended/releases/tags/v1.14.3-extended-2.7.3", calls)


if __name__ == "__main__":
    unittest.main()
