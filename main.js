const { app, BaseWindow, WebContentsView, Menu, shell, ipcMain, dialog, screen } = require('electron');
const path = require('path');
const fs = require('fs');
const https = require('https');

const TAB_BAR_HEIGHT_TOP = 48;  // top bar height when tabs are on top
const TAB_BAR_WIDTH_LEFT = 68;  // sidebar width when tabs are on the left
const PANE_BAR_SIZE = 38;  // second row (top mode) / second column (left mode), split mode only
const DIVIDER_SIZE = 6;    // draggable divider thickness between split panes
const MIN_RATIO = 0.15;
const MAX_RATIO = 0.85;

const REPO_OWNER = 'JoelPaganRoman';
const REPO_NAME = 'workbench-app';

const TABS = {
  docs:   { url: 'https://docs.google.com/document/u/0/',      label: 'Docs' },
  sheets: { url: 'https://docs.google.com/spreadsheets/u/0/',  label: 'Sheets' },
  slides: { url: 'https://docs.google.com/presentation/u/0/',  label: 'Slides' },
  gemini: { url: 'https://gemini.google.com/app',               label: 'Gemini' },
  drive:  { url: 'https://drive.google.com/drive/u/0/my-drive', label: 'Drive' }
};

let win = null;
let chromeView = null;
let dividerView = null;
let dividerAttached = false;
let views = {};          // key -> WebContentsView (content views, created lazily)
let attachedSet = new Set();
let panes = { left: 'docs', right: null };
let splitMode = false;

// Content-area geometry, updated every layout() call — the divider drag math
// and the "jump the divider view to cover the whole content area while
// dragging" trick both need this.
let contentGeom = { x: 0, y: 0, width: 0, height: 0 };
let dividerDrag = null;

const DEFAULT_SETTINGS = { tabPosition: 'top', splitRatio: 0.5 };

function getSettingsPath() {
  return path.join(app.getPath('userData'), 'settings.json');
}

function loadSettings() {
  try {
    const stored = JSON.parse(fs.readFileSync(getSettingsPath(), 'utf8'));
    return { ...DEFAULT_SETTINGS, ...stored };
  } catch (e) {
    return { ...DEFAULT_SETTINGS };
  }
}

function saveSettings(partial) {
  const merged = { ...loadSettings(), ...partial };
  try {
    fs.writeFileSync(getSettingsPath(), JSON.stringify(merged, null, 2));
  } catch (e) { /* non-fatal */ }
  return merged;
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

// ---------- Simple update check (GitHub Releases as the update feed) ----------
// Deliberately NOT a silent auto-installer: just checks the latest GitHub
// Release tag against the running app's version, and if newer, shows a
// native dialog with a link to the Releases page. A fully automatic
// download-and-install flow needs a more elaborate signing setup than our
// self-signed certificate reliably supports.
function compareVersions(a, b) {
  const pa = a.split('.').map(Number);
  const pb = b.split('.').map(Number);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const na = pa[i] || 0;
    const nb = pb[i] || 0;
    if (na !== nb) return na - nb;
  }
  return 0;
}

function checkForUpdates(showNoUpdateDialog) {
  const options = {
    hostname: 'api.github.com',
    path: `/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest`,
    headers: { 'User-Agent': 'Workbench-App' }
  };
  https.get(options, (res) => {
    let data = '';
    res.on('data', (chunk) => { data += chunk; });
    res.on('end', () => {
      try {
        const release = JSON.parse(data);
        const latestTag = (release.tag_name || '').replace(/^v/, '');
        const currentVersion = app.getVersion();
        if (latestTag && compareVersions(latestTag, currentVersion) > 0) {
          const settings = loadSettings();
          if (settings.dismissedVersion === latestTag) return; // already said "later" for this one
          dialog.showMessageBox(win, {
            type: 'info',
            title: 'Actualización disponible',
            message: `Hay una nueva versión de Workbench (${latestTag}) disponible.`,
            detail: `Tienes la versión ${currentVersion}.`,
            buttons: ['Descargar', 'Más tarde'],
            defaultId: 0,
            cancelId: 1
          }).then((result) => {
            if (result.response === 0) {
              shell.openExternal(release.html_url || `https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/latest`);
            } else {
              saveSettings({ dismissedVersion: latestTag });
            }
          });
        } else if (showNoUpdateDialog) {
          dialog.showMessageBox(win, {
            type: 'info',
            title: 'Workbench',
            message: 'Ya tienes la última versión.',
            buttons: ['OK']
          });
        }
      } catch (e) { /* network hiccup or malformed response — not worth bothering the user */ }
    });
  }).on('error', () => { /* offline or GitHub unreachable — silently skip */ });
}

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

function getChromeSize(isLeft) {
  const base = isLeft ? TAB_BAR_WIDTH_LEFT : TAB_BAR_HEIGHT_TOP;
  return base + (splitMode ? PANE_BAR_SIZE : 0);
}

