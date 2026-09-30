#!/usr/bin/env python3
"""Render the real SDDM greeter, capture its states and test its login protocol.

Requires PySide6 and Pillow. A temporary fake SDDM daemon receives a test-only
password; this never authenticates a real account or touches the login service.
Screenshots and test copies go under build/sddm-check by default.
"""
import argparse
import hashlib
import json
import os
import shutil
import struct
import sys
from pathlib import Path

from PIL import Image, ImageChops
from PySide6.QtCore import QCoreApplication, QProcess, QProcessEnvironment, QTimer
from PySide6.QtNetwork import QLocalServer

ROOT = Path(__file__).resolve().parents[1]
SECRET = "mistletoe-test-only"


def qt_string(value):
    data = value.encode("utf-16-be")
    return struct.pack(">I", len(data)) + data


def read_string(data, offset):
    if len(data) < offset + 4:
        return None
    size = struct.unpack_from(">I", data, offset)[0]
    if len(data) < offset + 4 + size:
        return None
    return data[offset + 4:offset + 4 + size].decode("utf-16-be"), offset + 4 + size


def instrument(theme, output):
    ui = theme / "LockScreenUi.qml"
    ui.write_text(ui.read_text().replace("new Date()", "new Date(2026, 8, 30, 23, 8, 0)"))
    main = theme / "Main.qml"
    capture = lambda name: json.dumps(str(output / (name + ".png")))
    checks = """
    function input(item) {
        if (item.echoMode !== undefined) return item;
        for (let child of item.children) {
            let result = input(child);
            if (result) return result;
        }
        return null;
    }
    function screenshot(path) {
        root.grabToImage(function(result) {
            if (!result.saveToFile(path)) console.error("CHECK_FAILED capture");
        });
    }
    Timer { running: true; interval: 1000; onTriggered: root.screenshot(IDLE) }
    Timer { running: true; interval: 1200; onTriggered: loginUi.wake() }
    Timer { running: true; interval: 2300; onTriggered: root.screenshot(ACTIVE) }
    Timer {
        running: true; interval: 2700
        onTriggered: {
            let field = root.input(loginUi);
            if (!field || !field.activeFocus) console.error("CHECK_FAILED focus");
            field.text = SECRET;
            field.accepted();
            if (!root.authenticator.busy) console.error("CHECK_FAILED submission");
        }
    }
    Timer {
        running: true; interval: 3400
        onTriggered: {
            let field = root.input(loginUi);
            if (field.text || field.enabled || !loginUi.message) console.error("CHECK_FAILED failure");
            root.screenshot(FAILURE);
        }
    }
    Timer {
        running: true; interval: 6100
        onTriggered: {
            let field = root.input(loginUi);
            if (!field.enabled || loginUi.message) console.error("CHECK_FAILED retry");
            root.screenshot(RECOVERED);
        }
    }
    Timer { running: true; interval: 6500; onTriggered: root.chooseUser() }
    Timer { running: true; interval: 6900; onTriggered: root.screenshot(USERS) }
    Timer { running: true; interval: 7200; onTriggered: root.selectUser(Settings.defaultUser) }
    Timer {
        running: true; interval: 7600
        onTriggered: {
            let field = root.input(loginUi);
            if (!field.activeFocus || field.text || root.selectingUser) console.error("CHECK_FAILED user_selection");
            field.text = SECRET;
            field.accepted();
        }
    }
    Connections { target: sddm; function onLoginSucceeded() { Qt.quit(); } }
"""
    for name in ("idle", "active", "failure", "recovered", "users"):
        checks = checks.replace(name.upper(), capture(name))
    checks = checks.replace("SECRET", json.dumps(SECRET))
    main.write_text(main.read_text().rstrip()[:-1] + checks + "}\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--theme", type=Path, default=ROOT / "build/sddm/mistletoe")
    parser.add_argument("--output", type=Path, default=ROOT / "build/sddm-check")
    parser.add_argument("--greeter", default="sddm-greeter-qt6")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    theme = output / "test-theme"
    shutil.copytree(args.theme, theme, dirs_exist_ok=True)
    instrument(theme, output)
    platform = output / "screen.json"
    platform.write_text(json.dumps({"screens": [{"name": "test", "width": 1920, "height": 1080,
                                                "logicalDpi": 96, "logicalBaseDpi": 96, "dpr": 1}]}))
    app = QCoreApplication(sys.argv)
    server = QLocalServer()
    # Keep the UNIX socket below its path length limit.
    socket_name = f"/tmp/mistletoe-sddm-check-{os.getpid()}"
    if not server.listen(socket_name):
        raise SystemExit(server.errorString())
    connections = []
    attempts = []
    errors = []

    def connect():
        sock = server.nextPendingConnection()
        connections.append(sock)
        buffer = bytearray()
        def receive():
            buffer.extend(bytes(sock.readAll()))
            while len(buffer) >= 4:
                code = struct.unpack_from(">I", buffer)[0]
                if code == 0:
                    del buffer[:4]
                    sock.write(struct.pack(">II", 1, 4) + struct.pack(">I", 0) + qt_string("test-host"))
                    sock.flush()
                elif code == 1:
                    user = read_string(buffer, 4)
                    if user is None: return
                    password = read_string(buffer, user[1])
                    if password is None or len(buffer) < password[1] + 4: return
                    session_type = struct.unpack_from(">I", buffer, password[1])[0]
                    session = read_string(buffer, password[1] + 4)
                    if session is None: return
                    if not user[0] or password[0] != SECRET or not session[0]:
                        errors.append("Invalid SDDM login payload")
                    attempts.append({"user": user[0], "session": session[0], "type": session_type})
                    del buffer[:session[1]]
                    sock.write(struct.pack(">I", 3 if len(attempts) == 1 else 2))
                    sock.flush()
                else:
                    errors.append(f"Unexpected SDDM request {code}")
                    buffer.clear()
                    return
        sock.readyRead.connect(receive)
    server.newConnection.connect(connect)
    process = QProcess()
    environment = QProcessEnvironment.systemEnvironment()
    environment.insert("QT_QPA_PLATFORM", f"offscreen:configfile={platform}")
    environment.insert("QT_QPA_OFFSCREEN_NO_GLX", "1")
    environment.insert("QT_QUICK_BACKEND", "software")
    environment.insert("QT_FORCE_STDERR_LOGGING", "1")
    process.setProcessEnvironment(environment)
    process.setProcessChannelMode(QProcess.MergedChannels)
    log = bytearray()
    process.readyReadStandardOutput.connect(lambda: log.extend(bytes(process.readAllStandardOutput())))
    process.finished.connect(lambda *_: app.quit())
    timeout = QTimer()
    timeout.setSingleShot(True)
    def expired():
        errors.append("Greeter test timed out")
        process.kill()
    timeout.timeout.connect(expired)
    timeout.start(15000)
    process.start(args.greeter, ["--test-mode", "--theme", str(theme), "--socket", socket_name])
    if not process.waitForStarted(5000):
        raise SystemExit(process.errorString())
    app.exec()
    log.extend(bytes(process.readAllStandardOutput()))
    server.close()
    QLocalServer.removeServer(socket_name)
    text = log.decode(errors="replace")
    (output / "greeter.log").write_text(text)
    if "CHECK_FAILED" in text or "Fallback to embedded theme" in text or "Error:" in text or "ReferenceError" in text or "TypeError" in text:
        errors.append("Greeter reported a QML or interaction error; see greeter.log")
    if len(attempts) != 2:
        errors.append(f"Expected a failure and a successful retry, got {len(attempts)} attempts")
    for name in ("idle", "active", "failure", "recovered", "users"):
        path = output / (name + ".png")
        if not path.is_file() or Image.open(path).size != (1920, 1080):
            errors.append(f"Missing or incorrectly sized screenshot {name}")
    if errors:
        print(text)
        raise SystemExit("\n".join(errors))
    report = {"passed": True, "login_attempts": attempts,
              "screenshots": [str(output / (name + ".png")) for name in ("idle", "active", "failure", "recovered", "users")]}
    report["retry_image_identical"] = ImageChops.difference(Image.open(output / "active.png"),
                                                           Image.open(output / "recovered.png")).getbbox() is None
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    package = args.theme.resolve()
    digest = hashlib.sha256((package / "SHA256SUMS").read_bytes()).hexdigest()
    (package / "VERIFIED_SHA256").write_text(digest + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
