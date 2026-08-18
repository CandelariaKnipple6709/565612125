const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');
const os = require('os');
const fs = require('fs');
const crypto = require('crypto');
const QRCode = require('qrcode');
const { startSignalingServer } = require('./signaling');

const PORT = 8081;
let server = null;
let mainWindow = null;
let currentRoom = null;

// Baked-in default ngrok authtoken, so the app connects automatically on
// first run with nothing to paste in the UI.
//
// SECURITY NOTE: this value ends up in the GitHub repository's source
// (main.js) exactly as committed — anyone with access to the repo can
// read it. If the repo is public, that means anyone on the internet can
// see and use this token under your ngrok account. Keep this repo
// PRIVATE, or replace this constant with an empty string and paste the
// token into the app's UI instead (Settings -> "Доступ через интернет"),
// which keeps it local-only and out of git entirely.
const DEFAULT_NGROK_TOKEN = '3I4MVZf4mgt0NsQk5AFEQO7r5A7_6SqkMQRVHM244tuM9c6Zm';

// ---- local config (ngrok token) --------------------------------------
// Stored per-machine under Electron's userData folder — NEVER inside the
// repo, so it can't accidentally end up on GitHub. The token is a personal
// credential tied to the user's own free ngrok.com account.
function configPath() {
  return path.join(app.getPath('userData'), 'camswap-config.json');
}

function loadConfig() {
  try {
    const raw = fs.readFileSync(configPath(), 'utf8');
    return JSON.parse(raw);
  } catch (e) {
    return {};
  }
}

function saveConfig(cfg) {
  try {
    fs.mkdirSync(path.dirname(configPath()), { recursive: true });
    fs.writeFileSync(configPath(), JSON.stringify(cfg, null, 2), 'utf8');
  } catch (e) {
    console.error('[camswap] failed to save config:', e);
  }
}

let config = {};

// ---- ngrok tunnel -------------------------------------------------------
// When a token is set, we open a public https tunnel to our local
// signaling server (PORT) and use its wss:// equivalent as the pairing
// address. This is what lets an https:// streaming site open the
// signaling WebSocket at all (browsers block ws:// from a secure page),
// and it also removes the "same Wi-Fi network" requirement entirely.
let ngrokListener = null;
let ngrokUrl = null; // wss://... once the tunnel is up
let ngrokStatus = { state: 'disabled', message: '' }; // disabled|starting|connected|error

function notifyNgrokStatus() {
  if (mainWindow) {
    mainWindow.webContents.send('camswap-ngrok-status', ngrokStatus);
  }
}

async function stopNgrokTunnel() {
  if (ngrokListener) {
    try { await ngrokListener.close(); } catch (e) { /* ignore */ }
    ngrokListener = null;
  }
  ngrokUrl = null;
}

async function startNgrokTunnel(token) {
  await stopNgrokTunnel();

  if (!token) {
    ngrokStatus = { state: 'disabled', message: '' };
    notifyNgrokStatus();
    await sendPairingInfo(); // fall back to local IP in the QR
    return;
  }

  ngrokStatus = { state: 'starting', message: 'подключение к ngrok...' };
  notifyNgrokStatus();

  try {
    const ngrok = require('@ngrok/ngrok');
    const listener = await ngrok.forward({ addr: PORT, authtoken: token });
    ngrokListener = listener;
    const httpsUrl = listener.url(); // e.g. https://abcd1234.ngrok-free.app
    ngrokUrl = httpsUrl.replace(/^https:/, 'wss:');
    ngrokStatus = { state: 'connected', message: ngrokUrl };
    notifyNgrokStatus();
    // Upgrade the pairing info (QR/room text) to the public wss:// address
    // now that the tunnel is actually up.
    await sendPairingInfo();
  } catch (e) {
    console.error('[camswap] ngrok tunnel failed:', e);
    ngrokUrl = null;
    ngrokStatus = { state: 'error', message: (e && e.message) || String(e) };
    notifyNgrokStatus();
    await sendPairingInfo(); // fall back to local IP in the QR
  }
}

function isLinkLocal(address) {
  // 169.254.0.0/16 — Windows self-assigns these (APIPA) to adapters that
  // aren't actually connected to anything (disabled NICs, unplugged
  // Ethernet, some virtual adapters). They're never reachable from a
  // phone, so must never be offered up for QR pairing.
  return address.startsWith('169.254.');
}

