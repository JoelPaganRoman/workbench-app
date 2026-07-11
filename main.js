const { app, BaseWindow, WebContentsView, Menu, shell, ipcMain } = require('electron');
const path = require('path');

const TAB_BAR_HEIGHT = 48;
const PANE_BAR_HEIGHT = 38;

const TABS = {
  docs:   { url: 'https://docs.google.com/document/u/0/',      label: 'Docs' },
  sheets: { url: 'https://docs.google.com/spreadsheets/u/0/',  label: 'Sheets' },
  slides: { url: 'https://docs.google.com/presentation/u/0/',  label: 'Slides' },
  gemini: { url: 'https://gemini.google.com/app',               label: 'Gemini' },
  drive:  { url: 'https://drive.google.com/drive/u/0/my-drive', label: 'Drive' }
};

let win = null;
let chromeView = null;
let views = {};          // key -> WebContentsView (content views, created lazily)
let attachedSet = new Set();
let panes = { left: 'docs', right: null };
let splitMode = false;

function classifyUrl(url) {
  try {
    const u = new URL(url);
    if (u.hostname.includes('drive.google.com')) return 'drive';
    if (u.hostname.includes('gemini.google.com')) return 'gemini';
    if (u.hostname.includes('docs.google.com') || u.hostname.includes('sheets.google.com') || u.hostname.includes('slides.google.com')) {
      if (u.pathname.startsWith('/spreadsheets')) return 'sheets';
      if (u.pathname.startsWith('/presentation')) return 'slides';
      if (u.pathname.startsWith('/document')) return 'docs';
    }
  } catch (e) { /* not a valid absolute URL, ignore */ }
  return null;
}

function getHeaderHeight() {
  return TAB_BAR_HEIGHT + (splitMode ? PANE_BAR_HEIGHT : 0);
}

function layout() {
  if (!win) return;
  const [width, height] = win.getContentSize();
  const headerH = getHeaderHeight();

  chromeView.setBounds({ x: 0, y: 0, width, height: headerH });

  if (!splitMode) {
    if (views[panes.left]) {
      views[panes.left].setBounds({ x: 0, y: headerH, width, height: height - headerH });
    }
  } else {
    const halfW = Math.floor(width / 2);
    if (views[panes.left]) {
      views[panes.left].setBounds({ x: 0, y: headerH, width: halfW - 1, height: height - headerH });
    }
    if (panes.right && views[panes.right]) {
      views[panes.right].setBounds({ x: halfW + 1, y: headerH, width: width - halfW - 1, height: height - headerH });
    }
  }
}

function attachView(key) {
  if (!attachedSet.has(key)) {
    win.contentView.addChildView(views[key]);
    attachedSet.add(key);
  }
}

function detachView(key) {
  if (attachedSet.has(key)) {
    win.contentView.removeChildView(views[key]);
    attachedSet.delete(key);
  }
}

function openInTab(key, url, sourceKey) {
  const sourcePane = panes.left === sourceKey ? 'left' : (panes.right === sourceKey ? 'right' : 'left');
  if (splitMode) {
    const targetPane = sourcePane === 'left' ? 'right' : 'left';
    setPaneContent(targetPane, key, url);
  } else {
    setPaneContent('left', key, url);
  }
}

function attachNavigationInterception(view, ownKey) {
  view.webContents.on('will-navigate', (event, url) => {
    const target = classifyUrl(url);
    if (target && target !== ownKey) {
      event.preventDefault();
      openInTab(target, url, ownKey);
    }
  });
  view.webContents.setWindowOpenHandler(({ url }) => {
    const target = classifyUrl(url);
    if (target && target !== ownKey) {
      openInTab(target, url, ownKey);
      return { action: 'deny' };
    }
    if (target === ownKey) {
      view.webContents.loadURL(url);
      return { action: 'deny' };
    }
    shell.openExternal(url);
    return { action: 'deny' };
  });
}

function ensureView(key, urlOverride) {
  if (!views[key]) {
    const view = new WebContentsView({
      webPreferences: {
        partition: 'persist:googleworkspace',
        contextIsolation: true,
        nodeIntegration: false
      }
    });
    view.webContents.loadURL(urlOverride || TABS[key].url);
    attachNavigationInterception(view, key);
    views[key] = view;
  }
  return views[key];
}

