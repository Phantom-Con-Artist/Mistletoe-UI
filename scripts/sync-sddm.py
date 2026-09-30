#!/usr/bin/env python3
"""Export desktop appearance as the user, then publish validated data as root.

The installed system service runs the exporter without root privileges. The
publisher accepts image bytes and palette values, never QML or executable code.
"""
import argparse
import configparser
import hashlib
import json
import os
import pwd
import re
import stat
import struct
import subprocess
import tempfile
import time
from pathlib import Path
from urllib.parse import unquote, urlparse


def read_config(path):
    result = configparser.ConfigParser(interpolation=None, strict=False)
    result.optionxform = str
    result.read(path)
    return result


def desktop_wallpaper(config):
    desktop = read_config(config / "plasma-org.kde.plasma.desktop-appletsrc")
    candidates = []
    for section in desktop.sections():
        match = re.fullmatch(r"Containments\]\[(\d+)\]\[Wallpaper\]\[org.kde.image\]\[General", section)
        if not match:
            continue
        parent = f"Containments][{match[1]}"
        if desktop.get(parent, "plugin", fallback="") != "org.kde.plasma.folder":
            if desktop.get(parent, "plugin", fallback="") != "org.kde.desktop":
                continue
        screen = desktop.getint(parent, "lastScreen", fallback=-1)
        image = desktop.get(section, "Image", fallback="")
        if image and screen >= 0:
            candidates.append((screen != 0, screen, image))
    if not candidates:
        raise ValueError("No image wallpaper is configured on an active desktop")
    url = urlparse(min(candidates)[2])
    if url.scheme not in ("", "file") or url.netloc not in ("", "localhost"):
        raise ValueError("The desktop wallpaper must be a local image or wallpaper package")
    path = Path(unquote(url.path)).expanduser()
    if path.is_dir():
        images = [p for p in (path / "contents/images").iterdir() if p.is_file()]
        if not images:
            raise ValueError("The desktop wallpaper package has no images")
        path = max(images, key=lambda p: p.stat().st_size)
    return path.resolve()


def color(value):
    if re.fullmatch(r"#[0-9a-fA-F]{6}", value):
        return value.lower()
    parts = value.split(",")
    if len(parts) != 3:
        raise ValueError("Expected an RGB color")
    rgb = [int(v) for v in parts]
    if any(v < 0 or v > 255 for v in rgb):
        raise ValueError("RGB components must be between 0 and 255")
    return "#" + "".join(f"{v:02x}" for v in rgb)


def atomic_write(path, content, mode=0o644):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".appearance-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(name, mode)
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)


def js(values):
    return (".pragma library\n" + "".join(f"var {key} = {json.dumps(value)};\n"
                                          for key, value in values.items())).encode()


def export(state, config, data, mirror_lock=True):
    from PIL import Image, ImageOps
    path = desktop_wallpaper(config)
    kde = read_config(config / "kdeglobals")
    colors = {name: color(kde.get("Colors:Window", key)) for name, key in
              (("ink", "BackgroundNormal"), ("bone", "ForegroundNormal"), ("gold", "DecorationFocus"))}
    state.mkdir(parents=True, exist_ok=True)
    with Image.open(path) as source:
        image = source.convert("RGB")
    fd, temp = tempfile.mkstemp(prefix=".wallpaper-", dir=state)
    os.close(fd)
    try:
        image.save(temp, format="PNG")
        wallpaper = Path(temp).read_bytes()
    finally:
        Path(temp).unlink(missing_ok=True)
    luma = ImageOps.fit(image.convert("L"), (1920, 1080))
    ink = [int(colors["ink"][i:i + 2], 16) for i in (1, 3, 5)]
    veil_luma = (0.299 * ink[0] + 0.587 * ink[1] + 0.114 * ink[2]) / 255
    def light(box, veil):
        hist = luma.crop(box).histogram()
        mean = sum(i * n for i, n in enumerate(hist)) / max(1, sum(hist)) / 255
        return mean * (1 - veil) + veil_luma * veil > 0.5
    backdrop = {"clockOnLight": light((134, 324, 749, 648), 0.38),
                "promptOnLight": light((750, 713, 1170, 753), 0.62),
                "badgeOnLight": light((1380, 0, 1920, 86), 0.38)}
    request = {"colors": colors, "backdrop": backdrop,
               "wallpaper_sha256": hashlib.sha256(wallpaper).hexdigest(), "wallpaper_source": str(path)}
    atomic_write(state / "wallpaper.png", wallpaper, 0o600)
    atomic_write(state / "appearance.json", (json.dumps(request) + "\n").encode(), 0o600)
    if mirror_lock:
        locker = config / "kscreenlockerrc"
        group = "Greeter][Wallpaper][org.kde.image][General"
        if read_config(locker).get(group, "Image", fallback="") != path.as_uri():
            subprocess.run(["kwriteconfig6", "--file", str(locker), "--group", "Greeter", "--group", "Wallpaper",
                            "--group", "org.kde.image", "--group", "General", "--key", "Image", path.as_uri()], check=True)
        target = data / "plasma/shells/org.mistletoe.lockscreen/contents/lockscreen/backdrop.js"
        if target.is_file() and not target.is_symlink() and target.resolve().is_relative_to(data.resolve()):
            # Retain the machine's distro line while updating contrast data.
            old = read_js(target)
            old.update(backdrop)
            atomic_write(target, js(old))
    print(f"Exported desktop appearance from {path}")
    return request


