'use strict';

// Matches the systems handled by defaults.cfg (cores + ext_launchers) plus
// PortMaster scripts.
const SYSTEMS = [
    { id: 'gb', label: 'Game Boy' },
    { id: 'gbc', label: 'Game Boy Color' },
    { id: 'gba', label: 'Game Boy Advance' },
    { id: 'nes', label: 'NES' },
    { id: 'snes', label: 'SNES' },
    { id: 'genesis', label: 'Genesis / Mega Drive' },
    { id: 'psx', label: 'PlayStation' },
    { id: 'n64', label: 'Nintendo 64' },
    { id: 'psp', label: 'PSP' },
    { id: 'arcade', label: 'Arcade' },
    { id: 'port', label: 'PortMaster (.sh script)' },
];

const state = {
    gameDirs: [], // open GAME folder roots (launcher merges them the same way)
    games: [],
    skipped: [],
    sort: 'az',         // 'az' | 'playtime'
    backupDir: null,    // remembered backup destination
    steamGridKey: '',   // SteamGridDB API key (stored in settings)
    edit: null,   // { game, pending: {cover, icon, bg} }
    wizard: null, // { step, system, romPath, name, cover, icon, bg }
};

const $ = (id) => document.getElementById(id);

function assetUrl(absPath) {
    return 'vitro-asset://' + encodeURIComponent(absPath);
}

function baseName(p) {
    return p.split(/[\\/]/).pop();
}

function formatPlaytime(seconds) {
    if (!seconds || seconds < 60) return seconds > 0 ? '<1m' : '0m';
    const minutes = Math.round(seconds / 60);
    const hours = Math.floor(minutes / 60);
    return hours > 0 ? `${hours}h ${minutes % 60}m` : `${minutes}m`;
}

function sortedGames() {
    const games = [...state.games];
    if (state.sort === 'playtime') {
        // Most played first; untouched games keep A-Z order at the end
        games.sort(
            (a, b) =>
                (b.playSeconds || 0) - (a.playSeconds || 0) ||
                a.name.localeCompare(b.name, undefined, { sensitivity: 'base' })
        );
    }
    return games; // scan already returns A-Z
}

function showToast(message) {
    const toast = $('toast');
    toast.textContent = message;
    toast.classList.remove('hidden');
    clearTimeout(showToast._t);
    showToast._t = setTimeout(() => toast.classList.add('hidden'), 2600);
}

// Long-running toolbar actions (backup, optimize) swap the button
// content for a spinner + label so the activity is unmissable.
function setButtonBusy(btn, label) {
    btn.dataset.label = btn.textContent;
    btn.disabled = true;
    btn.textContent = '';
    const spinner = document.createElement('span');
    spinner.className = 'spinner';
    btn.append(spinner, document.createTextNode(label));
}

function clearButtonBusy(btn) {
    btn.textContent = btn.dataset.label;
    btn.disabled = false;
}

function setError(id, message) {
    const el = $(id);
    if (message) {
        el.textContent = message;
        el.classList.remove('hidden');
    } else {
        el.classList.add('hidden');
    }
}

// ---------------------------------------------------------------------------
// Views
// ---------------------------------------------------------------------------

function showLibraryView() {
    $('view-welcome').classList.add('hidden');
    $('view-library').classList.remove('hidden');
}

// Opens a GAME folder root. `add` keeps the already-open roots (a
// second SD card's GAME folder shows merged, like the launcher does).
async function openFolder({ add = false } = {}) {
    setError('welcome-error', null);
    const dir = await window.vitro.pickGameFolder();
    if (!dir) return;
    state.gameDirs = add ? [...state.gameDirs.filter((d) => d !== dir), dir] : [dir];
    await window.vitro.setGameDirs(state.gameDirs);
    await refreshLibrary();
    showLibraryView();
}

async function closeFolder(dir) {
    state.gameDirs = state.gameDirs.filter((d) => d !== dir);
    await window.vitro.setGameDirs(state.gameDirs);
    await refreshLibrary();
}

async function refreshLibrary({ silent = false } = {}) {
    try {
        const result = await window.vitro.scanLibrary(state.gameDirs);
        state.games = result.games;
        state.skipped = result.skipped;
        renderLibrary();
        return true;
    } catch (err) {
        if (!silent) showToast('Scan failed: ' + err.message);
        return false;
    }
}

