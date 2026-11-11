import contextlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("build_icon", ROOT / "scripts" / "build-icon.py")
build_icon = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build_icon)


class IconBuildTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix="strata-icon-test-")
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)
        self.resources = self.root / "Strata.app" / "Contents" / "Resources"
        self.resources.mkdir(parents=True)
        self.info = self.resources.parent / "Info.plist"
        self.original_info = (ROOT / "Resources" / "Info.plist").read_bytes()
        self.info.write_bytes(self.original_info)

    @unittest.skipUnless(sys.platform == "darwin" and build_icon.compiles_layers(build_icon.host_version()),
                         "Xcode compiles the layered macOS app icon on macOS 26 or later")
    def test_app_bundle_has_adaptive_layers_and_the_contributed_fallback(self):
        with contextlib.redirect_stdout(io.StringIO()):
            build_icon.build(self.resources, self.info)
        original = plistlib.loads(self.original_info)
        info = plistlib.loads(self.info.read_bytes())
        self.assertEqual(info["CFBundleIconName"], "AppIcon")
        self.assertEqual(info["CFBundleIconFile"], "AppIcon")
        for key, value in original.items():
            self.assertEqual(info[key], value, key)
        self.assertEqual((self.resources / "AppIcon.icns").read_bytes(),
                         (ROOT / "Resources" / "AppIcon.icns").read_bytes())
        result = subprocess.run(["xcrun", "assetutil", "--info", str(self.resources / "Assets.car")],
                                capture_output=True, text=True, check=True)
        stacks = [item for item in json.loads(result.stdout) if item.get("AssetType") == "IconImageStack"]
        self.assertTrue(stacks, "The app icon must retain its layers rather than only a flattened image.")
        self.assertTrue(all(item["Name"] == "AppIcon" and item["LayerCount"] > 1 for item in stacks))
        self.assertTrue({"NSAppearanceNameAqua", "NSAppearanceNameDarkAqua", "ISAppearanceTintable"}
                        .issubset({item.get("Appearance") for item in stacks}))
        iconset = self.root / "fallback.iconset"
        subprocess.run(["iconutil", "-c", "iconset", str(self.resources / "AppIcon.icns"), "-o", str(iconset)], check=True)
        for size in [16, 32, 128, 256, 512]:
            for scale in ["", "@2x"]:
                self.assertTrue((iconset / f"icon_{size}x{size}{scale}.png").is_file())

    def test_a_mac_older_than_26_builds_with_the_fallback_alone(self):
        # Why: Xcode's icon compiler crashes on a layered icon on macOS 15, where Strata is built too.
        # Given a macOS 15 build host, when the icon is built without ever starting the compiler.
        with patch.object(build_icon, "host_version", return_value=(15, 7)), \
             patch.object(build_icon.subprocess, "run", side_effect=AssertionError("the icon compiler was started")), \
             contextlib.redirect_stdout(io.StringIO()) as said:
            build_icon.build(self.resources, self.info)
        # Then the bundle holds the fallback, its metadata is unchanged, and the build says what it left out.
        self.assertEqual([item.name for item in self.resources.iterdir()], ["AppIcon.icns"])
        self.assertEqual((self.resources / "AppIcon.icns").read_bytes(),
                         (ROOT / "Resources" / "AppIcon.icns").read_bytes())
        self.assertEqual(self.info.read_bytes(), self.original_info)
        self.assertIn("without its layers", said.getvalue())

    def test_layers_are_compiled_from_macos_26(self):
        self.assertFalse(build_icon.compiles_layers((15, 7)))
        self.assertTrue(build_icon.compiles_layers((26, 0)))
        self.assertTrue(build_icon.compiles_layers((27, 2)))
        # Not a Mac (no version to read): the compiler is asked, and its failure stops the build.
        self.assertTrue(build_icon.compiles_layers(()))

    def test_compiler_failure_stops_before_changing_bundle_resources_or_metadata(self):
        (self.resources / "Assets.car").write_bytes(b"previous catalog")
        (self.resources / "AppIcon.icns").write_bytes(b"previous fallback")
        with patch.object(build_icon, "host_version", return_value=(26, 0)), \
             patch.object(build_icon.subprocess, "run", side_effect=subprocess.CalledProcessError(1, ["actool"])):
            with self.assertRaises(subprocess.CalledProcessError):
                build_icon.build(self.resources, self.info)
        self.assertEqual(self.info.read_bytes(), self.original_info)
        self.assertEqual((self.resources / "Assets.car").read_bytes(), b"previous catalog")
        self.assertEqual((self.resources / "AppIcon.icns").read_bytes(), b"previous fallback")

    def test_an_incomplete_icon_source_cannot_silently_ship_only_the_fallback(self):
        with patch.object(build_icon, "ROOT", self.root):
            with self.assertRaises(FileNotFoundError):
                build_icon.build(self.resources, self.info)
        self.assertEqual(list(self.resources.iterdir()), [])
        self.assertEqual(self.info.read_bytes(), self.original_info)


if __name__ == "__main__":
    unittest.main()
