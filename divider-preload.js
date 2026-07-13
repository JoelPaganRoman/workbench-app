const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('dividerAPI', {
  dragStart: (screenX) => ipcRenderer.send('divider-drag-start', screenX),
  dragMove: (screenX) => ipcRenderer.send('divider-drag-move', screenX),
  dragEnd: () => ipcRenderer.send('divider-drag-end')
});
