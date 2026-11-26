#!/usr/bin/env python3
"""Exercise BubiTunes using an interactive pseudo-terminal on macOS."""

import argparse
from contextlib import contextmanager
import fcntl
import gzip
import json
import os
from pathlib import Path
import pty
import re
import select
import signal
import struct
import subprocess
import tempfile
import termios
import time


def track(title=None, game="", artist="", seconds=8):
    header = bytearray(128)
    tone = bytes([0x56, 0, 100, 0x56, 7, 0x3E, 0x56, 8, 1])
    one_second = bytes([0x61, 0x44, 0xAC])
    commands = tone + one_second * seconds + bytes([0x66])
    tags = b""
    if title:
        fields = ["", title, "", game, "PC-88", "", "", artist, "", "", ""]
        strings = ("\0".join(fields) + "\0").encode("utf-16-le")
        tags = b"Gd3 " + struct.pack("<II", 0x100, len(strings)) + strings
        struct.pack_into("<I", header, 0x14, len(header) + len(commands) - 0x14)
    for offset, value in (
        (0, 0x206D6756), (4, len(header) + len(commands) + len(tags) - 4),
        (8, 0x171), (0x34, len(header) - 0x34), (0x48, 8_000_000),
    ):
        struct.pack_into("<I", header, offset, value)
    return header + commands + tags


def await_text(master, expected, process):
    texts = (expected,) if isinstance(expected, str) else expected
    received = bytearray()
    end = time.monotonic() + 8
    while time.monotonic() < end:
        if select.select([master], [], [], 0.2)[0]:
            received.extend(os.read(master, 4096))
            plain = re.sub(rb"\x1b\[[0-9;?]*[A-Za-z]", b"", received)
            if all(text.encode() in received or text.encode() in plain for text in texts):
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
                env={**os.environ, "BUBITUNES_LIBRARY_DIR": str(Path(directory) / "store")},
            )
            try:
                await_text(master, "Playing", process)
                os.write(master, b" ")
                await_text(master, "Paused", process)
                fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 12, 80, 0, 0))
                os.write(master, b"\x1b[C")
                await_text(master, "› 2", process)
                os.write(master, b"n")
                await_text(master, "› 3", process)
                os.write(master, b"p")
                await_text(master, "› 2", process)
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