// Toolbar chips, one per open GAME folder root
function renderRoots() {
    const list = $('root-list');
    list.textContent = '';
    for (const dir of state.gameDirs) {
        const chip = document.createElement('span');
        chip.className = 'root-chip';
        chip.title = dir;
        const label = document.createElement('span');
        label.className = 'root-chip-label';
        label.textContent = dir;
        chip.appendChild(label);
        const close = document.createElement('button');
        close.className = 'root-chip-close';
        close.textContent = '✕';
        close.title = 'Close this folder';
        close.addEventListener('click', async () => {
            await closeFolder(dir);
            if (state.gameDirs.length === 0) {
                $('view-library').classList.add('hidden');
                $('view-welcome').classList.remove('hidden');
            }
        });
        chip.appendChild(close);
        list.appendChild(chip);
    }
}

function renderLibrary() {
    renderRoots();

    const grid = $('library-grid');
    grid.textContent = '';
    $('library-empty').classList.toggle('hidden', state.games.length > 0);

    for (const game of sortedGames()) {
        const card = document.createElement('div');
        card.className = 'card';

        const cover = document.createElement('div');
        cover.className = 'card-cover';
        if (game.imgPath) {
            const img = document.createElement('img');
            img.src = assetUrl(game.imgPath);
            img.loading = 'lazy';
            cover.appendChild(img);
        } else {
            cover.textContent = game.name.charAt(0).toUpperCase();
        }

        const meta = document.createElement('div');
        meta.className = 'card-meta';

        const name = document.createElement('div');
        name.className = 'card-name';
        name.textContent = game.name;
        name.title = game.name;

        const sub = document.createElement('div');
        sub.className = 'card-sub';
        const badge = document.createElement('span');
        badge.className = 'badge';
        badge.textContent = game.system || 'no system';
        sub.appendChild(badge);
        if (state.gameDirs.length > 1) {
            // Which open GAME folder this game lives in
            const root = document.createElement('span');
            root.className = 'badge';
            root.textContent = game.rootLabel;
            root.title = game.rootDir;
            sub.appendChild(root);
        }
        if (game.playSeconds > 0) {
            const time = document.createElement('span');
            time.className = 'badge';
            time.textContent = formatPlaytime(game.playSeconds);
            time.title = `Played ${game.playCount} time(s)`;
            sub.appendChild(time);
        }
        if (!game.fileExists) {
            const warn = document.createElement('span');
            warn.className = 'badge badge-warn';
            warn.textContent = 'file missing';
            warn.title = 'The rom/script referenced by info.cfg is not in the folder';
            sub.appendChild(warn);
        }

        meta.append(name, sub);
        card.append(cover, meta);
        card.addEventListener('click', () => openEdit(game));
        grid.appendChild(card);
    }

    const note = $('skipped-note');
    if (state.skipped.length > 0) {
        note.textContent =
            'Skipped folders: ' +
            state.skipped.map((s) => `${s.folder} (${s.reason})`).join(', ');
        note.classList.remove('hidden');
    } else {
        note.classList.add('hidden');
    }
}

// ---------------------------------------------------------------------------
// Edit modal
// ---------------------------------------------------------------------------

function fillSystemSelect(select, selected) {
    select.textContent = '';
    for (const sys of SYSTEMS) {
        const opt = document.createElement('option');
        opt.value = sys.id;
        opt.textContent = `${sys.label} (${sys.id})`;
        select.appendChild(opt);
    }
    if (selected && !SYSTEMS.some((s) => s.id === selected)) {
        const opt = document.createElement('option');
        opt.value = selected;
        opt.textContent = selected;
        select.appendChild(opt);
    }
    select.value = selected || 'gba';
}

function setPreview(el, src) {
    el.textContent = '';
    if (src) {
        const img = document.createElement('img');
        img.src = src;
        el.appendChild(img);
    }
}

function openEdit(game) {
    state.edit = { game, pending: {} };
    setError('edit-error', null);

    $('edit-name').value = game.name;
    fillSystemSelect($('edit-system'), game.system);
    $('edit-file').textContent = game.file || '(none)';
    setPreview($('edit-preview-cover'), game.imgPath ? assetUrl(game.imgPath) : null);
    setPreview($('edit-preview-icon'), game.iconPath ? assetUrl(game.iconPath) : null);
    setPreview($('edit-preview-bg'), game.bgPath ? assetUrl(game.bgPath) : null);

    $('modal-edit').classList.remove('hidden');
}

