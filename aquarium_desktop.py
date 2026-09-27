"""Interactive aquarium wallpaper for Windows and Linux/X11."""

from __future__ import annotations

import argparse
import ctypes
import math
import os
from pathlib import Path
import random
import signal
import sys
import time

import cv2
from PySide6.QtCore import QPointF, QRectF, Qt, QTimer
from PySide6.QtGui import QCursor, QImage, QPainter, QPen
from PySide6.QtWidgets import QApplication, QWidget


def asset_dir() -> Path:
    bundled = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent)) / "assets"
    if bundled.is_dir():
        return bundled
    return Path(sys.executable).resolve().parent / "assets"


ASSETS = asset_dir()
VIDEO = ASSETS / "aquarium-loop.mp4"
SPECIES = (
    ("neon-tetra.png", 16, (45, 64), (22, 38)),
    ("honey-gourami.png", 3, (87, 110), (11, 20)),
    ("silver-angelfish.png", 2, (106, 137), (8, 15)),
    ("fancy-guppy.png", 6, (63, 82), (18, 31)),
)


def check_assets() -> None:
    if not VIDEO.is_file():
        raise RuntimeError(f"Missing loop video: {VIDEO}")
    cap = cv2.VideoCapture(str(VIDEO))
    try:
        if not cap.isOpened() or not cap.read()[0]:
            raise RuntimeError("Cannot decode the aquarium video")
    finally:
        cap.release()
    for name, _, _, _ in SPECIES:
        image = QImage(str(ASSETS / name))
        if image.isNull():
            raise RuntimeError(f"Cannot load fish image: {name}")


def windows_workerw() -> int:
    from ctypes import wintypes

    user32 = configure_user32()
    progman = user32.FindWindowW("Progman", None)
    if not progman:
        raise RuntimeError("Cannot find the Windows desktop")
    result = ctypes.c_size_t()
    user32.SendMessageTimeoutW(progman, 0x052C, 0, 0, 0, 1000, ctypes.byref(result))
    worker = ctypes.c_void_p()
    enum_callback = ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)

    def inspect(hwnd: int, _param: int) -> bool:
        nonlocal worker
        if user32.FindWindowExW(hwnd, 0, "SHELLDLL_DefView", None):
            candidate = user32.FindWindowExW(0, hwnd, "WorkerW", None)
            if candidate:
                worker = ctypes.c_void_p(candidate)
                return False
        return True

    user32.EnumWindows(enum_callback(inspect), 0)
    return int(worker.value or progman)


def configure_user32():
    from ctypes import wintypes

    user32 = ctypes.windll.user32
    user32.FindWindowW.argtypes = [wintypes.LPCWSTR, wintypes.LPCWSTR]
    user32.FindWindowW.restype = wintypes.HWND
    user32.FindWindowExW.argtypes = [wintypes.HWND, wintypes.HWND, wintypes.LPCWSTR, wintypes.LPCWSTR]
    user32.FindWindowExW.restype = wintypes.HWND
    user32.EnumWindows.argtypes = [ctypes.c_void_p, wintypes.LPARAM]
    user32.EnumWindows.restype = wintypes.BOOL
    user32.SendMessageTimeoutW.argtypes = [
        wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM,
        wintypes.UINT, wintypes.UINT, ctypes.c_void_p,
    ]
    user32.SendMessageTimeoutW.restype = wintypes.LPARAM
    user32.SetParent.argtypes = [wintypes.HWND, wintypes.HWND]
    user32.SetParent.restype = wintypes.HWND
    user32.GetParent.argtypes = [wintypes.HWND]
    user32.GetParent.restype = wintypes.HWND
    user32.GetWindowLongPtrW.argtypes = [wintypes.HWND, ctypes.c_int]
    user32.GetWindowLongPtrW.restype = ctypes.c_ssize_t
    user32.SetWindowLongPtrW.argtypes = [wintypes.HWND, ctypes.c_int, ctypes.c_ssize_t]
    user32.SetWindowLongPtrW.restype = ctypes.c_ssize_t
    user32.SetWindowPos.argtypes = [
        wintypes.HWND, wintypes.HWND, ctypes.c_int, ctypes.c_int,
        ctypes.c_int, ctypes.c_int, wintypes.UINT,
    ]
    user32.SetWindowPos.restype = wintypes.BOOL
    return user32


def attach_windows_desktop(window: QWidget) -> None:
    user32 = configure_user32()
    hwnd = int(window.winId())
    parent = windows_workerw()
    GWL_STYLE, GWL_EXSTYLE = -16, -20
    WS_CHILD, WS_VISIBLE, WS_POPUP = 0x40000000, 0x10000000, 0x80000000
    WS_EX_TRANSPARENT, WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW = 0x20, 0x08000000, 0x80
    style = user32.GetWindowLongPtrW(hwnd, GWL_STYLE)
    user32.SetWindowLongPtrW(hwnd, GWL_STYLE, (style | WS_CHILD | WS_VISIBLE) & ~WS_POPUP)
    ex_style = user32.GetWindowLongPtrW(hwnd, GWL_EXSTYLE)
    user32.SetWindowLongPtrW(
        hwnd, GWL_EXSTYLE, ex_style | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW
    )
    user32.SetParent(hwnd, parent)
    if user32.GetParent(hwnd) != parent:
        raise RuntimeError("Could not attach aquarium to the Windows desktop")
    rect = window.geometry()
    user32.SetWindowPos(hwnd, 1, rect.x(), rect.y(), rect.width(), rect.height(), 0x0020 | 0x0010 | 0x0004)


