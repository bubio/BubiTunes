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

Run `bubitunes` with no arguments to open the library, or give it a music folder
to register and index it. The library scans `.vgm` and `.vgz` files recursively
and searches both Japanese and English GD3 fields. The library opens with
three panes: Artist and Game on top, with a full-width Song list below.
Game uses the GD3 game name. Select
with Up/Down, move among panes with Left/Right or Tab/Shift-Tab, and press
Enter in Song to play. On a narrow terminal, only the focused pane is shown.
Choose All artists or All games to remove that filter. Missing tags appear
under Unknown artist or Unknown game.

Press `g` to cycle through columns, game groups, artist groups, and a flat
track list. Use `/browse columns` to return to columns directly.

| Key | Action |
| --- | --- |
| `l`, `d`, `r` | Open library, register a folder, rescan registered folders |
| `←`, `→`, `Tab`, `g` | Move between library panes or switch browser layout |
| `/`, `↑`, `↓` | Filter the current view or enter a slash command |
| `Enter`, `a` | Play the selection immediately or add it to the queue |
| `Tab` | Add the search selection to the queue while the search prompt is open |
| `f`, `F`, `h` | Toggle a favorite, open favorites, or open recently played tracks |
| `s`, `o` | Save the current queue as a named playlist or open saved playlists |

Press `/` to see command suggestions. Type to narrow the list, select with
Up/Down, and use Tab to complete or Enter to run. Type `/help` for shortcuts,
including `/play`, `/pause`,
`/next`, `/restart`, `/volume 35`, `/history`, and `/spectrum off`.
Ordinary text after `/` still filters the active list. Use `/search <text>`
when the search starts with a command name. `/browse artists` switches grouping
directly.

The spectrum shows twelve low-to-high bands from the played stereo PCM. The
bands automatically scale to recent peaks before volume is applied. The
separate left and right peak meters follow playback volume. The YM2608 indicators pulse for recent
register writes in FM, SSG, rhythm, and ADPCM. They indicate command activity,
which can differ from a sustained note's audible output.

Uppercase `P` switches between the playback queue and the browser while
preserving the current track, position, and queue. Use `/play list` to replace
the queue with the open collection and start from the first track. Use
`/play library` or `/play favorites` from any view. For one game, open it and
use `/play game`, or provide its GD3 name with `/play game <game name>`.
In columns, `/play list` and `S` use the songs shown after artist and game
filtering. With a game selected, Song and `/play list` follow natural filename
order (01, 02, 10) and display the GD3 titles.

Press uppercase `S` to shuffle the open list, or the entire current queue
from the player view. You can also use `/shuffle favorites`, `/shuffle library`,
or `/shuffle game <game name>`. The shuffled order stays fixed while the queue
repeats.

Uppercase `R` cycles through Repeat off, Repeat one, and Repeat queue.
Use `/repeat off`, `/repeat one`, or `/repeat all` to choose directly. These
modes apply after a VGM finishes its own playback, including its file loop.

Registered folders, favorites, history, and playlists are stored in
`~/Library/Application Support/BubiTunes/library.json`. On exit, BubiTunes also
saves the volume, repeat mode, spectrum visibility, queue order, and playback
position. When started without explicit track files, it restores the queue and
loads the current track paused at the saved position. Press Space to resume.
Supplying track files starts a new queue. Use `BUBITUNES_LIBRARY_DIR` to specify
a different storage directory.

The initial player accepts files for a single YM2608. YM2203 playback is planned
for a later Core release. For local development against a sibling Core clone:

```sh
BUBITUNES_CORE_DIR=../Bubilator88Core swift test
BUBITUNES_CORE_DIR=../Bubilator88Core swift run bubitunes track.vgz
```

BubiTunes is distributed under GPL v2. The OPNA synthesis includes work based
on cisc's fmgen. See [FMGEN-NOTICE.txt](FMGEN-NOTICE.txt). The six substitute
rhythm WAV files originate from the Bubilator88 project.