async function pickEditAsset(kind) {
    const file = await window.vitro.pickFile('image');
    if (!file) return;
    state.edit.pending[kind] = file;
    setPreview($('edit-preview-' + kind), assetUrl(file));
}

async function saveEdit() {
    const { game, pending } = state.edit;
    setError('edit-error', null);
    const btn = $('btn-save-edit');
    setButtonBusy(btn, 'Saving…');
    try {
        await window.vitro.updateGame({
            folderPath: game.folderPath,
            entryIndex: game.entryIndex,
            name: $('edit-name').value,
            system: $('edit-system').value,
            coverPath: pending.cover || null,
            iconPath: pending.icon || null,
            bgPath: pending.bg || null,
        });
        $('modal-edit').classList.add('hidden');
        showToast('Saved "' + $('edit-name').value.trim() + '"');
        await refreshLibrary();
    } catch (err) {
        setError('edit-error', err.message);
    } finally {
        clearButtonBusy(btn);
    }
}

async function deleteGameFromEdit() {
    const { game } = state.edit;
    // A folder with a single title is the game (rom, art, saves) - it
    // goes to the trash whole. Multi-title folders only lose the entry.
    const message =
        game.entryCount > 1
            ? `Remove "${game.name}" from this folder's info.cfg?\n\n` +
              `The folder holds ${game.entryCount} titles, so no files are ` +
              `deleted - only this entry is removed from the list.`
            : `Delete "${game.name}"?\n\n` +
              `Its folder "${game.folder}" (rom, artwork, stats and any ` +
              `in-folder saves) will be moved to the trash.`;
    if (!window.confirm(message)) return;

    setError('edit-error', null);
    const btn = $('btn-delete-game');
    setButtonBusy(btn, 'Deleting…');
    try {
        const res = await window.vitro.deleteGame({
            folderPath: game.folderPath,
            entryIndex: game.entryIndex,
        });
        $('modal-edit').classList.add('hidden');
        showToast(
            res.trashedFolder
                ? `Moved "${game.folder}" to the trash`
                : `Removed "${game.name}"`
        );
        await refreshLibrary();
    } catch (err) {
        setError('edit-error', err.message);
    } finally {
        clearButtonBusy(btn);
    }
}

// ---------------------------------------------------------------------------
// Add-game wizard
// ---------------------------------------------------------------------------

function openWizard() {
    state.wizard = { step: 1, system: null, romPath: null, name: '', cover: null, icon: null, bg: null };
    setError('wizard-error', null);
    $('wizard-name').value = '';
    $('rom-readout').classList.add('hidden');
    // Destination picker, only when more than one GAME folder is open
    const rootField = $('wizard-root-field');
    rootField.classList.toggle('hidden', state.gameDirs.length < 2);
    const rootSelect = $('wizard-root');
    rootSelect.textContent = '';
    for (const dir of state.gameDirs) {
        const opt = document.createElement('option');
        opt.value = dir;
        opt.textContent = dir;
        rootSelect.appendChild(opt);
    }
    setPreview($('wiz-preview-cover'), null);
    setPreview($('wiz-preview-icon'), null);
    setPreview($('wiz-preview-bg'), null);
    renderSystemGrid();
    renderWizardStep();
    $('modal-wizard').classList.remove('hidden');
}

function renderSystemGrid() {
    const grid = $('system-grid');
    grid.textContent = '';
    for (const sys of SYSTEMS) {
        const tile = document.createElement('div');
        tile.className = 'system-tile' + (state.wizard.system === sys.id ? ' selected' : '');
        const name = document.createElement('div');
        name.className = 'sys-name';
        name.textContent = sys.label;
        const id = document.createElement('span');
        id.className = 'sys-id';
        id.textContent = sys.id;
        tile.append(name, id);
        tile.addEventListener('click', () => {
            state.wizard.system = sys.id;
            renderSystemGrid();
            renderWizardStep();
        });
        grid.appendChild(tile);
    }
}

function wizardCanAdvance() {
    const w = state.wizard;
    if (w.step === 1) return !!w.system;
    if (w.step === 2) return !!w.romPath && !!$('wizard-name').value.trim();
    return true;
}