def check_library(executable):
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        folder = root / "Music"
        folder.mkdir()
        (folder / "曲.vgm").write_bytes(track("曲のテーマ", "架空のゲーム", "作曲者"))
        (folder / "Other.vgz").write_bytes(gzip.compress(track()))
        environment = {**os.environ, "BUBITUNES_LIBRARY_DIR": str(root / "store")}

        @contextmanager
        def player(arguments, viewport=(24, 100)):
            master, slave = pty.openpty()
            try:
                fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", *viewport, 0, 0))
                process = subprocess.Popen(
                    [executable, *arguments], stdin=slave, stdout=slave, stderr=slave, env=environment,
                )
                try:
                    yield master, process
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.wait()
            finally:
                os.close(master)
                os.close(slave)

        def quit_player(master, process):
            os.write(master, b"q")
            await_text(master, "\x1b[?1049l", process)
            assert process.wait(timeout=8) == 0

        def interact(arguments, actions, viewport=(24, 100)):
            with player(arguments, viewport) as (master, process):
                for keys, expected in actions:
                    if keys:
                        while select.select([master], [], [], 0)[0]:
                            os.read(master, 4096)
                        os.write(master, keys)
                    await_text(master, expected, process)
                quit_player(master, process)

        interact([folder], [
            (b"", "曲のテーマ"),
            (b"\x1b[B", "› 作曲者"),
            (b"\t", "▸ Game"),
            (b"\x1b[B", "› 架空のゲーム"),
            (b"\x1b[C", "▸ Song"),
            (b"\x1b[Z", "▸ Game"),
            (b"/browse games\r", "Unknown game"),
            (b"\r", "曲のテーマ"),
            (b"\x1b[D", "Unknown game"),
            (b"/", "Matching commands"),
            (b"br", "/browse columns|games|artists|tracks"),
            (b"\t", "browse ▏"),
            (b"artists\r", "Unknown artist"),
            (b"\r", "Library / Artists / 作曲者"),
            (b"\r", "曲のテーマ"),
            (b"\x1b[D", "Library / Artists / 作曲者"),
            ("/曲".encode(), "› 曲のテーマ"),
            (b"\r", "Playing"),
            (b"", "● SSG"),
            (b"/pa", "/pause"),
            (b"\r", "Paused"),
            (b"/vo", "/volume 0–100"),
            (b"\t", "volume ▏"),
            (b"35\r", "Vol 35%"),
            (b"/p", "Matching commands  3"),
            (b"\x1b[B", "› /play"),
            (b"\r", "Playing"),
            (b"/spectrum off\r", "Spectrum off."),
            (b"/help\r", "Slash commands"),
            (b"\x1b", "Library / Search"),
            (b"P", "Playback queue"),
            (b"fF", "♥ 曲のテーマ"),
            (b"h", "Recently Played"),
        ])
        interact([], [
            (b"", "曲のテーマ"),
            (b"/browse games\r", "Unknown game"),
            ("/search 曲\r".encode(), "› ♥ 曲のテーマ"),
            (b"F", "Favorites  1"),
            (b"h", "Recently Played"),
            (b"/play library\r", "Playback queue  2"),
            (b"/play favorites\r", "Playback queue  1"),
            (b"/play library\r", "Playback queue  2"),
            ("/play game 架空のゲーム\r".encode(), "Playback queue  1"),
            (b"l", "Library / Games"),
            (b"\r", "Library / Games / 架空のゲーム"),
            (b"/play list\r", "Playback queue  1"),
            (b"F", "Favorites  1"),
            (b"/play list\r", "Playback queue  1"),
            (b"F", "Favorites  1"),
            (b"S", "Playback queue · Shuffled  1"),
            (b"/shuffle library\r", "Playback queue · Shuffled  2"),
            ("/shuffle game 架空のゲーム\r".encode(), "Playback queue · Shuffled  1"),
            (b"/browse columns\r", "▸ Artist"),
            (b"\x1b[B", "› 作曲者"),
            (b"\x1b[C", "▸ Game"),
            (b"\x1b[B", "› 架空のゲーム"),
            (b"/play list\r", "Playback queue  1"),
            (b"/browse columns\r", "▸ Game"),
            (b"\x1b[C", "▸ Song"),
            (b" ", "Paused"),
            (b"\r", "Playing"),
            (b"\x1b[D", "▸ Game"),
        ])

        pack = root / "Pack"
        pack.mkdir()
        (pack / "01 Opening.vgm").write_bytes(track("Zulu", "Pack Game", "Pack Artist"))
        (pack / "02 Battle.vgz").write_bytes(gzip.compress(track("Alpha", "Pack Game", "Pack Artist")))
        (pack / "10 Ending.vgm").write_bytes(track("Beta", "Pack Game", "Pack Artist"))
        (pack / "03 Guest.vgm").write_bytes(track("Guest Tune", "Pack Game", "Side Artist"))
        (pack / "04 Side.vgm").write_bytes(track("Side Tune", "Side Game", "Pack Artist"))
        environment["BUBITUNES_LIBRARY_DIR"] = str(root / "pack-store")
        interact([pack], [
            (b"", "Pack Artist"),
            (b"\x1b[B", "› Pack Artist"),
            (b"\t", "▸ Game"),
            (b"\x1b[B", "› Pack Game"),
            (b"\t", "▸ Song"),
            (b"\x1b[B", "› Alpha"),
            (b"\r", ("Playing", "▌ Alpha")),
            (b"P", ("Playback queue  3", "1  01 Opening.vgm", "› 2  02 Battle.vgz", "3  10 Ending.vgm")),
            (b"p", "› 1  01 Opening.vgm"),
            (b"n", "› 2  02 Battle.vgz"),
            (b" ", "Paused"),
            (b"P", "▸ Song"),
            (b"\x1b[D", "▸ Game"),
            (b"\x1b[B", "› Side Game"),
            (b"P", ("Playback queue  3", "› 2  02 Battle.vgz")),
            (b" ", "Playing"),
            (b"n", "› 3  10 Ending.vgm"),
            (b"p", "› 2  02 Battle.vgz"),
            (b"/volume 29\r", "Vol 29%"),
            (b"/repeat all\r", "Repeat queue"),
            (b"/spectrum off\r", "Spectrum off   /spectrum on"),
            (b"", "0:01 / 0:08"),
            (b" ", "Paused"),
        ])
        interact([], [
            (b"", ("Paused", "Alpha", "Vol 29%", "Repeat queue", "Spectrum off   /spectrum on", "0:01 / 0:08")),
            (b"P", ("1  01 Opening.vgm", "› 2  02 Battle.vgz", "3  10 Ending.vgm")),
            (b" ", "Playing"),
            (b"", "0:02 / 0:08"),
        ])
        interact([pack / "10 Ending.vgm"], [
            (b"", ("Playing", "Beta", "› 1  10 Ending.vgm", "0:00 / 0:08", "Vol 29%")),
        ])

        interact([], [
            (b"", "Pack Artist"),
            (b"/Tune ", "▹ Guest Tune"),
            (b"\x1b[B", "▹ Side Tune"),
            (b"\r", ("Playing", "▌ Side Tune", "› Side Tune")),
            (b"\x1b[A", "▹ Guest Tune"),
            (b"P", ("Playback queue  2", "1  03 Guest.vgm", "› 2  04 Side.vgm")),
            (b"P", "Library / Search"),
            (b"/search Alpha\r", "▹ Alpha"),
            (b"f", "Added to favorites."),
            (b"/search Beta\r", "▹ Beta"),
            (b"f", "Added to favorites."),
            (b"F", "Favorites  2"),
            (b"\x1b[B", "▹ ♥ Alpha"),
            (b"\r", "▌ Alpha"),
            (b"P", ("Playback queue  2", "1  10 Ending.vgm", "› 2  02 Battle.vgz")),
        ])

        environment["BUBITUNES_LIBRARY_DIR"] = str(root / "store")
        short_track = root / "Short.vgm"
        short_track.write_bytes(track(seconds=2))
        interact([short_track], [
            (b"", ("Playing", "› 1  Short.vgm")),
            (b"P", ("▸ Artist", "› All artists")),
            (b"", "Stopped"),
            (b"/spectrum off\r", "Spectrum off."),
            (b"d/does-not-exist\r", "Folder not found."),
        ], viewport=(10, 80))

        shared_store = root / "shared-store"
        environment["BUBITUNES_LIBRARY_DIR"] = str(shared_store)
        with player([]) as (idle_master, idle):
            await_text(idle_master, "No track loaded", idle)
            interact([pack / "10 Ending.vgm"], [
                (b"", "0:01 / 0:08"),
                (b" ", "Paused"),
            ])
            library_file = shared_store / "library.json"
            saved = json.loads(library_file.read_text())["playbackQueue"]
            assert saved["frame"] >= 44_100, saved
            os.write(idle_master, b"/volume 35\r")
            await_text(idle_master, "Vol 35%", idle)
            quit_player(idle_master, idle)
            updated = json.loads(library_file.read_text())
            assert updated["playbackQueue"] == saved, updated
            assert round(updated["playbackPreferences"]["volume"] * 100) == 35, updated


