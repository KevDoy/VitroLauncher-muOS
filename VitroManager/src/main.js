const { app, BrowserWindow, ipcMain, dialog, nativeImage, protocol, shell } = require('electron');
const path = require('path');
const fs = require('fs');
const fsp = fs.promises;

let mainWindow = null;

// ---------------------------------------------------------------------------
// Settings (remembers the opened GAME folders)
// ---------------------------------------------------------------------------

const settingsPath = () => path.join(app.getPath('userData'), 'settings.json');

function loadSettings() {
    try {
        return JSON.parse(fs.readFileSync(settingsPath(), 'utf8'));
    } catch {
        return {};
    }
}

function saveSettings(settings) {
    try {
        fs.writeFileSync(settingsPath(), JSON.stringify(settings, null, 2));
    } catch (err) {
        console.error('Failed to save settings:', err);
    }
}

// ---------------------------------------------------------------------------
// Library scanning
// ---------------------------------------------------------------------------

const IMAGE_EXTS = new Set(['.png', '.jpg', '.jpeg', '.bmp', '.webp', '.gif']);

// ---------------------------------------------------------------------------
// info.cfg - the launcher's hand-editable game descriptor. One
// "key = value" per line; lines starting with # (or ;) are comments;
// a folder with several titles uses one [game] section per title.
// Empty values ("bg = ") mean "not set" so every field can be listed
// as a template. Legacy info.json files are still read (and get
// rewritten as info.cfg on the next edit).
// ---------------------------------------------------------------------------

const CFG_FIELDS = ['name', 'system', 'file', 'img', 'icon', 'bg'];

function parseCfg(text) {
    const entries = [];
    let current = null;
    const push = () => {
        current = {};
        entries.push(current);
    };
    for (const rawLine of text.split(/\r?\n/)) {
        const line = rawLine.trim();
        if (!line || line.startsWith('#') || line.startsWith(';')) continue;
        if (line.startsWith('[') && line.endsWith(']')) {
            push();
            continue;
        }
        const eq = line.indexOf('=');
        if (eq === -1) continue;
        const key = line.slice(0, eq).trim();
        const value = line.slice(eq + 1).trim();
        if (!key || !value) continue;
        if (!current) push();
        current[key] = value;
    }
    return entries.filter((entry) => Object.keys(entry).length > 0);
}

// Every known field is written even when empty, so hand-editing a
// generated file is a fill-in-the-blanks job.
function serializeCfg(entries) {
    const blocks = entries.map((entry) => {
        const lines = entries.length > 1 ? ['[game]'] : [];
        for (const field of CFG_FIELDS) {
            const value = entry[field];
            lines.push(value ? `${field} = ${value}` : `${field} =`);
        }
        return lines.join('\n');
    });
    return blocks.join('\n\n') + '\n';
}

async function readInfo(folderPath) {
    try {
        const raw = await fsp.readFile(path.join(folderPath, 'info.cfg'), 'utf8');
        return parseCfg(raw);
    } catch (err) {
        if (err.code !== 'ENOENT') throw err;
    }
    // Legacy folder that still has an info.json
    const raw = await fsp.readFile(path.join(folderPath, 'info.json'), 'utf8');
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [parsed];
}

// Play statistics the launcher writes into each game folder
// (stats.json, keyed by rom file - see src/stats.lua in the launcher).
async function readStats(folderPath) {
    try {
        const raw = await fsp.readFile(path.join(folderPath, 'stats.json'), 'utf8');
        const parsed = JSON.parse(raw);
        return parsed && typeof parsed === 'object' ? parsed : {};
    } catch {
        return {};
    }
}

// Short display label for a GAME folder root: the containing folder's
// name ("SD2" for /Volumes/SD2/GAME, "Vitro Launcher" for the app dir).
function rootLabel(gameDir) {
    return path.basename(path.dirname(gameDir)) || gameDir;
}