function renderWizardStep() {
    const w = state.wizard;

    document.querySelectorAll('#wizard-steps .step').forEach((el) => {
        const n = Number(el.dataset.step);
        el.classList.toggle('active', n === w.step);
        el.classList.toggle('done', n < w.step);
    });
    document.querySelectorAll('.wizard-page').forEach((el) => {
        el.classList.toggle('hidden', Number(el.dataset.page) !== w.step);
    });

    if (w.step === 2) {
        $('rom-lead').textContent =
            w.system === 'port'
                ? 'Select the PortMaster launch script (.sh) — copy it from the ports/ directory on your device.'
                : 'Select the rom or iso file for this game.';
    }
    if (w.step === 4) renderReview();

    $('wizard-back').style.visibility = w.step === 1 ? 'hidden' : 'visible';
    $('wizard-next').textContent = w.step === 4 ? 'Create Game' : 'Next';
    $('wizard-next').disabled = !wizardCanAdvance();
}

function renderReview() {
    const w = state.wizard;
    const sys = SYSTEMS.find((s) => s.id === w.system);
    const box = $('review-box');
    box.textContent = '';
    const rows = [
        ['Name', $('wizard-name').value.trim()],
        ['System', sys ? `${sys.label} (${sys.id})` : w.system],
        ['File', baseName(w.romPath)],
        ['Cover', w.cover ? baseName(w.cover) : '— none —'],
        ['Icon', w.icon ? baseName(w.icon) : '— none —'],
        ['Background', w.bg ? baseName(w.bg) : '— none —'],
    ];
    if (state.gameDirs.length > 1) {
        rows.push(['Location', $('wizard-root').value]);
    }
    for (const [label, value] of rows) {
        const line = document.createElement('div');
        const lab = document.createElement('span');
        lab.className = 'rv-label';
        lab.textContent = label;
        line.append(lab, document.createTextNode(value));
        box.appendChild(line);
    }
}

async function pickRom() {
    const file = await window.vitro.pickFile('rom');
    if (!file) return;
    state.wizard.romPath = file;
    const readout = $('rom-readout');
    readout.textContent = file;
    readout.classList.remove('hidden');
    if (!$('wizard-name').value.trim()) {
        // Suggest a name from the filename, stripping extension and region tags
        const base = baseName(file).replace(/\.[^.]+$/, '');
        $('wizard-name').value = base.replace(/\s*[([].*?[)\]]\s*/g, ' ').replace(/\s+/g, ' ').trim() || base;
    }
    renderWizardStep();
}

async function pickWizardAsset(kind) {
    const file = await window.vitro.pickFile('image');
    if (!file) return;
    state.wizard[kind] = file;
    setPreview($('wiz-preview-' + kind), assetUrl(file));
}

async function wizardNext() {
    const w = state.wizard;
    setError('wizard-error', null);

    if (w.step < 4) {
        w.step += 1;
        renderWizardStep();
        return;
    }

    // Copying a rom can take a while (multi-GB isos from a slow card);
    // make the activity unmistakable and keep the modal in place.
    const next = $('wizard-next');
    setButtonBusy(next, 'Copying files…');
    $('wizard-back').disabled = true;
    try {
        const result = await window.vitro.createGame({
            gameDir: state.gameDirs.length > 1 ? $('wizard-root').value : state.gameDirs[0],
            name: $('wizard-name').value,
            system: w.system,
            romPath: w.romPath,
            coverPath: w.cover,
            iconPath: w.icon,
            bgPath: w.bg,
        });
        $('modal-wizard').classList.add('hidden');
        showToast('Created "' + result.folder + '"');
        await refreshLibrary();
    } catch (err) {
        setError('wizard-error', err.message);
    } finally {
        clearButtonBusy(next);
        $('wizard-back').disabled = false;
    }
}

function wizardBack() {
    if (state.wizard.step > 1) {
        state.wizard.step -= 1;
        setError('wizard-error', null);
        renderWizardStep();
    }
}

// ---------------------------------------------------------------------------
// SteamGridDB picker
//
// Cover = SGDB grids (2:3 box art), Background = heroes, Icon = icons.
// Flow: search by title -> pick the matching game -> click an image.
// The chosen image is downloaded to a temp file and handed to the same
// pending-asset flow a locally picked file uses.
// ---------------------------------------------------------------------------

