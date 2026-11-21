# BubiTunes

BubiTunes plays PC-88 YM2608 (OPNA) VGM and VGZ files in a terminal. It uses
[Bubilator88Core](https://github.com/bubio/Bubilator88Core) for synthesis and
includes substitute OPNA rhythm samples. It runs without PC-88 BIOS files.

The initial standalone build targets Apple Silicon Macs running macOS 15 or
later. Extract the release archive and keep `BubiTunesRhythm` next to the CLI.

```sh
./bubitunes "track 1.vgz" "track 2.vgm"
```

Press Space to pause or resume, Left/Right or p/n to change tracks, +/− to adjust
volume, and q to quit. Files with a loop play that section one additional time.
The File menu in Bubilator88 can open tracks using the bundled CLI.

The initial player accepts files for a single YM2608. YM2203 playback is planned
for a later Core release. For local development against a sibling Core clone:

```sh
BUBITUNES_CORE_DIR=../Bubilator88Core swift test
BUBITUNES_CORE_DIR=../Bubilator88Core swift run bubitunes track.vgz
```

BubiTunes is distributed under GPL v2. The OPNA synthesis includes work based
on cisc's fmgen. See [FMGEN-NOTICE.txt](FMGEN-NOTICE.txt). The six substitute
rhythm WAV files originate from the Bubilator88 project.