def attach_x11_desktop(window: QWidget) -> None:
    lib = ctypes.CDLL("libX11.so.6")
    lib.XOpenDisplay.restype = ctypes.c_void_p
    lib.XOpenDisplay.argtypes = [ctypes.c_char_p]
    lib.XInternAtom.restype = ctypes.c_ulong
    lib.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
    lib.XChangeProperty.argtypes = [
        ctypes.c_void_p, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_ulong,
        ctypes.c_int, ctypes.c_int, ctypes.c_void_p, ctypes.c_int,
    ]
    lib.XLowerWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
    lib.XFlush.argtypes = [ctypes.c_void_p]
    display = lib.XOpenDisplay(None)
    if not display:
        raise RuntimeError("Cannot connect to the X11 display")
    xid = int(window.winId())
    window_type = lib.XInternAtom(display, b"_NET_WM_WINDOW_TYPE", 0)
    desktop_type = ctypes.c_ulong(lib.XInternAtom(display, b"_NET_WM_WINDOW_TYPE_DESKTOP", 0))
    lib.XChangeProperty(
        display, xid, window_type, 4, 32, 0,
        ctypes.cast(ctypes.pointer(desktop_type), ctypes.c_void_p), 1,
    )
    lib.XLowerWindow(display, xid)
    lib.XFlush(display)
    lib.XCloseDisplay.argtypes = [ctypes.c_void_p]
    lib.XCloseDisplay(display)