const SGDB_KIND_LABELS = { cover: 'Cover', icon: 'Icon', bg: 'Background' };

function sgdbStatus(message, withSpinner) {
    const el = $('sgdb-status');
    if (!message) {
        el.classList.add('hidden');
        return;
    }
    el.textContent = '';
    if (withSpinner) {
        const spinner = document.createElement('span');
        spinner.className = 'spinner';
        el.appendChild(spinner);
    }
    el.appendChild(document.createTextNode(message));
    el.classList.remove('hidden');
}

function openSgdbPicker({ kind, name, onPick }) {
    if (!state.steamGridKey) {
        showToast('Add a SteamGridDB API key in Settings first');
        return;
    }
    state.sgdb = { kind, onPick, games: [] };
    $('sgdb-title').textContent = `SteamGridDB — ${SGDB_KIND_LABELS[kind]}`;
    $('sgdb-search').value = name || '';
    $('sgdb-game').classList.add('hidden');
    $('sgdb-grid').textContent = '';
    $('sgdb-grid').className = 'sgdb-grid kind-' + kind;
    setError('sgdb-error', null);
    sgdbStatus(null);
    $('modal-sgdb').classList.remove('hidden');
    if (name) sgdbSearch();
}

async function sgdbSearch() {
    const term = $('sgdb-search').value.trim();
    if (!term) return;
    setError('sgdb-error', null);
    $('sgdb-grid').textContent = '';
    $('sgdb-game').classList.add('hidden');
    sgdbStatus('Searching…', true);
    try {
        const games = await window.vitro.sgdbSearch(term);
        state.sgdb.games = games;
        if (games.length === 0) {
            sgdbStatus('No games match "' + term + '". Try a shorter title.');
            return;
        }
        const select = $('sgdb-game');
        select.textContent = '';
        for (const game of games) {
            const opt = document.createElement('option');
            opt.value = String(game.id);
            opt.textContent = game.year ? `${game.name} (${game.year})` : game.name;
            select.appendChild(opt);
        }
        select.classList.remove('hidden');
        await sgdbLoadAssets();
    } catch (err) {
        sgdbStatus(null);
        setError('sgdb-error', err.message);
    }
}

async function sgdbLoadAssets() {
    const gameId = Number($('sgdb-game').value);
    if (!gameId) return;
    setError('sgdb-error', null);
    $('sgdb-grid').textContent = '';
    sgdbStatus('Loading images…', true);
    try {
        const assets = await window.vitro.sgdbAssets(gameId, state.sgdb.kind);
        sgdbStatus(null);
        if (assets.length === 0) {
            sgdbStatus(`No ${SGDB_KIND_LABELS[state.sgdb.kind].toLowerCase()} images for this game.`);
            return;
        }
        const grid = $('sgdb-grid');
        for (const asset of assets) {
            const tile = document.createElement('div');
            tile.className = 'sgdb-tile';
            tile.title = `${asset.width}x${asset.height}` + (asset.style ? ` · ${asset.style}` : '');
            const img = document.createElement('img');
            img.src = asset.thumb;
            img.loading = 'lazy';
            tile.appendChild(img);
            tile.addEventListener('click', () => sgdbPick(tile, asset));
            grid.appendChild(tile);
        }
    } catch (err) {
        sgdbStatus(null);
        setError('sgdb-error', err.message);
    }
}

async function sgdbPick(tile, asset) {
    if (state.sgdb.downloading) return;
    state.sgdb.downloading = true;
    tile.classList.add('busy');
    sgdbStatus('Downloading…', true);
    try {
        const localPath = await window.vitro.sgdbDownload(asset.url);
        state.sgdb.onPick(localPath);
        $('modal-sgdb').classList.add('hidden');
    } catch (err) {
        setError('sgdb-error', err.message);
    } finally {
        sgdbStatus(null);
        tile.classList.remove('busy');
        state.sgdb.downloading = false;
    }
}

// ---------------------------------------------------------------------------
// Stats modal
// ---------------------------------------------------------------------------

