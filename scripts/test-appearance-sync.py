#!/usr/bin/env python3
"""Regression checks for edition wallpaper policy and data-only SDDM updates."""
import copy
import importlib.machinery
import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


bridge = load("appearance_bridge", ROOT / "apps/mistletoe-menu/mistletoe-menu")
sync = load("appearance_sync", ROOT / "scripts/sync-sddm.py")


def desktop(image):
    return f"""[Containments][1]
plugin=org.kde.panel
lastScreen=0
[Containments][1][Wallpaper][org.kde.image][General]
Image=/stale/panel.png
[Containments][2]
plugin=org.kde.plasma.folder
lastScreen=-1
[Containments][2][Wallpaper][org.kde.image][General]
Image=/stale/desktop.png
[Containments][72]
plugin=org.kde.plasma.folder
lastScreen=0
[Containments][72][Wallpaper][org.kde.image][General]
Image={image}
"""


class EditionPolicy(unittest.TestCase):
    def exercise(self, previous, current, force=False, fails=False):
        calls = []
        def run(args, **_kwargs):
            calls.append(args)
            if args[0] == "kreadconfig6":
                return subprocess.CompletedProcess(args, 0, current + "\n", "")
            return subprocess.CompletedProcess(args, int(fails and args[0] == "plasma-apply-wallpaperimage"), b"", b"test failure")
        with tempfile.TemporaryDirectory() as tmp:
            with patch.object(bridge, "CONFIG", Path(tmp)), patch.object(bridge, "DATA", Path("/themes")), \
                    patch.object(bridge, "ensure_gtk_layer"), patch.object(bridge, "lock_settings"), patch.object(bridge, "flush_wallpaper") as flush, \
                    patch.object(bridge, "current_wallpapers", return_value=["/pictures/my image.png"]), \
                    patch.object(bridge, "kread", return_value=previous), patch.object(bridge.subprocess, "run", side_effect=run):
                bridge.sync_wallpaper(force=force)
                self.assertEqual(flush.call_count, int(not fails and current in bridge.EDITION_WALLPAPER and (force or bool(previous and previous != current))))
        return calls

    def test_switch_replaces_custom_for_each_edition(self):
        for edition, package in bridge.EDITION_WALLPAPER.items():
            with self.subTest(edition=edition):
                calls = self.exercise("old.edition", edition)
                self.assertIn(["plasma-apply-wallpaperimage", f"/themes/wallpapers/{package}"], calls)
                lock = [c for c in calls if "kscreenlockerrc" in c][0]
                self.assertEqual(lock[-1], f"file:///themes/wallpapers/{package}")

    def test_same_edition_keeps_custom(self):
        calls = self.exercise("org.mistletoe.dark.desktop", "org.mistletoe.dark.desktop")
        self.assertFalse(any(c[0] == "plasma-apply-wallpaperimage" for c in calls))
        self.assertEqual([c for c in calls if "kscreenlockerrc" in c][0][-1], "file:///pictures/my%20image.png")

    def test_first_start_keeps_custom_and_records_baseline(self):
        calls = self.exercise("", "org.mistletoe.neon.desktop")
        self.assertFalse(any(c[0] == "plasma-apply-wallpaperimage" for c in calls))
        self.assertTrue(any("LastLookAndFeel" in c for c in calls))

    def test_explicit_reapply_replaces_custom(self):
        calls = self.exercise("org.mistletoe.ember.desktop", "org.mistletoe.ember.desktop", force=True)
        self.assertTrue(any(c[0] == "plasma-apply-wallpaperimage" for c in calls))

    def test_failed_apply_does_not_record_success(self):
        calls = self.exercise("org.mistletoe.dark.desktop", "org.mistletoe.ember.desktop", fails=True)
        self.assertFalse(any("LastLookAndFeel" in c or "kscreenlockerrc" in c for c in calls))

    def test_other_themes_keep_their_wallpaper(self):
        calls = self.exercise("org.mistletoe.ember.desktop", "org.kde.breeze.desktop")
        self.assertFalse(any(c[0] == "plasma-apply-wallpaperimage" for c in calls))