function layout() {
  if (!win) return;
  const [width, height] = win.getContentSize();
  const settings = loadSettings();
  const isLeft = settings.tabPosition === 'left';
  const chromeSize = getChromeSize(isLeft);

  if (isLeft) {
    chromeView.setBounds({ x: 0, y: 0, width: chromeSize, height });
    contentGeom = { x: chromeSize, y: 0, width: width - chromeSize, height };
  } else {
    chromeView.setBounds({ x: 0, y: 0, width, height: chromeSize });
    contentGeom = { x: 0, y: chromeSize, width, height: height - chromeSize };
  }

  layoutContentPanes(settings);
}

function layoutContentPanes(settings) {
  const { x, y, width, height } = contentGeom;

  if (!splitMode) {
    if (views[panes.left]) views[panes.left].setBounds({ x, y, width, height });
    hideDivider();
    return;
  }

  const ratio = clamp((settings || loadSettings()).splitRatio, MIN_RATIO, MAX_RATIO);
  const half = DIVIDER_SIZE / 2;
  const firstWidth = Math.round(width * ratio);

  if (views[panes.left]) {
    views[panes.left].setBounds({ x, y, width: firstWidth - half, height });
  }
  if (panes.right && views[panes.right]) {
    views[panes.right].setBounds({
      x: x + firstWidth + half,
      y,
      width: width - firstWidth - half,
      height
    });
  }

  if (!dividerDrag) {
    showDivider(x + firstWidth - half, y, DIVIDER_SIZE, height);
  }
}

function ensureDividerView() {
  if (dividerView) return dividerView;
  dividerView = new WebContentsView({
    webPreferences: {
      preload: path.join(__dirname, 'divider-preload.js'),
      contextIsolation: true
    }
  });
  dividerView.setBackgroundColor('#00000000');
  dividerView.webContents.loadFile('divider.html');
  return dividerView;
}

function showDivider(x, y, w, h) {
  ensureDividerView();
  if (!dividerAttached) {
    win.contentView.addChildView(dividerView);
    dividerAttached = true;
  }
  dividerView.setBounds({ x: Math.round(x), y: Math.round(y), width: Math.round(w), height: Math.round(h) });
}

function hideDivider() {
  if (dividerAttached && dividerView) {
    win.contentView.removeChildView(dividerView);
    dividerAttached = false;
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
    trafficLightPosition: { x: 18, y: 17 }
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
        { label: 'Preferences…', accelerator: 'CmdOrCtrl+,', click: () => openSettingsWindow() },
        { label: 'Check for Updates…', click: () => checkForUpdates(true) },
        { type: 'separator' },
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

ipcMain.on('divider-drag-start', (event, screenX) => {
  const settings = loadSettings();
  dividerDrag = {
    startScreenX: screenX,
    startRatio: settings.splitRatio,
    contentWidth: contentGeom.width
  };
  // Grow the (normally sliver-thin) divider to cover the whole content area
  // for the duration of the drag, so it keeps receiving mousemove even once
  // the cursor moves well past its resting position.
  if (dividerView) {
    dividerView.setBounds({
      x: Math.round(contentGeom.x),
      y: Math.round(contentGeom.y),
      width: Math.round(contentGeom.width),
      height: Math.round(contentGeom.height)
    });
  }
});

ipcMain.on('divider-drag-move', (event, screenX) => {
  if (!dividerDrag) return;
  const deltaX = screenX - dividerDrag.startScreenX;
  const newRatio = clamp(dividerDrag.startRatio + deltaX / dividerDrag.contentWidth, MIN_RATIO, MAX_RATIO);
  saveSettings({ splitRatio: newRatio });
  layoutContentPanes(loadSettings());
});

ipcMain.on('divider-drag-end', () => {
  dividerDrag = null;
  layout(); // shrinks the divider back down to its thin strip at the new position
});

ipcMain.handle('get-settings', () => loadSettings());
ipcMain.handle('save-settings', (event, partial) => {
  const merged = saveSettings(partial);
  layout();
  if (chromeView) chromeView.webContents.send('settings-changed', merged);
  return merged;
});
ipcMain.handle('get-app-version', () => app.getVersion());
ipcMain.on('check-for-updates', () => checkForUpdates(true));

let settingsWin = null;
function openSettingsWindow() {
  if (settingsWin) { settingsWin.focus(); return; }
  const { width, height } = screen.getPrimaryDisplay().workAreaSize;
  const winWidth = 420;
  const winHeight = 340;
  settingsWin = new BaseWindow({
    width: winWidth,
    height: winHeight,
    x: Math.round((width - winWidth) / 2),
    y: Math.round((height - winHeight) / 2),
    title: 'Preferences',
    titleBarStyle: 'hiddenInset',
    backgroundColor: '#000000'
  });
  const settingsView = new WebContentsView({
    webPreferences: {
      preload: path.join(__dirname, 'settings-preload.js'),
      contextIsolation: true
    }
  });
  settingsWin.contentView.addChildView(settingsView);
  settingsView.setBounds({ x: 0, y: 0, width: winWidth, height: winHeight });
  settingsView.webContents.loadFile('settings.html');
  settingsWin.on('closed', () => { settingsWin = null; });
}

app.whenReady().then(() => {
  createWindow();
  setTimeout(() => checkForUpdates(false), 4000);
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

app.on('activate', () => {
  if (!win) createWindow();
});
