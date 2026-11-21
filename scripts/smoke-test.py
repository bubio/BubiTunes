#!/usr/bin/env python3
"""Exercise BubiTunes using an interactive pseudo-terminal on macOS."""

import argparse
import fcntl
import gzip
import os
from pathlib import Path
import pty
import select
import signal
import struct
import subprocess
import tempfile
import termios
import time


def track():
    header = bytearray(128)
    tone = bytes([0x56, 0, 100, 0x56, 7, 0x3E, 0x56, 8, 1])
    one_second = bytes([0x61, 0x44, 0xAC])
    commands = tone + one_second * 8 + bytes([0x66])
    for offset, value in (
        (0, 0x206D6756), (4, len(header) + len(commands) - 4),
        (8, 0x171), (0x34, len(header) - 0x34), (0x48, 8_000_000),
    ):
        struct.pack_into("<I", header, offset, value)
    return header + commands


def await_text(master, expected, process):
    received = bytearray()
    end = time.monotonic() + 8
    while time.monotonic() < end:
        if select.select([master], [], [], 0.2)[0]:
            received.extend(os.read(master, 4096))
            if expected.encode() in received:
                return
        if process.poll() is not None:
            break
    raise AssertionError((expected, process.poll(), received[-2000:].decode(errors="replace")))


def check(executable):
    with tempfile.TemporaryDirectory() as directory:
        first = Path(directory) / "曲 ' one.vgm"
        second = Path(directory) / "second.vgz"
        first.write_bytes(track())
        second.write_bytes(gzip.compress(track()))
        master, slave = pty.openpty()
        try:
            original = termios.tcgetattr(slave)
            process = subprocess.Popen(
                [executable, "--", first, first, second], stdin=slave, stdout=slave, stderr=slave,
            )
            try:
                await_text(master, "Playing", process)
                os.write(master, b" ")
                await_text(master, "Paused", process)
                fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 12, 80, 0, 0))
                os.write(master, b"\x1b[C")
                await_text(master, "> 2", process)
                os.write(master, b"n")
                await_text(master, "> 3", process)
                os.write(master, b"p")
                await_text(master, "> 2", process)
                process.send_signal(signal.SIGINT)
                assert process.wait(timeout=8) == 0
                actual = termios.tcgetattr(slave)
                assert actual == original, ("terminal settings were not restored", original, actual)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()
        finally:
            os.close(master)
            os.close(slave)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bubitunes", type=Path)
    args = parser.parse_args()
    check(args.bubitunes.resolve())
    print("Passed interactive VGM/VGZ playback and terminal restoration.")