function renderPanes() {
  const desired = splitMode ? [panes.left, panes.right].filter(Boolean) : [panes.left];
  desired.forEach((k) => { ensureView(k); attachView(k); });
  Array.from(attachedSet).forEach((k) => { if (!desired.includes(k)) detachView(k); });
  layout();
  if (chromeView) chromeView.webContents.send('panes-changed', panes, splitMode);
}

function setPaneContent(pane, key, url) {
  const otherPane = pane === 'left' ? 'right' : 'left';
  if (panes[otherPane] === key) {
    panes[otherPane] = panes[pane]; // swap instead of duplicating a tab in both panes
  }
  panes[pane] = key;
  ensureView(key, url);
  if (url && views[key]) views[key].webContents.loadURL(url);
  renderPanes();
}

function toggleSplit() {
  splitMode = !splitMode;
  if (splitMode && !panes.right) {
    panes.right = panes.left === 'drive' ? 'docs' : 'drive';
  }
  renderPanes();
}

function closeSplit() {
  splitMode = false;
  panes.right = null;
  renderPanes();
}

function createWindow() {
  win = new BaseWindow({
    width: 1360,
    height: 880,
    minWidth: 820,
    minHeight: 540,
    title: 'Workbench',
    backgroundColor: '#00000000',
    transparent: true,
    vibrancy: 'header',
    visualEffectState: 'active',
    titleBarStyle: 'hiddenInset',
    trafficLightPosition: { x: 18, y: (TAB_BAR_HEIGHT - 14) / 2 }
  });

  chromeView = new WebContentsView({
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true
    }
  });
  chromeView.setBackgroundColor('#00000000');
  win.contentView.addChildView(chromeView);
  chromeView.webContents.loadFile('tabbar.html');

  chromeView.webContents.on('did-finish-load', () => {
    renderPanes();
    layout();
  });

  win.on('resize', layout);
  win.on('resized', layout);

  win.on('closed', () => {
    win = null;
    chromeView = null;
    views = {};
    attachedSet = new Set();
  });

  const menu = Menu.buildFromTemplate([
    {
      label: app.name,
      submenu: [
        { role: 'about' }, { type: 'separator' },
        { role: 'hide' }, { role: 'hideOthers' }, { role: 'unhide' }, { type: 'separator' },
        { role: 'quit' }
      ]
    },
    {
      label: 'Editar',
      submenu: [
        { role: 'undo' }, { role: 'redo' }, { type: 'separator' },
        { role: 'cut' }, { role: 'copy' }, { role: 'paste' }, { role: 'selectAll' }
      ]
    },
    {
      label: 'Ver',
      submenu: [
        { label: 'Docs',   accelerator: 'CmdOrCtrl+1', click: () => setPaneContent('left', 'docs') },
        { label: 'Sheets', accelerator: 'CmdOrCtrl+2', click: () => setPaneContent('left', 'sheets') },
        { label: 'Slides', accelerator: 'CmdOrCtrl+3', click: () => setPaneContent('left', 'slides') },
        { label: 'Gemini', accelerator: 'CmdOrCtrl+4', click: () => setPaneContent('left', 'gemini') },
        { label: 'Drive',  accelerator: 'CmdOrCtrl+5', click: () => setPaneContent('left', 'drive') },
        { type: 'separator' },
        { label: 'Alternar pantalla dividida', accelerator: 'CmdOrCtrl+\\', click: () => toggleSplit() },
        {
          label: 'Recargar pestaña activa',
          accelerator: 'CmdOrCtrl+R',
          click: () => { if (views[panes.left]) views[panes.left].webContents.reload(); }
        },
        { role: 'togglefullscreen' }
      ]
    },
    { label: 'Ventana', submenu: [{ role: 'minimize' }, { role: 'zoom' }, { role: 'close' }] }
  ]);
  Menu.setApplicationMenu(menu);
}

ipcMain.on('switch-tab', (event, key) => setPaneContent('left', key));
ipcMain.on('toggle-split', () => toggleSplit());
ipcMain.on('close-split', () => closeSplit());
ipcMain.on('select-pane-tab', (event, { pane, key }) => setPaneContent(pane, key));

app.whenReady().then(createWindow);

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

app.on('activate', () => {
  if (!win) createWindow();
});