def check_repeat(executable):
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        first = root / "Repeat first.vgm"
        second = root / "Repeat second.vgm"
        first.write_bytes(track(seconds=2))
        second.write_bytes(track(seconds=2))
        master, slave = pty.openpty()
        try:
            process = subprocess.Popen(
                [executable, first, second], stdin=slave, stdout=slave, stderr=slave,
                env={**os.environ, "BUBITUNES_LIBRARY_DIR": str(root / "store")},
            )
            try:
                await_text(master, "› 1  Repeat first.vgm", process)
                os.write(master, b"R")
                await_text(master, "Repeat one", process)
                await_text(master, "0:01 / 0:02", process)
                await_text(master, "0:00 / 0:02", process)
                os.write(master, b"/repeat all\r")
                await_text(master, "Repeat queue", process)
                await_text(master, "› 2  Repeat second.vgm", process)
                await_text(master, "› 1  Repeat first.vgm", process)
                os.write(master, b"q")
                await_text(master, "\x1b[?1049l", process)
                assert process.wait(timeout=8) == 0
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
    check_library(args.bubitunes.resolve())
    check_repeat(args.bubitunes.resolve())
    print("Passed interactive VGM/VGZ playback, library, shuffle, repeat, saved playback state, compact layout, notices, and terminal restoration.")