class AppearancePublisher(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.config = self.base / "config"
        self.config.mkdir()
        self.image = self.base / "my image.png"
        Image.new("RGB", (240, 135), (45, 80, 120)).save(self.image)
        (self.config / "plasma-org.kde.plasma.desktop-appletsrc").write_text(desktop(self.image.as_uri()))
        (self.config / "kdeglobals").write_text("[Colors:Window]\nBackgroundNormal=22,15,32\nForegroundNormal=236,226,240\nDecorationFocus=196,110,200\n")
        self.state = self.base / "state"
        self.theme = self.base / "theme"
        self.theme.mkdir()
        (self.theme / "Main.qml").write_text("// existing tested UI\n")
        (self.theme / "LockScreenUi.qml").write_text("// existing presentation\n")
        (self.theme / "settings.js").write_bytes(sync.js({"ink": "#000000", "bone": "#ffffff", "gold": "#abcdef", "defaultUser": "original", "textFont": "fonts/text.ttf"}))
        (self.theme / "backdrop.js").write_bytes(sync.js({"distro": "Fedora Linux 44", "clockOnLight": True, "promptOnLight": True, "badgeOnLight": True}))
        (self.theme / "wallpaper.png").write_bytes(self.image.read_bytes())
        self.request = sync.export(self.state, self.config, self.base / "data", mirror_lock=False)

    def test_primary_image_ignores_panels_and_inactive_desktops(self):
        self.assertEqual(sync.desktop_wallpaper(self.config), self.image)
        with patch.object(bridge, "CONFIG", self.config):
            self.assertEqual(bridge.current_wallpapers(), [self.image.as_uri()])

    def test_plain_path_and_package(self):
        for path in (self.image, self.base / "package"):
            if path != self.image:
                (path / "contents/images").mkdir(parents=True)
                (path / "contents/images/picture.png").write_bytes(self.image.read_bytes())
            (self.config / "plasma-org.kde.plasma.desktop-appletsrc").write_text(desktop(path))
            self.assertEqual(sync.desktop_wallpaper(self.config), self.image if path == self.image else path / "contents/images/picture.png")

    def test_publish_matches_palette_without_changing_ui_or_fonts(self):
        before = {p.name: p.read_bytes() for p in self.theme.glob("*.qml")}
        sync.publish(self.state, self.theme, os.getuid())
        settings = sync.read_js(self.theme / "settings.js")
        self.assertEqual({k: settings[k] for k in ("ink", "bone", "gold")}, {"ink": "#160f20", "bone": "#ece2f0", "gold": "#c46ec8"})
        self.assertEqual(settings["defaultUser"], "original")
        self.assertEqual(settings["textFont"], "fonts/text.ttf")
        self.assertEqual(before, {p.name: p.read_bytes() for p in self.theme.glob("*.qml")})
        self.assertEqual(sync.read_js(self.theme / "backdrop.js")["distro"], "Fedora Linux 44")
        self.assertEqual((self.theme / "wallpaper.png").read_bytes(), (self.state / "wallpaper.png").read_bytes())
        snapshot = {p.name: p.read_bytes() for p in self.theme.iterdir()}
        sync.publish(self.state, self.theme, os.getuid())
        self.assertEqual(snapshot, {p.name: p.read_bytes() for p in self.theme.iterdir()})

    def test_invalid_data_cannot_mutate_the_theme(self):
        for field in ("colors", "wallpaper_sha256", "unexpected"):
            with self.subTest(field=field):
                bad = copy.deepcopy(self.request)
                if field == "colors":
                    bad["colors"]["gold"] = '"; malicious()'
                elif field == "wallpaper_sha256":
                    bad[field] = "0" * 64
                else:
                    bad[field] = "Main.qml"
                (self.state / "appearance.json").write_text(json.dumps(bad))
                before = {p.name: p.read_bytes() for p in self.theme.iterdir()}
                with self.assertRaises(ValueError):
                    sync.publish(self.state, self.theme, os.getuid())
                self.assertEqual(before, {p.name: p.read_bytes() for p in self.theme.iterdir()})

    def test_staging_symlink_and_wrong_owner_rejected(self):
        with self.assertRaises(ValueError):
            sync.publish(self.state, self.theme, os.getuid() + 1)
        (self.state / "wallpaper.png").unlink()
        (self.state / "wallpaper.png").symlink_to(self.image)
        with self.assertRaises(OSError):
            sync.publish(self.state, self.theme, os.getuid())

    def test_refresh_repeats_when_settings_change_while_running(self):
        calls = []
        def export_as_user(command, **_kwargs):
            calls.append(command)
            if len(calls) == 1:
                with (self.config / "kdeglobals").open("a") as file:
                    file.write("\n[ChangedDuringExport]\nkey=value\n")
        with patch.object(sync.subprocess, "run", side_effect=export_as_user), \
                patch.object(sync, "publish") as publish, patch.object(sync.time, "sleep"):
            sync.refresh(self.state, self.config, self.base / "data", self.theme, os.getuid())
        self.assertEqual(len(calls), 2)
        self.assertEqual(publish.call_count, 2)
        self.assertEqual(calls[0][:2], ["/usr/sbin/runuser", "-u"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