function openStats() {
    const games = [...state.games].sort(
        (a, b) =>
            (b.playSeconds || 0) - (a.playSeconds || 0) ||
            a.name.localeCompare(b.name, undefined, { sensitivity: 'base' })
    );

    const totalSeconds = games.reduce((sum, g) => sum + (g.playSeconds || 0), 0);
    const played = games.filter((g) => g.playCount > 0).length;
    $('stats-summary').textContent =
        `${games.length} game(s), ${played} played, ` +
        `${formatPlaytime(totalSeconds)} total playtime.`;

    const rows = $('stats-rows');
    rows.textContent = '';
    for (const game of games) {
        const tr = document.createElement('tr');
        const cells = [
            game.name,
            game.system || '—',
            game.playSeconds > 0 ? formatPlaytime(game.playSeconds) : '—',
            game.playCount > 0 ? String(game.playCount) : '—',
            game.lastPlayed ? new Date(game.lastPlayed * 1000).toLocaleDateString() : '—',
        ];
        cells.forEach((text, i) => {
            const td = document.createElement('td');
            td.textContent = text;
            if (i === 2 || i === 3) td.className = 'num';
            tr.appendChild(td);
        });
        rows.appendChild(tr);
    }

    $('modal-stats').classList.remove('hidden');
}

// ---------------------------------------------------------------------------
// Backup
// ---------------------------------------------------------------------------

// Copies every open GAME root into the backup folder; later runs only
// copy new and changed files (fresh saves, stats, added games).
// The destination is remembered; Shift-click to pick a different one.
async function runBackup({ rePick = false } = {}) {
    let dir = state.backupDir;
    if (rePick || !dir) {
        dir = await window.vitro.pickBackupFolder();
        if (!dir) return;
        state.backupDir = dir;
        await window.vitro.setBackupDir(dir);
    }

    const btn = $('btn-backup');
    setButtonBusy(btn, 'Backing up…');
    try {
        const res = await window.vitro.backupLibrary(state.gameDirs, dir);
        if (res.copied > 0) {
            const mb = (res.bytes / (1024 * 1024)).toFixed(1);
            showToast(`Backed up ${res.copied} file(s) (${mb} MB) to ${baseName(dir)}`);
        } else {
            showToast('Backup already up to date');
        }
    } catch (err) {
        showToast('Backup failed: ' + err.message);
    } finally {
        clearButtonBusy(btn);
    }
}

// ---------------------------------------------------------------------------
// Settings modal
// ---------------------------------------------------------------------------

function renderSettingsRoots() {
    const list = $('settings-roots');
    list.textContent = '';
    if (state.gameDirs.length === 0) {
        const empty = document.createElement('p');
        empty.className = 'field-hint';
        empty.textContent = 'No GAME folder open.';
        list.appendChild(empty);
    }
    for (const dir of state.gameDirs) {
        const row = document.createElement('div');
        row.className = 'settings-row';
        const readout = document.createElement('div');
        readout.className = 'file-readout';
        readout.textContent = dir;
        readout.title = dir;
        const remove = document.createElement('button');
        remove.className = 'btn btn-ghost btn-sm';
        remove.textContent = 'Remove';
        remove.addEventListener('click', async () => {
            await closeFolder(dir);
            renderSettingsRoots();
        });
        row.append(readout, remove);
        list.appendChild(row);
    }
}

function renderSettingsBackupDir() {
    $('settings-backup-dir').textContent = state.backupDir || '(not set)';
}

function openSettings() {
    renderSettingsRoots();
    renderSettingsBackupDir();
    $('settings-sgdb-key').value = state.steamGridKey || '';
    $('modal-settings').classList.remove('hidden');
}

async function saveSteamGridKey() {
    const key = $('settings-sgdb-key').value.trim();
    if (key === (state.steamGridKey || '')) return;
    state.steamGridKey = key;
    await window.vitro.setSteamGridKey(key);
}

async function closeSettings() {
    await saveSteamGridKey();
    $('modal-settings').classList.add('hidden');
    // Removing the last GAME folder drops back to the welcome screen
    if (state.gameDirs.length === 0) {
        $('view-library').classList.add('hidden');
        $('view-welcome').classList.remove('hidden');
    }
}

// ---------------------------------------------------------------------------
// Wiring
// ---------------------------------------------------------------------------

