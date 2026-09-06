"""Private compositor search UI regression fixture."""
import argparse
import os
import select
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import tty
from PIL import Image
from pathlib import Path


NEEDLE = "HISTORY-NEEDLE-é中"


def child(directory):
    root = Path(directory)
    tty.setraw(0)
    assert os.get_terminal_size(1).columns == 80
    assert os.get_terminal_size(1).lines == 32
    # Force the needle into scrollback and across a physical wrap boundary.
    os.write(1, (("history filler\r\n" * 40) + "A" * 79 + NEEDLE +
                 ("\r\nhistory tail\r\n" * 30) + "\x1b[?25l\x1b[41m \x1b[0m\r\n" +
                 ("history tail\r\n" * 39) + "\x1b[?2004h").encode())
    (root / "ready").touch()
    while not (root / "closed").exists():
        time.sleep(.01)
    received = bytearray()
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        ready, _, _ = select.select([0], [], [], .05)
        if ready:
            received.extend(os.read(0, 4096))
            if received.endswith(b"\x1b[201~"):
                break
    expected = b"x\x1b[200~" + NEEDLE.encode() + b"\x1b[201~"
    (root / "received").write_bytes(received)
    assert received == expected, (received, expected)
    assert NEEDLE.encode() not in received[:1], "search query reached PTY before close"
    (root / "done").touch()
    while not (root / "stop").exists():
        time.sleep(.01)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--terminal", required=True)
    p.add_argument("--weston", required=True)
    p.add_argument("--seat", required=True)
    p.add_argument("--wl-copy", required=True)
    args = p.parse_args()
    with tempfile.TemporaryDirectory(prefix="cudaterm-search-") as directory:
        root = Path(directory)
        env = dict(os.environ, XDG_RUNTIME_DIR=directory, WAYLAND_DISPLAY="search-test")
        os.mkfifo(root / "keys", 0o600)
        env["CUDATERM_TEST_KEYS"] = str(root / "keys")
        env.pop("DISPLAY", None)
        env["CUDATERM_TRACE"] = str(root / "search.csv")
        with (root / "weston.log").open("w") as log:
            weston = subprocess.Popen(
                [args.weston, "--backend=headless", "--renderer=gl", "--shell=desktop",
                 "--socket=search-test", "--no-config", "--debug", "--modules=" + args.seat,
                 "--width=1200", "--height=900"], env=env, stdout=log, stderr=log)
            terminal = None
            try:
                deadline = time.monotonic() + 10
                while not (root / "search-test").exists():
                    if time.monotonic() > deadline:
                        raise RuntimeError("timed out: search-test")
                    time.sleep(.01)
                terminal = subprocess.Popen(
                    [args.terminal, "--cols", "80", "--rows", "32", "-e", sys.executable,
                     str(Path(__file__).resolve()), "--child", directory], env=env)
                while not (root / "ready").exists():
                    if time.monotonic() > deadline + 10:
                        raise RuntimeError("timed out: ready")
                    time.sleep(.01)
                # Weston focus/configure delivery can lag the child readiness marker.
                frame_deadline = time.monotonic() + 5
                while not (root / "search.csv").exists() or "gl_texture_swap" not in (root / "search.csv").read_text():
                    if time.monotonic() > frame_deadline:
                        raise RuntimeError("timed out: initial frame")
                    time.sleep(.01)
                time.sleep(.3)

                with (root / "keys").open("wb", buffering=0) as keys:
                    def event(code, value):
                        keys.write(struct.pack("=II", code, value))
                    def chord(key, shift=True):
                        for code, value in ((29, 1), (42, 1) if shift else (0, 0),
                                            (key, 1), (key, 0), (42, 0) if shift else (0, 0),
                                            (29, 0)):
                            if code:
                                event(code, value)
                    # Ctrl-Shift-F opens the local search prompt.
                    event(42, 1); event(104, 1); event(104, 0); event(42, 0)
                    time.sleep(.2)
                    def capture(name, marker):
                        for png in root.glob("*.png"): png.unlink()
                        subprocess.run([str(Path(args.weston).with_name("weston-screenshooter"))],
                                       env=env, cwd=directory, check=True,
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                       timeout=5)
                        image = Image.open(next(root.glob("*.png"))).convert("RGB")
                        pixels = [(x, y) for y in range(image.height) for x in range(image.width)
                                  if (image.getpixel((x, y))[0] >= 120 and
                                      image.getpixel((x, y))[1] < 10 and
                                      image.getpixel((x, y))[2] < 10)]
                        if marker:
                            assert len(pixels) == 128, (name, len(pixels))
                        else:
                            assert not pixels, (name, len(pixels))
                        image.save(f"bench/window-search-{name}.png")
                        return pixels
                    before_marker = capture("before", True)
                    chord(33)
                    subprocess.run([args.wl_copy], input=NEEDLE.encode(), env=env, check=True, timeout=5)
                    chord(47)  # Ctrl-Shift-V: query remains local
                    time.sleep(.2)
                    capture("active", False)
                    event(28, 1); event(28, 0)  # Enter: next
                    event(42, 1); event(28, 1); event(28, 0); event(42, 0)  # Shift-Enter
                    # Exercise no-match and return to the known match.
                    event(29, 1); event(22, 1); event(22, 0); event(29, 0)  # Ctrl-U
                    subprocess.run([args.wl_copy], input=b"absent", env=env, check=True, timeout=5)
                    chord(47)
                    time.sleep(.1)
                    event(29, 1); event(22, 1); event(22, 0); event(29, 0)
                    subprocess.run([args.wl_copy], input=NEEDLE.encode(), env=env, check=True, timeout=5)
                    chord(47)
                    time.sleep(.2)
                    subprocess.run([args.wl_copy], input=b"copy-marker", env=env,
                                    check=True, timeout=5)
                    time.sleep(.2)
                    chord(46)  # Ctrl-Shift-C copies active match
                    time.sleep(.2)
                    paste = subprocess.run(
                        [str(Path(args.wl_copy).with_name("wl-paste")), "--no-newline"],
                        env=env, check=True, capture_output=True, timeout=5).stdout
                    assert paste == NEEDLE.encode(), paste
                    event(1, 1); event(1, 0)  # Escape closes and restores viewport.
                    restored_marker = capture("restored", True)
                    assert restored_marker == before_marker, (before_marker, restored_marker)
                    (root / "closed").touch()
                    event(45, 1); event(45, 0)  # x proves normal input is restored.
                    chord(47)  # bracketed paste reaches the child after close
                    (root / "stop").touch()
                done_deadline = time.monotonic() + 10
                while not (root / "done").exists():
                    if time.monotonic() > done_deadline:
                        raise RuntimeError("timed out: done")
                    time.sleep(.01)
                assert terminal.wait(timeout=5) == 0
                shutil.copyfile(root / "search.csv", "bench/window-search-search.csv")
                print("PASS: local UTF-8 history search, navigation, copy and normal input after close")
            except Exception:
                try:
                    subprocess.run([str(Path(args.weston).with_name("weston-screenshooter"))],
                                   env=env, cwd=directory, check=False,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                   timeout=5)
                    if (root / "search.csv").exists():
                        shutil.copyfile(root / "search.csv", "bench/window-search-debug.csv")
                    pngs = list(root.glob("*.png"))
                    if pngs: shutil.copyfile(pngs[0], "bench/window-search-debug.png")
                finally:
                    raise
            finally:
                (root / "closed").touch()
                (root / "stop").touch()
                if terminal and terminal.poll() is None:
                    terminal.terminate(); terminal.wait(timeout=5)
                weston.terminate(); weston.wait(timeout=5)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--child":
        child(sys.argv[2])
    else:
        main()
