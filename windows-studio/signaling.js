/**
 * Same signaling relay as signaling-server/server.js, extracted into a
 * reusable function so it can run embedded inside the Electron main
 * process (no separate `node server.js` step for the Windows app) while
 * staying testable on its own with plain Node.
 *
 * Pairs ONE sender (this app) with ANY NUMBER of receivers (each open
 * iOS tab is its own receiver connection) per room, and relays SDP/ICE
 * JSON between the sender and whichever specific receiver a message is
 * addressed to. No media passes through this server at all — only
 * signaling messages.
 *
 * Each receiver gets a server-assigned clientId on join. WebRTC is
 * inherently point-to-point, so supporting multiple simultaneous
 * receivers means the sender keeps one separate RTCPeerConnection per
 * receiver (see renderer.js) — this server's job is just to route each
 * message to the right one of those, via targetId (sender -> receiver)
 * and an auto-attached fromId (receiver -> sender, since there's only
 * ever one sender to relay to, the receiver doesn't need to address it
 * explicitly).
 */
const http = require('http');
const crypto = require('crypto');
const { WebSocketServer } = require('ws');

function randomClientId() {
  return crypto.randomBytes(6).toString('hex');
}

function safeSend(ws, obj) {
  if (ws && ws.readyState === ws.OPEN) {
    ws.send(JSON.stringify(obj));
  }
}

/**
 * @param {object} opts
 * @param {number} opts.port
 * @param {(msg: string) => void} [opts.log]
 * @returns {{ httpServer: http.Server, wss: WebSocketServer, close: () => void }}
 */
function startSignalingServer({ port, log = () => {} }) {
  // roomId -> { sender: ws|null, receivers: Map<clientId, ws> }
  const rooms = new Map();

  function getRoom(roomId) {
    if (!rooms.has(roomId)) rooms.set(roomId, { sender: null, receivers: new Map() });
    return rooms.get(roomId);
  }

  function deleteRoomIfEmpty(roomId) {
    const room = rooms.get(roomId);
    if (room && !room.sender && room.receivers.size === 0) rooms.delete(roomId);
  }

  function cleanupSocket(ws) {
    if (!ws.roomId || !ws.role) return;
    const room = rooms.get(ws.roomId);
    if (!room) return;

    if (ws.role === 'sender') {
      if (room.sender === ws) room.sender = null;
      // Every receiver loses its one and only peer connection.
      for (const rws of room.receivers.values()) {
        safeSend(rws, { type: 'peer-left' });
      }
    } else {
      if (room.receivers.get(ws.clientId) === ws) room.receivers.delete(ws.clientId);
      // Sender only needs to tear down the ONE RTCPeerConnection that
      // belonged to this specific receiver, not all of them.
      safeSend(room.sender, { type: 'peer-left', peerId: ws.clientId });
    }

    deleteRoomIfEmpty(ws.roomId);
  }

  const httpServer = http.createServer((req, res) => {
    if (req.url === '/health') {
      res.writeHead(200, { 'Content-Type': 'text/plain' });
      res.end('ok');
      return;
    }
    res.writeHead(404);
    res.end();
  });

  const wss = new WebSocketServer({ server: httpServer });

  wss.on('connection', (ws) => {
    ws.isAlive = true;
    ws.on('pong', () => { ws.isAlive = true; });

    ws.on('message', (raw) => {
      let msg;
      try { msg = JSON.parse(raw.toString()); } catch (e) { return; }

      if (msg.type === 'join') {
        const { room: roomId, role } = msg;
        if (!roomId || (role !== 'sender' && role !== 'receiver')) {
          ws.send(JSON.stringify({ type: 'error', message: 'join requires room and role (sender|receiver)' }));
          return;
        }
        const room = getRoom(roomId);

        if (role === 'sender') {
          if (room.sender) {
            ws.send(JSON.stringify({ type: 'error', message: `a sender is already connected to room ${roomId}` }));
            ws.close();
            return;
          }
          room.sender = ws;
          ws.roomId = roomId;
          ws.role = 'sender';
          ws.clientId = randomClientId();
          ws.send(JSON.stringify({ type: 'joined', room: roomId, role, clientId: ws.clientId }));

          // Edge case: receiver(s) already waiting in the room before the
          // sender showed up — introduce them to each other now.
          for (const [receiverId, rws] of room.receivers) {
            safeSend(ws, { type: 'peer-joined', peerId: receiverId });
            safeSend(rws, { type: 'peer-joined', peerId: ws.clientId });
          }
        } else {
          const clientId = randomClientId();
          room.receivers.set(clientId, ws);
          ws.roomId = roomId;
          ws.role = 'receiver';
          ws.clientId = clientId;
          ws.send(JSON.stringify({ type: 'joined', room: roomId, role, clientId }));

          if (room.sender) {
            safeSend(room.sender, { type: 'peer-joined', peerId: clientId });
            safeSend(ws, { type: 'peer-joined', peerId: room.sender.clientId });
          }
        }
        return;
      }

      // Everything else (offer/answer/ice-candidate) is a routed relay
      // message, valid only once joined.
      if (!ws.roomId || !ws.role) return;
      const room = rooms.get(ws.roomId);
      if (!room) return;

      if (ws.role === 'sender') {
        // Sender addresses a specific receiver by targetId — there can
        // be several, so this is required (unlike the receiver side).
        const target = room.receivers.get(msg.targetId);
        if (target) {
          safeSend(target, Object.assign({}, msg, { fromId: ws.clientId }));
        }
      } else {
        // Only one sender per room, so the server can address it on the
        // receiver's behalf — no targetId needed from the receiver.
        if (room.sender) {
          safeSend(room.sender, Object.assign({}, msg, { fromId: ws.clientId }));
        }
      }
    });

    ws.on('close', () => cleanupSocket(ws));
    ws.on('error', () => cleanupSocket(ws));
  });

  const interval = setInterval(() => {
    wss.clients.forEach((ws) => {
      if (ws.isAlive === false) {
        cleanupSocket(ws);
        return ws.terminate();
      }
      ws.isAlive = false;
      ws.ping();
    });
  }, 30000);

  httpServer.listen(port, '0.0.0.0', () => {
    log(`camswap embedded signaling server listening on :${port}`);
  });

  return {
    httpServer,
    wss,
    close() {
      clearInterval(interval);
      wss.close();
      httpServer.close();
    }
  };
}

module.exports = { startSignalingServer };