$('btn-open-folder').addEventListener('click', () => openFolder());
$('btn-add-root').addEventListener('click', () => openFolder({ add: true }));
$('btn-rescan').addEventListener('click', async () => {
    await refreshLibrary();
    showToast('Library rescanned');
});
$('btn-optimize').addEventListener('click', async () => {
    const btn = $('btn-optimize');
    setButtonBusy(btn, 'Optimizing…');
    try {
        const res = await window.vitro.optimizeLibrary(state.gameDirs);
        if (res.resized > 0) {
            const mb = (res.savedBytes / (1024 * 1024)).toFixed(1);
            showToast(`Resized ${res.resized} image(s), saved ${mb} MB`);
        } else {
            showToast('All images are already within the size budgets');
        }
        await refreshLibrary();
    } catch (err) {
        showToast('Optimize failed: ' + err.message);
    } finally {
        clearButtonBusy(btn);
    }
});
$('btn-add-game').addEventListener('click', openWizard);
$('sort-select').addEventListener('change', () => {
    state.sort = $('sort-select').value;
    renderLibrary();
});
$('btn-stats').addEventListener('click', openStats);
$('btn-backup').addEventListener('click', (e) => runBackup({ rePick: e.shiftKey }));

$('btn-settings').addEventListener('click', openSettings);
$('btn-settings-close').addEventListener('click', closeSettings);
$('btn-settings-done').addEventListener('click', closeSettings);
$('settings-add-root').addEventListener('click', async () => {
    await openFolder({ add: true });
    renderSettingsRoots();
});
$('settings-pick-backup').addEventListener('click', async () => {
    const dir = await window.vitro.pickBackupFolder();
    if (!dir) return;
    state.backupDir = dir;
    await window.vitro.setBackupDir(dir);
    renderSettingsBackupDir();
});

$('btn-save-edit').addEventListener('click', saveEdit);
$('btn-delete-game').addEventListener('click', deleteGameFromEdit);
$('edit-show-folder').addEventListener('click', () => {
    if (state.edit) window.vitro.showInFolder(state.edit.game.folderPath);
});
document.querySelectorAll('[data-pick]').forEach((btn) => {
    btn.addEventListener('click', () => pickEditAsset(btn.dataset.pick));
});
document.querySelectorAll('[data-sgdb]').forEach((btn) => {
    btn.addEventListener('click', () => {
        const kind = btn.dataset.sgdb;
        openSgdbPicker({
            kind,
            name: $('edit-name').value.trim() || state.edit.game.name,
            onPick: (localPath) => {
                state.edit.pending[kind] = localPath;
                setPreview($('edit-preview-' + kind), assetUrl(localPath));
            },
        });
    });
});

$('btn-pick-rom').addEventListener('click', pickRom);
$('wizard-name').addEventListener('input', () => {
    if (state.wizard) $('wizard-next').disabled = !wizardCanAdvance();
});
document.querySelectorAll('[data-wizpick]').forEach((btn) => {
    btn.addEventListener('click', () => pickWizardAsset(btn.dataset.wizpick));
});
document.querySelectorAll('[data-wizsgdb]').forEach((btn) => {
    btn.addEventListener('click', () => {
        const kind = btn.dataset.wizsgdb;
        openSgdbPicker({
            kind,
            name: $('wizard-name').value.trim(),
            onPick: (localPath) => {
                state.wizard[kind] = localPath;
                setPreview($('wiz-preview-' + kind), assetUrl(localPath));
            },
        });
    });
});

$('sgdb-search-btn').addEventListener('click', sgdbSearch);
$('sgdb-search').addEventListener('keydown', (e) => {
    if (e.key === 'Enter') sgdbSearch();
});
$('sgdb-game').addEventListener('change', sgdbLoadAssets);
$('wizard-next').addEventListener('click', wizardNext);
$('wizard-back').addEventListener('click', wizardBack);

document.querySelectorAll('[data-close]').forEach((btn) => {
    btn.addEventListener('click', () => $(btn.dataset.close).classList.add('hidden'));
});

// Restore the previously opened folders on launch
(async () => {
    const settings = await window.vitro.getSettings();
    state.backupDir = settings.backupDir || null;
    state.steamGridKey = settings.steamGridKey || '';
    const dirs = settings.gameDirs || [];
    if (dirs.length > 0) {
        state.gameDirs = dirs;
        // If an SD card isn't mounted the scan fails; stay on the welcome screen.
        if (await refreshLibrary({ silent: true })) {
            showLibraryView();
        }
    }
})();
