# VitroManager

Desktop companion app for [Vitro Launcher](../README.md). Point it at a
`GAME` folder on your muOS SD card — inside the launcher folder
(`MUOS/application/Vitro Launcher/GAME`) or at the root of the card
(`<SD card>/GAME`) — and it lets you:

- browse the games already in the library, with their cover art. Open
  several `GAME` folders at once (e.g. one per SD card) and they show
  as one merged library, just like the launcher displays them. Sort
  A–Z or by playtime;
- view play stats (**Stats**): playtime, play count and last-played
  date per game, read from the `stats.json` the launcher writes into
  each game folder;
- back up the library (**Back Up**): copies every open `GAME` folder —
  roms, artwork, `info.cfg`, stats and in-folder saves — into a
  `Vitro Game Backups/GAME` folder inside a destination of your choice
  (a second open GAME folder backs up to `GAME 2`, and so on). Later
  runs are incremental: only new and changed files (fresh save games,
  updated stats, added titles) are copied, and nothing is ever deleted
  from the backup. The destination is remembered and can be changed in
  Settings;
- a settings screen (**⚙**): manage the open GAME folders, change the
  backup folder, and store a [SteamGridDB](https://www.steamgriddb.com)
  API key. With a key set, every artwork slot gets a **SteamGridDB…**
  button: search by game title, pick the matching game, and choose from
  its art — grids become covers, heroes become backgrounds, icons
  become icons. Chosen images go through the same downscaling as local
  imports (free key: steamgriddb.com → Preferences → API);
- change a game's name, system, cover, icon, or background — picked
  from local files, or searched on SteamGridDB;
- delete a title (from the edit dialog): the game folder is moved to
  the system trash — recoverable, nothing is destroyed. If one folder
  declares several titles, only the selected entry is removed from its
  `info.cfg` and all files stay;
- add a new game through a short wizard — pick the system, the rom / iso /
  PortMaster script, and the artwork. VitroManager creates the game folder,
  copies the files in, and writes the `info.cfg` the launcher expects
  (see [docs/GAME-LIBRARY.md](../docs/GAME-LIBRARY.md) for the format);
- keep artwork device-sized: images are downscaled on import (covers to
  480x720, icons to 160x160, backgrounds to 960x720), and **Optimize
  Images** applies the same budgets to a library that already exists.

## Running from source

Requires Node.js 20+.

```bash
cd VitroManager
npm install
npm start
```

If you launch from a terminal inside an Electron-based editor (Cursor,
VS Code) and the app crashes immediately, the editor exports
`ELECTRON_RUN_AS_NODE` into the shell — run
`env -u ELECTRON_RUN_AS_NODE npm start` instead.

## Building installers

```bash
npm run dist:mac     # .dmg + .zip
npm run dist:win     # NSIS installer + .zip
npm run dist:linux   # AppImage + .deb
npm run dist         # all three
```

Output lands in `VitroManager/dist/`. Windows and Linux builds can be
produced from macOS for testing, but for signed releases build each target
on its own platform (or in CI).

## Notes

- Cover art is written into the game folder as `default.png`/`.jpg`,
  icons as `icon.*`, and backgrounds as `bg.*`; the rom keeps its
  original filename. PNG sources stay PNG (transparency survives),
  everything else is saved as JPEG. Formats the importer can't decode
  (webp/bmp/gif) are copied through untouched.
- The launcher shows covers in a 2:3 tile by default, icons are small
  squares, and backgrounds are fullscreen.
- The opened GAME folders are remembered between launches.
