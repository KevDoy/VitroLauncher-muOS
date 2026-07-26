const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('vitro', {
    getSettings: () => ipcRenderer.invoke('settings:get'),
    setGameDirs: (gameDirs) => ipcRenderer.invoke('settings:setGameDirs', gameDirs),
    pickGameFolder: () => ipcRenderer.invoke('dialog:pickGameFolder'),
    pickFile: (kind) => ipcRenderer.invoke('dialog:pickFile', kind),
    scanLibrary: (gameDirs) => ipcRenderer.invoke('library:scan', gameDirs),
    createGame: (payload) => ipcRenderer.invoke('library:createGame', payload),
    updateGame: (payload) => ipcRenderer.invoke('library:updateGame', payload),
    deleteGame: (payload) => ipcRenderer.invoke('library:deleteGame', payload),
    optimizeLibrary: (gameDirs) => ipcRenderer.invoke('library:optimize', gameDirs),
    backupLibrary: (gameDirs, backupDir) => ipcRenderer.invoke('library:backup', gameDirs, backupDir),
    setBackupDir: (backupDir) => ipcRenderer.invoke('settings:setBackupDir', backupDir),
    setSteamGridKey: (key) => ipcRenderer.invoke('settings:setSteamGridKey', key),
    pickBackupFolder: () => ipcRenderer.invoke('dialog:pickBackupFolder'),
    showInFolder: (targetPath) => ipcRenderer.invoke('shell:showInFolder', targetPath),
    sgdbSearch: (term) => ipcRenderer.invoke('sgdb:search', term),
    sgdbAssets: (gameId, kind) => ipcRenderer.invoke('sgdb:assets', gameId, kind),
    sgdbDownload: (url) => ipcRenderer.invoke('sgdb:download', url),
});
