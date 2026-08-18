const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('camswap', {
  onPairingInfo: (callback) => {
    ipcRenderer.on('camswap-pairing', (_event, info) => callback(info));
  },
  onNgrokStatus: (callback) => {
    ipcRenderer.on('camswap-ngrok-status', (_event, status) => callback(status));
  },
  getPairingInfo: () => ipcRenderer.invoke('camswap:get-pairing-info'),
  regenerateRoom: () => ipcRenderer.invoke('camswap:regenerate-room'),
  getConfig: () => ipcRenderer.invoke('camswap:get-config'),
  setNgrokToken: (token) => ipcRenderer.invoke('camswap:set-ngrok-token', token)
});