class AquariumWindow(QWidget):
    def __init__(self, geometry: QRectF, preview: bool = False) -> None:
        flags = Qt.WindowType.FramelessWindowHint | Qt.WindowType.Tool
        if sys.platform.startswith("linux"):
            flags |= Qt.WindowType.WindowStaysOnBottomHint
        super().__init__(None, flags)
        self.setGeometry(geometry.toRect())
        self.setAttribute(Qt.WidgetAttribute.WA_TransparentForMouseEvents, not preview)
        self.setAttribute(Qt.WidgetAttribute.WA_ShowWithoutActivating, not preview)
        self.setFocusPolicy(Qt.FocusPolicy.NoFocus)
        self.preview = preview
        self.cap = cv2.VideoCapture(str(VIDEO))
        self.frame: QImage | None = None
        self.images = [QImage(str(ASSETS / item[0])) for item in SPECIES]
        self.fish: list[dict] = []
        for kind, (_, count, width_range, speed_range) in enumerate(SPECIES):
            for index in range(count):
                speed = random.uniform(*speed_range)
                self.fish.append({
                    "kind": kind,
                    "x": random.uniform(0, max(self.width(), 1)),
                    "y": self.height() * random.uniform(0.20, 0.72),
                    "vx": speed * (1 if index % 2 == 0 else -1),
                    "vy": random.uniform(-5, 5),
                    "width": random.uniform(*width_range),
                    "cruise": speed,
                    "phase": random.uniform(0, math.tau),
                    "depth": random.uniform(0.76, 1.0),
                })
        self.bubbles = [
            [random.uniform(0, self.width()), random.uniform(0, self.height()),
             random.uniform(0.8, 2.7), random.uniform(5, 17)]
            for _ in range(32)
        ]
        self.last_tick = time.monotonic()
        self.elapsed = 0.0
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.tick)
        self.timer.start(1000 // 24)

    def closeEvent(self, event) -> None:
        self.cap.release()
        super().closeEvent(event)

    def keyPressEvent(self, event) -> None:
        if self.preview and event.key() == Qt.Key.Key_Escape:
            QApplication.quit()

    def tick(self) -> None:
        ok, raw = self.cap.read()
        if not ok:
            self.cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
            ok, raw = self.cap.read()
        if ok:
            height, width, _ = raw.shape
            self.frame = QImage(raw.data, width, height, raw.strides[0], QImage.Format.Format_BGR888).copy()
        now = time.monotonic()
        dt = min(max(now - self.last_tick, 0.0), 0.06)
        self.last_tick = now
        self.elapsed += dt
        pointer = self.mapFromGlobal(QCursor.pos())
        pointer_here = self.rect().contains(pointer)

        for fish in self.fish:
            dx = fish["x"] - pointer.x()
            dy = fish["y"] - pointer.y()
            distance = max(math.hypot(dx, dy), 1)
            ax = ay = 0.0
            radius = 190 if fish["kind"] == 2 else 145
            if pointer_here and distance < radius:
                force = ((radius - distance) / radius) ** 2 * (170 if fish["kind"] == 2 else 290)
                ax += dx / distance * force
                ay += dy / distance * force
            ay += math.sin(self.elapsed * (0.45 if fish["kind"] == 2 else 0.9) + fish["phase"]) * (2.5 if fish["kind"] == 2 else 5)
            if abs(fish["vx"]) < fish["cruise"] * 0.7:
                ax += 9 if fish["vx"] >= 0 else -9
            if fish["x"] < 35:
                ax += 80
            if fish["x"] > self.width() - 35:
                ax -= 80
            if fish["y"] < self.height() * 0.14:
                ay += 36
            if fish["y"] > self.height() * 0.79:
                ay -= 36
            fish["vx"] = (fish["vx"] + ax * dt) * (1 - 0.14 * dt)
            fish["vy"] = (fish["vy"] + ay * dt) * (1 - 0.8 * dt)
            speed = math.hypot(fish["vx"], fish["vy"])
            maximum = max(fish["cruise"] * 3, 48)
            if speed > maximum:
                fish["vx"] *= maximum / speed
                fish["vy"] *= maximum / speed
            fish["x"] += fish["vx"] * dt
            fish["y"] += fish["vy"] * dt
            if fish["x"] < -80:
                fish["x"] = -80
                fish["vx"] = abs(fish["vx"])
            elif fish["x"] > self.width() + 80:
                fish["x"] = self.width() + 80
                fish["vx"] = -abs(fish["vx"])

        for index, bubble in enumerate(self.bubbles):
            bubble[1] -= bubble[3] * dt
            bubble[0] += math.sin(self.elapsed + index) * dt * 2
            if bubble[1] < -10:
                bubble[0] = random.uniform(0, self.width())
                bubble[1] = self.height() + 10
        self.update()

    def paintEvent(self, _event) -> None:
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.SmoothPixmapTransform)
        if self.frame:
            source = self.frame.rect()
            scale = max(self.width() / source.width(), self.height() / source.height())
            crop_width = self.width() / scale
            crop_height = self.height() / scale
            crop = QRectF((source.width() - crop_width) / 2, (source.height() - crop_height) / 2, crop_width, crop_height)
            painter.drawImage(QRectF(self.rect()), self.frame, crop)
        else:
            painter.fillRect(self.rect(), Qt.GlobalColor.black)

        painter.setBrush(Qt.BrushStyle.NoBrush)
        painter.setPen(QPen(Qt.GlobalColor.white, 0.7))
        painter.setOpacity(0.23)
        for x, y, radius, _ in self.bubbles:
            painter.drawEllipse(QPointF(x, y), radius, radius)
        painter.setOpacity(1)

        for fish in sorted(self.fish, key=lambda item: item["depth"]):
            image = self.images[fish["kind"]]
            width = fish["width"] * fish["depth"]
            height = width * image.height() / image.width()
            painter.save()
            painter.translate(fish["x"], fish["y"])
            if fish["vx"] < 0:
                painter.scale(-1, 1)
            painter.setOpacity(fish["depth"] * 0.93)
            painter.drawImage(QRectF(-width / 2, -height / 2, width, height), image)
            painter.restore()
        painter.end()


def main() -> int:
    parser = argparse.ArgumentParser(description="Interactive aquarium desktop wallpaper")
    parser.add_argument("--check", action="store_true", help="verify packaged video and fish artwork")
    parser.add_argument("--preview", action="store_true", help="open a regular preview window")
    args = parser.parse_args()
    try:
        check_assets()
    except RuntimeError as exc:
        print(f"fish: {exc}", file=sys.stderr)
        return 1
    if args.check:
        print("Aquarium assets decode correctly.")
        return 0
    if sys.platform.startswith("linux") and not args.preview:
        if os.environ.get("XDG_SESSION_TYPE", "").lower() == "wayland":
            print("fish: Linux Wayland is not supported yet. Log into an X11 desktop session.", file=sys.stderr)
            return 1
        if not os.environ.get("DISPLAY"):
            print("fish: an X11 display is required.", file=sys.stderr)
            return 1
    app = QApplication(sys.argv[:1])
    if args.preview:
        geometry = QRectF(0, 0, 1200, 752)
    else:
        geometry = QRectF(QApplication.primaryScreen().virtualGeometry())
    window = AquariumWindow(geometry, preview=args.preview)
    if sys.platform == "win32" and not args.preview:
        window.show()
        attach_windows_desktop(window)
    elif sys.platform.startswith("linux") and not args.preview:
        window.create()
        attach_x11_desktop(window)
        window.show()
        attach_x11_desktop(window)
    else:
        window.show()
    heartbeat = QTimer()
    heartbeat.timeout.connect(lambda: None)
    heartbeat.start(200)
    signal.signal(signal.SIGINT, lambda *_: app.quit())
    signal.signal(signal.SIGTERM, lambda *_: app.quit())
    print("Aquarium is swimming behind your desktop icons. Press Control-C to stop.", flush=True)
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
