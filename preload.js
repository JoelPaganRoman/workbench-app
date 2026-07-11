const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('tabAPI', {
  switchTab: (key) => ipcRenderer.send('switch-tab', key),
  toggleSplit: () => ipcRenderer.send('toggle-split'),
  closeSplit: () => ipcRenderer.send('close-split'),
  selectPaneTab: (pane, key) => ipcRenderer.send('select-pane-tab', { pane, key }),
  onPanesChanged: (callback) => ipcRenderer.on('panes-changed', (_event, panes, splitMode) => callback(panes, splitMode))
});