// Scans one or more GAME folder roots and merges the results. Each game
// carries its root so cards can show which folder it lives in and edits
// land in the right place.
async function scanLibrary(gameDirs) {
    const result = { games: [], skipped: [] };

    for (const gameDir of gameDirs) {
        const dirents = await fsp.readdir(gameDir, { withFileTypes: true });

        for (const dirent of dirents) {
            if (!dirent.isDirectory() || dirent.name.startsWith('.')) continue;
            const folderPath = path.join(gameDir, dirent.name);

            let entries;
            try {
                entries = await readInfo(folderPath);
            } catch (err) {
                result.skipped.push({
                    folder: dirent.name,
                    reason: err.code === 'ENOENT' ? 'no info.cfg' : 'invalid game info: ' + err.message,
                });
                continue;
            }

            const stats = await readStats(folderPath);

            entries.forEach((entry, index) => {
                if (!entry || typeof entry !== 'object') return;
                const abs = (rel) =>
                    rel && typeof rel === 'string' ? path.join(folderPath, rel) : null;
                const fileExists = (rel) => {
                    const p = abs(rel);
                    return p ? fs.existsSync(p) : false;
                };
                const gameStats = (entry.file && stats[entry.file]) || {};
                result.games.push({
                    playSeconds: gameStats.playSeconds || 0,
                    playCount: gameStats.playCount || 0,
                    lastPlayed: gameStats.lastPlayed || null,
                    rootDir: gameDir,
                    rootLabel: rootLabel(gameDir),
                    folder: dirent.name,
                    folderPath,
                    entryIndex: index,
                    entryCount: entries.length,
                    name: entry.name || dirent.name,
                    system: entry.system || null,
                    file: entry.file || null,
                    fileExists: fileExists(entry.file),
                    img: entry.img || null,
                    imgPath: fileExists(entry.img) ? abs(entry.img) : null,
                    icon: entry.icon || null,
                    iconPath: fileExists(entry.icon) ? abs(entry.icon) : null,
                    bg: entry.bg || null,
                    bgPath: fileExists(entry.bg) ? abs(entry.bg) : null,
                });
            });
        }
    }

    result.games.sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: 'base' }));
    return result;
}

// ---------------------------------------------------------------------------
// Writing games
// ---------------------------------------------------------------------------