function candidateInterfaces() {
  const ifaces = os.networkInterfaces();
  const candidates = [];
  for (const name of Object.keys(ifaces)) {
    for (const iface of ifaces[name]) {
      if (iface.family === 'IPv4' && !iface.internal && !isLinkLocal(iface.address)) {
        candidates.push({ name, address: iface.address });
      }
    }
  }
  return candidates;
}

function getLocalIPv4() {
  const candidates = candidateInterfaces();
  if (candidates.length === 0) {
    return '127.0.0.1'; // fallback — QR pairing won't work off-device, but
                         // the app still runs for local debugging.
  }

  // Prefer adapters that look like a real Wi-Fi/Ethernet connection over
  // VPN/virtual/container adapters, which commonly show up alongside the
  // real one and would otherwise win by being listed first.
  const preferredNamePattern = /wi-?fi|wlan|ethernet|en0|eth0/i;
  const preferred = candidates.find(c => preferredNamePattern.test(c.name));
  if (preferred) return preferred.address;

  // Otherwise avoid obviously-virtual adapters if any real-looking one
  // exists among the remaining candidates.
  const avoidPattern = /virtual|vmware|virtualbox|hyper-v|vethernet|tailscale|zerotier|loopback|docker|wsl/i;
  const nonVirtual = candidates.find(c => !avoidPattern.test(c.name));
  if (nonVirtual) return nonVirtual.address;

  return candidates[0].address;
}

function randomRoom() {
  return 'cam-' + crypto.randomBytes(4).toString('hex');
}

async function buildPairingPayload(room) {
  // Prefer the public ngrok wss:// address (works from anywhere, and is
  // the only way an https:// streaming site will accept the signaling
  // connection at all) when the tunnel is up; otherwise fall back to the
  // local LAN address (ws://, requires the phone on the same Wi-Fi).
  let serverUrl;
  if (ngrokUrl) {
    serverUrl = ngrokUrl;
  } else {
    const ip = getLocalIPv4();
    serverUrl = `ws://${ip}:${PORT}`;
  }
  const payload = JSON.stringify({ v: 1, server: serverUrl, room });
  const qrDataUrl = await QRCode.toDataURL(payload, { margin: 1, scale: 6 });
  return { serverUrl, room, port: PORT, qrDataUrl, usingNgrok: !!ngrokUrl };
}

async function sendPairingInfo() {
  if (!mainWindow) return;
  const info = await buildPairingPayload(currentRoom);
  mainWindow.webContents.send('camswap-pairing', info);
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 820,
    minWidth: 960,
    minHeight: 640,
    backgroundColor: '#111111',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      // Needed for canvas.captureStream()/getUserMedia-free WebRTC sending
      // and for the local <-> phone media flow in general.
      backgroundThrottling: false
    }
  });

  mainWindow.loadFile(path.join(__dirname, 'renderer', 'index.html'));

  mainWindow.webContents.on('did-finish-load', () => {
    sendPairingInfo();
    notifyNgrokStatus();
  });
}

app.whenReady().then(() => {
  currentRoom = randomRoom();
  server = startSignalingServer({ port: PORT, log: console.log });
  config = loadConfig();

  // First run (no local config yet, e.g. a fresh install): fall back to
  // the baked-in token so ngrok connects automatically with no manual
  // step. Once the user has explicitly set a token via the UI (even to
  // change it), that saved value always wins over the baked-in default.
  if (!config.ngrokToken && DEFAULT_NGROK_TOKEN) {
    config.ngrokToken = DEFAULT_NGROK_TOKEN;
    saveConfig(config);
  }

  ipcMain.handle('camswap:get-pairing-info', async () => {
    return buildPairingPayload(currentRoom);
  });

  ipcMain.handle('camswap:regenerate-room', async () => {
    currentRoom = randomRoom();
    const info = await buildPairingPayload(currentRoom);
    return info;
  });

  ipcMain.handle('camswap:get-config', async () => {
    return {
      hasToken: !!config.ngrokToken,
      ngrokStatus
    };
  });

  ipcMain.handle('camswap:set-ngrok-token', async (event, token) => {
    config.ngrokToken = (token || '').trim();
    saveConfig(config);
    await startNgrokTunnel(config.ngrokToken);
    return { hasToken: !!config.ngrokToken, ngrokStatus };
  });

  createWindow();

  if (config.ngrokToken) {
    // Fire and forget — sendPairingInfo() gets called again once (or if)
    // the tunnel comes up, so the window doesn't need to wait for this.
    startNgrokTunnel(config.ngrokToken);
  }

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (server) server.close();
  stopNgrokTunnel();
  if (process.platform !== 'darwin') app.quit();
});