def read_js(path):
    values = {}
    for line in path.read_text().splitlines():
        match = re.fullmatch(r"var ([A-Za-z][A-Za-z0-9_]*) = (.+);", line)
        if match:
            values[match[1]] = json.loads(match[2])
    return values


def read_owned(path, uid, limit):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != uid or info.st_size > limit:
            raise ValueError("Invalid appearance staging file")
        value = stream.read(limit + 1)
        if len(value) > limit:
            raise ValueError("Appearance staging file exceeds its size limit")
        return value


def validate(request, wallpaper):
    if set(request) != {"colors", "backdrop", "wallpaper_sha256", "wallpaper_source"}:
        raise ValueError("Unexpected appearance fields")
    if set(request["colors"]) != {"ink", "bone", "gold"} or any(
            not isinstance(v, str) or not re.fullmatch(r"#[0-9a-f]{6}", v) for v in request["colors"].values()):
        raise ValueError("Invalid appearance colors")
    if set(request["backdrop"]) != {"clockOnLight", "promptOnLight", "badgeOnLight"} or any(
            type(v) is not bool for v in request["backdrop"].values()):
        raise ValueError("Invalid contrast settings")
    if hashlib.sha256(wallpaper).hexdigest() != request["wallpaper_sha256"]:
        raise ValueError("The appearance image and manifest do not match")
    if len(wallpaper) < 33 or wallpaper[:8] != b"\x89PNG\r\n\x1a\n" or wallpaper[12:16] != b"IHDR":
        raise ValueError("The exported wallpaper is not a PNG")
    width, height = struct.unpack(">II", wallpaper[16:24])
    if not 0 < width <= 16384 or not 0 < height <= 16384 or width * height > 80_000_000:
        raise ValueError("Invalid wallpaper dimensions")
    if wallpaper[24:26] != bytes((8, 2)):
        raise ValueError("The wallpaper must be an RGB PNG")


def publish(state, theme, uid):
    request = json.loads(read_owned(state / "appearance.json", uid, 16384))
    wallpaper = read_owned(state / "wallpaper.png", uid, 64 * 1024 * 1024)
    validate(request, wallpaper)
    settings = read_js(theme / "settings.js")
    backdrop = read_js(theme / "backdrop.js")
    settings.update(request["colors"])
    backdrop.update(request["backdrop"])
    changes = {"wallpaper.png": wallpaper, "settings.js": js(settings), "backdrop.js": js(backdrop)}
    changed = False
    for name, content in changes.items():
        target = theme / name
        if target.read_bytes() != content:
            atomic_write(target, content)
            changed = True
    if changed:
        # The UI and backend remain the tested package; only validated data change.
        manifest = "".join(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(theme)}\n"
                           for path in sorted(theme.rglob("*")) if path.is_file()
                           and path.name not in ("SHA256SUMS", "VERIFIED_SHA256"))
        atomic_write(theme / "SHA256SUMS", manifest.encode())
        atomic_write(theme / "VERIFIED_SHA256", (hashlib.sha256(manifest.encode()).hexdigest() + "\n").encode())
    print("Published desktop wallpaper and colors" if changed else "SDDM appearance is already current")


def refresh(state, config, data, theme, uid):
    """Repeat if Plasma commits another setting while a path-triggered job runs.

    systemd path events received while its service is active do not queue a
    second activation. Recheck the two watched files before finishing.
    """
    def snapshot():
        return tuple(hashlib.sha256((config / name).read_bytes()).digest() for name in
                     ("kdeglobals", "plasma-org.kde.plasma.desktop-appletsrc"))
    command = ["/usr/sbin/runuser", "-u", pwd.getpwuid(uid).pw_name, "--", "/usr/bin/python3",
               str(Path(__file__).resolve()), "export", "--state", str(state), "--config", str(config), "--data", str(data)]
    deadline = time.monotonic() + 25
    while time.monotonic() < deadline:
        before = snapshot()
        subprocess.run(command, check=True)
        publish(state, theme, uid)
        time.sleep(0.3)
        if snapshot() == before:
            return
        print("Desktop settings changed during sync; refreshing again", flush=True)
    raise RuntimeError("Desktop settings did not settle during appearance sync")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("export", "publish", "refresh"))
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--config", type=Path, default=Path.home() / ".config")
    parser.add_argument("--data", type=Path, default=Path.home() / ".local/share")
    parser.add_argument("--theme", type=Path, default=Path("/usr/share/sddm/themes/mistletoe"))
    parser.add_argument("--uid", type=int)
    args = parser.parse_args()
    if args.mode == "export":
        # KConfig writes a palette and several theme keys together.
        time.sleep(0.5)
        export(args.state, args.config, args.data)
    else:
        if os.geteuid() != 0 or args.uid is None:
            raise SystemExit("The publisher requires root and a configured desktop UID")
        if args.mode == "refresh":
            refresh(args.state, args.config, args.data, args.theme, args.uid)
        else:
            publish(args.state, args.theme, args.uid)


if __name__ == "__main__":
    main()