function sanitizeFolderName(name) {
    return name
        .replace(/[<>:"/\\|?*\x00-\x1f]/g, '')
        .replace(/\s+/g, ' ')
        .trim()
        .replace(/\.+$/, '')
        .slice(0, 100);
}

// Maximum stored size per asset type. The launcher displays covers at
// ~200px tall, icons at ~100px and backgrounds at 480p, so these keep
// plenty of headroom while capping GPU memory and SD usage on device
// (an unprocessed 1500px cover costs ~8 MB of texture memory; at these
// sizes it's well under 2 MB).
const ASSET_SPECS = {
    default: { maxW: 480, maxH: 720 }, // cover (2:3 box art)
    icon: { maxW: 160, maxH: 160 },
    bg: { maxW: 960, maxH: 720 },      // fullscreen loading art
};
const JPEG_QUALITY = 88;

// Decode + downscale an image to its spec. Returns { buffer, ext } or
// null when the format can't be processed (then the caller copies the
// file untouched). PNG sources stay PNG (some art has transparency);
// everything else becomes JPEG.
function processImage(sourcePath, canonicalBase) {
    const spec = ASSET_SPECS[canonicalBase];
    if (!spec) return null;
    const img = nativeImage.createFromPath(sourcePath);
    if (img.isEmpty()) return null; // unsupported format (bmp/webp/gif...)

    const { width, height } = img.getSize();
    const scale = Math.min(spec.maxW / width, spec.maxH / height, 1);
    const resized = scale < 1
        ? img.resize({
              width: Math.round(width * scale),
              height: Math.round(height * scale),
              quality: 'best',
          })
        : img;

    const asPng = path.extname(sourcePath).toLowerCase() === '.png';
    return {
        buffer: asPng ? resized.toPNG() : resized.toJPEG(JPEG_QUALITY),
        ext: asPng ? '.png' : '.jpg',
    };
}

// Remove other "<canonicalBase>.<image ext>" files so replacing a
// default.png with a default.jpg doesn't leave the stale png behind.
async function removeStaleAssets(folderPath, canonicalBase, keepName) {
    for (const ext of IMAGE_EXTS) {
        const name = canonicalBase + ext;
        if (name !== keepName) {
            await fsp.rm(path.join(folderPath, name), { force: true }).catch(() => {});
        }
    }
}

// Imports `sourcePath` into `folderPath` under a canonical name (e.g.
// cover -> default.png), downscaled to the asset type's maximum size.
// Formats nativeImage can't decode are copied untouched with their own
// extension. Returns the relative filename for info.cfg.
async function copyAsset(folderPath, sourcePath, canonicalBase) {
    const processed = processImage(sourcePath, canonicalBase);
    if (processed) {
        const destName = canonicalBase + processed.ext;
        await fsp.writeFile(path.join(folderPath, destName), processed.buffer);
        await removeStaleAssets(folderPath, canonicalBase, destName);
        return destName;
    }
    const ext = path.extname(sourcePath).toLowerCase() || '.png';
    const destName = canonicalBase + ext;
    const destPath = path.join(folderPath, destName);
    if (path.resolve(sourcePath) !== path.resolve(destPath)) {
        await fsp.copyFile(sourcePath, destPath);
        await removeStaleAssets(folderPath, canonicalBase, destName);
    }
    return destName;
}

async function copyRom(folderPath, sourcePath) {
    const destName = path.basename(sourcePath);
    const destPath = path.join(folderPath, destName);
    if (path.resolve(sourcePath) !== path.resolve(destPath)) {
        await fsp.copyFile(sourcePath, destPath);
    }
    return destName;
}

async function writeInfo(folderPath, entries) {
    await fsp.writeFile(path.join(folderPath, 'info.cfg'), serializeCfg(entries));
    // A legacy info.json would shadow nothing (the launcher prefers
    // info.cfg) but would confuse hand-editors; drop it on write.
    await fsp.rm(path.join(folderPath, 'info.json'), { force: true }).catch(() => {});
}

// payload: { gameDir, name, system, romPath, coverPath?, iconPath?, bgPath? }
async function createGame(payload) {
    const { gameDir, name, system, romPath, coverPath, iconPath, bgPath } = payload;

    if (!name || !name.trim()) throw new Error('Game name is required.');
    if (!romPath) throw new Error('A rom, iso or script file is required.');
    const isScript = path.extname(romPath).toLowerCase() === '.sh';
    if (!isScript && !system) throw new Error('A system is required for rom files.');

    const folderName = sanitizeFolderName(name);
    if (!folderName) throw new Error('Game name produces an empty folder name.');
    const folderPath = path.join(gameDir, folderName);
    if (fs.existsSync(folderPath)) {
        throw new Error(`A folder named "${folderName}" already exists in the GAME directory.`);
    }

    await fsp.mkdir(folderPath, { recursive: true });
    try {
        const entry = {
            system: isScript ? 'port' : system,
            name: name.trim(),
            file: await copyRom(folderPath, romPath),
        };
        if (coverPath) entry.img = await copyAsset(folderPath, coverPath, 'default');
        if (iconPath) entry.icon = await copyAsset(folderPath, iconPath, 'icon');
        if (bgPath) entry.bg = await copyAsset(folderPath, bgPath, 'bg');
        await writeInfo(folderPath, [entry]);
    } catch (err) {
        // Don't leave a half-created folder behind
        await fsp.rm(folderPath, { recursive: true, force: true }).catch(() => {});
        throw err;
    }
    return { folder: folderName };
}

// One-time pass over existing libraries: downscale any cover/icon/bg
// that exceeds its ASSET_SPECS budget, in place (filenames and
// info.cfg untouched). Returns counts for the toast.
async function optimizeLibrary(gameDirs) {
    const stats = { checked: 0, resized: 0, savedBytes: 0 };
    const seen = new Set();
    const FIELDS = [['img', 'default'], ['icon', 'icon'], ['bg', 'bg']];

    for (const gameDir of gameDirs) {
        const dirents = await fsp.readdir(gameDir, { withFileTypes: true });
        for (const dirent of dirents) {
            if (!dirent.isDirectory() || dirent.name.startsWith('.')) continue;
            const folderPath = path.join(gameDir, dirent.name);

            let entries;
            try {
                entries = await readInfo(folderPath);
            } catch {
                continue;
            }
            for (const entry of entries) {
                if (!entry || typeof entry !== 'object') continue;
                for (const [field, base] of FIELDS) {
                    const rel = entry[field];
                    if (!rel || typeof rel !== 'string') continue;
                    const filePath = path.join(folderPath, rel);
                    if (seen.has(filePath) || !fs.existsSync(filePath)) continue;
                    seen.add(filePath);

                    const spec = ASSET_SPECS[base];
                    const img = nativeImage.createFromPath(filePath);
                    if (img.isEmpty()) continue;
                    stats.checked += 1;

                    const { width, height } = img.getSize();
                    const scale = Math.min(spec.maxW / width, spec.maxH / height, 1);
                    if (scale >= 1) continue;

                    const resized = img.resize({
                        width: Math.round(width * scale),
                        height: Math.round(height * scale),
                        quality: 'best',
                    });
                    const asPng = path.extname(filePath).toLowerCase() === '.png';
                    const buffer = asPng ? resized.toPNG() : resized.toJPEG(JPEG_QUALITY);
                    const oldSize = (await fsp.stat(filePath)).size;
                    await fsp.writeFile(filePath, buffer);
                    stats.resized += 1;
                    stats.savedBytes += oldSize - buffer.length;
                }
            }
        }
    }
    return stats;
}

// payload: { folderPath, entryIndex, name?, system?, coverPath?, iconPath?, bgPath? }
// Only provided fields are changed; asset paths replace existing assets.
async function updateGame(payload) {
    const { folderPath, entryIndex, name, system, coverPath, iconPath, bgPath } = payload;

    const entries = await readInfo(folderPath);
    const entry = entries[entryIndex];
    if (!entry) throw new Error('Entry not found in info.cfg.');

    if (typeof name === 'string' && name.trim()) entry.name = name.trim();
    if (typeof system === 'string' && system) entry.system = system;
    if (coverPath) entry.img = await copyAsset(folderPath, coverPath, 'default');
    if (iconPath) entry.icon = await copyAsset(folderPath, iconPath, 'icon');
    if (bgPath) entry.bg = await copyAsset(folderPath, bgPath, 'bg');

    await writeInfo(folderPath, entries);
    return { ok: true };
}

// payload: { folderPath, entryIndex }
// A folder that holds only this title is moved to the system trash
// (rom, art and saves included, recoverable). When the folder declares
// several titles, only this entry is removed from info.cfg and every
// file stays put (assets/roms may be shared between entries).
async function deleteGame(payload) {
    const { folderPath, entryIndex } = payload;

    const entries = await readInfo(folderPath);
    if (!entries[entryIndex]) throw new Error('Entry not found in info.cfg.');

    if (entries.length === 1) {
        await shell.trashItem(folderPath);
        return { trashedFolder: true };
    }
    entries.splice(entryIndex, 1);
    await writeInfo(folderPath, entries);
    return { trashedFolder: false };
}

// ---------------------------------------------------------------------------
// Backup
// ---------------------------------------------------------------------------

// Incremental copy of one directory tree. Only files that are new or
// changed since the last run (different size, or newer modification
// time) are copied; the copy keeps the source's mtime so the next run
// skips it again. Nothing is ever deleted from the backup, so saves
// that disappeared from the card remain recoverable.
async function backupTree(srcDir, destDir, stats) {
    await fsp.mkdir(destDir, { recursive: true });
    const dirents = await fsp.readdir(srcDir, { withFileTypes: true });
    for (const dirent of dirents) {
        if (dirent.name === '.DS_Store' || dirent.name.startsWith('._')) continue;
        const src = path.join(srcDir, dirent.name);
        const dest = path.join(destDir, dirent.name);
        if (dirent.isDirectory()) {
            await backupTree(src, dest, stats);
            continue;
        }
        if (!dirent.isFile()) continue;

        const srcStat = await fsp.stat(src);
        let unchanged = false;
        try {
            // 2s modification-time window: SD cards are FAT/exFAT with
            // coarse timestamps, and utimes writes less precision than
            // stat reads on APFS. Same trade-off rsync makes for FAT.
            const destStat = await fsp.stat(dest);
            unchanged =
                destStat.size === srcStat.size &&
                destStat.mtimeMs >= srcStat.mtimeMs - 2000;
        } catch {
            // not in the backup yet
        }
        if (unchanged) {
            stats.unchanged += 1;
            continue;
        }
        await fsp.copyFile(src, dest);
        await fsp.utimes(dest, srcStat.atime, srcStat.mtime);
        stats.copied += 1;
        stats.bytes += srcStat.size;
    }
}

const BACKUP_FOLDER_NAME = 'Vitro Game Backups';

// Backs up every open GAME root - game folders with their roms, art,
// info.cfg, stats.json and in-folder saves - into a clearly named
// "Vitro Game Backups" folder inside backupDir. The usual single open
// root goes straight to "Vitro Game Backups/GAME"; additional roots
// (a second SD card) get "GAME 2", "GAME 3", ... in the order the
// folders were opened.
async function backupLibrary(gameDirs, backupDir) {
    if (!backupDir || !fs.existsSync(backupDir)) {
        throw new Error('Backup folder not found: ' + backupDir);
    }
    const backupRoot =
        path.basename(backupDir) === BACKUP_FOLDER_NAME
            ? backupDir // user picked the wrapper folder itself
            : path.join(backupDir, BACKUP_FOLDER_NAME);
    const stats = { copied: 0, unchanged: 0, bytes: 0 };
    for (let i = 0; i < gameDirs.length; i++) {
        const name = i === 0 ? 'GAME' : `GAME ${i + 1}`;
        await backupTree(gameDirs[i], path.join(backupRoot, name), stats);
    }
    return stats;
}

// ---------------------------------------------------------------------------
// SteamGridDB (artwork search)
//
// Cover = SGDB "grids" (600x900 box art), Background = "heroes",
// Icon = "icons". All requests run in the main process with the API
// key from settings; the renderer only ever sees image URLs and the
// downloaded temp file path, which then flows through the normal
// copyAsset pipeline (downscale + canonical name) on save.
// ---------------------------------------------------------------------------

const SGDB_API = 'https://www.steamgriddb.com/api/v2';

// Only formats both nativeImage (importer) and Love2D (launcher) can
// decode - keeps webp grids and .ico icons out of the results. The
// mimes filter is validated per endpoint: icons only allow png/ico
// (jpeg there is a 400), grids and heroes allow png/jpeg.
const SGDB_MIMES = 'mimes=image/png,image/jpeg';

const SGDB_ASSET_PATHS = {
    cover: (gameId) => `/grids/game/${gameId}?dimensions=600x900&${SGDB_MIMES}`,
    bg: (gameId) => `/heroes/game/${gameId}?${SGDB_MIMES}`,
    icon: (gameId) => `/icons/game/${gameId}?mimes=image/png`,
};

async function sgdbRequest(endpoint) {
    const key = loadSettings().steamGridKey;
    if (!key) throw new Error('No SteamGridDB API key set - add one in Settings.');
    const res = await fetch(SGDB_API + endpoint, {
        headers: { Authorization: 'Bearer ' + key },
    });
    if (res.status === 401) {
        throw new Error('SteamGridDB rejected the API key - check it in Settings.');
    }
    if (!res.ok) throw new Error('SteamGridDB request failed (HTTP ' + res.status + ').');
    const body = await res.json();
    if (!body.success) {
        throw new Error('SteamGridDB error: ' + (body.errors || ['unknown']).join(', '));
    }
    return body.data;
}

async function sgdbSearch(term) {
    const games = await sgdbRequest('/search/autocomplete/' + encodeURIComponent(term));
    return games.map((g) => ({
        id: g.id,
        name: g.name,
        // release_date is a unix timestamp; the year disambiguates remakes
        year: g.release_date ? new Date(g.release_date * 1000).getFullYear() : null,
    }));
}

async function sgdbAssets(gameId, kind) {
    const buildPath = SGDB_ASSET_PATHS[kind];
    if (!buildPath) throw new Error('Unknown asset kind: ' + kind);
    const items = await sgdbRequest(buildPath(gameId));
    return items.map((a) => ({
        id: a.id,
        url: a.url,
        thumb: a.thumb || a.url,
        width: a.width,
        height: a.height,
        style: a.style || null,
    }));
}

// Downloads a chosen image to a temp file; the renderer hands the path
// to createGame/updateGame exactly like a locally picked file.
async function sgdbDownload(url) {
    const res = await fetch(url);
    if (!res.ok) throw new Error('Image download failed (HTTP ' + res.status + ').');
    const buffer = Buffer.from(await res.arrayBuffer());
    const ext = path.extname(new URL(url).pathname).toLowerCase() || '.png';
    const dest = path.join(
        app.getPath('temp'),
        `vitro-sgdb-${Date.now()}-${Math.floor(Math.random() * 1e6)}${ext}`
    );
    await fsp.writeFile(dest, buffer);
    return dest;
}

// ---------------------------------------------------------------------------
// IPC
// ---------------------------------------------------------------------------

function registerIpc() {
    // Settings migration: gameDir (single folder) predates gameDirs
    ipcMain.handle('settings:get', () => {
        const settings = loadSettings();
        if (!settings.gameDirs && settings.gameDir) {
            settings.gameDirs = [settings.gameDir];
        }
        return settings;
    });

    ipcMain.handle('settings:setGameDirs', (_event, gameDirs) => {
        const settings = loadSettings();
        delete settings.gameDir;
        saveSettings({ ...settings, gameDirs });
    });

    ipcMain.handle('settings:setBackupDir', (_event, backupDir) => {
        saveSettings({ ...loadSettings(), backupDir });
    });

    ipcMain.handle('settings:setSteamGridKey', (_event, steamGridKey) => {
        saveSettings({ ...loadSettings(), steamGridKey });
    });

    ipcMain.handle('dialog:pickBackupFolder', async () => {
        const result = await dialog.showOpenDialog(mainWindow, {
            title: 'Choose a backup folder',
            message: 'Game folders are copied here - only new and changed files on later backups',
            properties: ['openDirectory', 'createDirectory'],
        });
        if (result.canceled || result.filePaths.length === 0) return null;
        return result.filePaths[0];
    });

    ipcMain.handle('dialog:pickGameFolder', async () => {
        const result = await dialog.showOpenDialog(mainWindow, {
            title: 'Open a GAME folder',
            message: 'Select a GAME folder - inside the Vitro Launcher folder, or at the root of an SD card',
            properties: ['openDirectory'],
        });
        if (result.canceled || result.filePaths.length === 0) return null;
        return result.filePaths[0];
    });

    ipcMain.handle('dialog:pickFile', async (_event, kind) => {
        const filters =
            kind === 'rom'
                ? [
                      { name: 'Roms, ISOs and scripts', extensions: ['*'] },
                  ]
                : [{ name: 'Images', extensions: ['png', 'jpg', 'jpeg', 'bmp', 'webp', 'gif'] }];
        const result = await dialog.showOpenDialog(mainWindow, {
            title: kind === 'rom' ? 'Select the rom, iso or launch script' : 'Select an image',
            properties: ['openFile'],
            filters,
        });
        if (result.canceled || result.filePaths.length === 0) return null;
        return result.filePaths[0];
    });

    ipcMain.handle('library:scan', async (_event, gameDirs) => {
        const dirs = Array.isArray(gameDirs) ? gameDirs : [gameDirs];
        for (const dir of dirs) {
            if (!dir || !fs.existsSync(dir)) {
                throw new Error('GAME folder not found: ' + dir);
            }
        }
        return scanLibrary(dirs);
    });

    ipcMain.handle('library:createGame', (_event, payload) => createGame(payload));
    ipcMain.handle('library:updateGame', (_event, payload) => updateGame(payload));
    ipcMain.handle('library:deleteGame', (_event, payload) => deleteGame(payload));
    ipcMain.handle('library:optimize', (_event, gameDirs) => optimizeLibrary(gameDirs));
    ipcMain.handle('library:backup', (_event, gameDirs, backupDir) =>
        backupLibrary(gameDirs, backupDir));

    ipcMain.handle('sgdb:search', (_event, term) => sgdbSearch(term));
    ipcMain.handle('sgdb:assets', (_event, gameId, kind) => sgdbAssets(gameId, kind));
    ipcMain.handle('sgdb:download', (_event, url) => sgdbDownload(url));

    ipcMain.handle('shell:showInFolder', (_event, targetPath) => {
        shell.showItemInFolder(targetPath);
    });
}

// ---------------------------------------------------------------------------
// App lifecycle
// ---------------------------------------------------------------------------

// Serves local images to the renderer without disabling web security.
protocol.registerSchemesAsPrivileged([
    { scheme: 'vitro-asset', privileges: { standard: false, bypassCSP: true, stream: true } },
]);

function appIconPath() {
    // Packaged builds use platform icons from electron-builder; for
    // `npm start` fall back to the source PNG that matches the OS.
    if (app.isPackaged) return undefined;
    const file = process.platform === 'darwin'
        ? path.join(__dirname, '..', 'build', 'icons', 'macos', 'app.png')
        : path.join(__dirname, '..', 'build', 'icons', 'win-lin', 'app.png');
    return fs.existsSync(file) ? file : undefined;
}

function createWindow() {
    mainWindow = new BrowserWindow({
        width: 1180,
        height: 800,
        minWidth: 860,
        minHeight: 560,
        title: 'VitroManager',
        backgroundColor: '#101322',
        icon: appIconPath(),
        webPreferences: {
            preload: path.join(__dirname, 'preload.js'),
            contextIsolation: true,
            nodeIntegration: false,
        },
    });
    mainWindow.loadFile(path.join(__dirname, '..', 'renderer', 'index.html'));
    mainWindow.on('closed', () => {
        mainWindow = null;
    });
}

app.whenReady().then(() => {
    protocol.registerFileProtocol('vitro-asset', (request, callback) => {
        const filePath = decodeURIComponent(request.url.slice('vitro-asset://'.length));
        if (IMAGE_EXTS.has(path.extname(filePath).toLowerCase())) {
            callback({ path: filePath });
        } else {
            callback({ error: -6 }); // FILE_NOT_FOUND
        }
    });

    registerIpc();
    createWindow();

    app.on('activate', () => {
        if (BrowserWindow.getAllWindows().length === 0) createWindow();
    });
});

app.on('window-all-closed', () => {
    if (process.platform !== 'darwin') app.quit();
});
