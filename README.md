# BubiTunes - PC-88 OPNA Music Player

[![Latest release](https://img.shields.io/github/v/release/bubio/BubiTunes)](https://github.com/bubio/BubiTunes/releases/latest)
[![License](https://img.shields.io/github/license/bubio/BubiTunes)](LICENSE)
[![macOS](https://github.com/bubio/BubiTunes/actions/workflows/macos.yml/badge.svg)](https://github.com/bubio/BubiTunes/actions/workflows/macos.yml)
[![Linux](https://github.com/bubio/BubiTunes/actions/workflows/linux.yml/badge.svg)](https://github.com/bubio/BubiTunes/actions/workflows/linux.yml)
[![Windows](https://github.com/bubio/BubiTunes/actions/workflows/windows.yml/badge.svg)](https://github.com/bubio/BubiTunes/actions/workflows/windows.yml)

BubiTunes is a terminal music player for PC-88 VGM and VGZ files recorded from
a single YM2608 (OPNA). It uses [Bubilator88Core](https://github.com/bubio/Bubilator88Core)
for sound synthesis. Substitute rhythm samples are built into the executable,
and playback requires no PC-88 BIOS files.

## Features

- Play one or more files directly or browse a library indexed by artist and game.
- Search Japanese and English GD3 tags, save favorites, and revisit recently played tracks.
- Shuffle or repeat a queue and resume it from the saved position.
- View a twelve-band spectrum, stereo peak meters, and YM2608 register activity for FM, SSG, rhythm, and ADPCM.

## Download

Download the package for your platform from [GitHub Releases](https://github.com/bubio/BubiTunes/releases).
The version comes from the tag, so a tag of `v1.2.3` uses `1.2.3` in each filename.

| Platform | Release package | CI artifact |
| --- | --- | --- |
| [macOS 15+ (Apple Silicon)](https://github.com/bubio/BubiTunes/actions/workflows/macos.yml) | `bubitunes-<version>-macos-arm64.tar.gz` | `bubitunes-macos-arm64` |
| [Linux (x64, built on Ubuntu 22.04)](https://github.com/bubio/BubiTunes/actions/workflows/linux.yml) | `bubitunes-<version>-linux-x64.tar.gz` | `bubitunes-linux-x64` |
| [Windows (x64)](https://github.com/bubio/BubiTunes/actions/workflows/windows.yml) | `bubitunes-<version>-windows-x64.zip` | `bubitunes-windows-x64` |

CI artifacts are available on successful workflow runs on `main`. The Linux
and Windows packages include the Swift runtime. The Windows ZIP contains only
`bubitunes.exe`.

## Usage

Extract the package and run the executable from a terminal.

```sh
./bubitunes "track 1.vgz" "track 2.vgm"
./bubitunes "$HOME/Music/PC-88"
```

On Windows, use `.\bubitunes.exe` in PowerShell.

```powershell
.\bubitunes.exe "track 1.vgz"
```

Passing a folder registers it and scans recursively for `.vgm` and `.vgz` files.
Run BubiTunes without arguments to open the library and restore the saved
queue. The current track loads paused at its saved position. Passing track
files starts a new queue.

| Key | Action |
| --- | --- |
| Space, `←` / `→` or `p` / `n` | Pause or resume, or go to the previous or next track in the player |
| `+` / `-`, `q` | Adjust volume or quit |
| `l`, `d`, `r` | Open the library, register a folder, or rescan registered folders |
| `↑` / `↓`, `←` / `→`, `Tab` / `Shift+Tab` | Select an entry or move between library panes |
| `g` | Cycle through columns, game groups, artist groups, and a flat track list |
| `Enter`, `a` | Play the displayed list from the selected track, or append the selected track |
| `f`, `F`, `h` | Toggle a favorite, open favorites, or open recently played tracks |
| `P`, `S`, `R` | Switch between queue and browser, shuffle the current list, or cycle through repeat modes |

The default library view shows Artist and Game above Song. Choose **All artists**
or **All games** to clear the corresponding filter. Untagged entries appear
under **Unknown artist** or **Unknown game**. When a game is selected, tracks
appear in natural filename order (01, 02, 10) with their GD3 titles. On narrow
terminals, the browser shows the focused pane.

Press `/` to filter the active list or bring up slash command suggestions.
Use the arrow keys to select a suggestion, `Tab` to complete it, and `Enter`
to run it. When filtering, `Tab` appends the selected result to the queue.
Use `/search <text>` for searches that begin with a command name. Run `/help`
to see all commands.

- `/browse columns`, `/browse games`, `/browse artists`, and `/browse tracks` select a library layout.
- `/play list` plays the displayed collection from the first track. Use `/play library`,
  `/play favorites`, or `/play game <game name>` to start another collection.
- `/shuffle library`, `/shuffle favorites`, and `/shuffle game <game name>`
  shuffle a collection. The order stays fixed when the queue repeats.
- `/repeat off`, `/repeat one`, and `/repeat all` control queue repeat. A VGM's
  embedded loop plays one additional time before the queue repeat mode takes effect.
- `/volume 35` sets the volume, and `/spectrum off` hides the spectrum.

The player saves registered folders, favorites, history, and playback state in
`BubiTunes/library.json` under the platform's application support directory.
On macOS, this is `~/Library/Application Support/BubiTunes/library.json`.
Set `BUBITUNES_LIBRARY_DIR` to use another directory.

## Building

CI uses Swift 6.4.3. On Linux, install zlib development headers and pkg-config
before building. On Ubuntu, run `sudo apt-get install zlib1g-dev pkg-config`.

| Platform | Build, test, and package |
| --- | --- |
| macOS | `bash scripts/build-macos.sh` |
| Linux | `bash scripts/build-linux.sh` |
| Windows (PowerShell) | `./scripts/build-windows.ps1` |

The scripts place the package in `dist/` using the filename
`bubitunes-<platform>-<arch>.<ext>`. They run the release test suite and check
that the packaged executable starts with `--help`. The macOS executable is
ad hoc signed.

SwiftPM uses the published Bubilator88Core dependency by default. To develop
against a sibling checkout, set `BUBITUNES_CORE_DIR` when running SwiftPM or
the packaging scripts.

```sh
BUBITUNES_CORE_DIR=../Bubilator88Core swift test
BUBITUNES_CORE_DIR=../Bubilator88Core swift run bubitunes track.vgz
```

On macOS, run the interactive smoke test against a built executable in a
session with audio output.

```sh
python3 scripts/smoke-test.py "$(swift build --show-bin-path)/bubitunes"
```

## License and credits

BubiTunes is distributed under the [GNU General Public License v2](LICENSE).
OPNA synthesis includes work based on cisc's fmgen. The embedded substitute
rhythm samples come from Bubilator88.

- [fmgen notice](FMGEN-NOTICE.txt)
- [miniaudio notice](https://github.com/bubio/BubiTunes/blob/main/Sources/CMinAudio/NOTICE.txt)
- [zlib notice](https://github.com/bubio/BubiTunes/blob/main/Sources/CZlibVendored/NOTICE.txt)
