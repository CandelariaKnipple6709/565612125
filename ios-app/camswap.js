/**
 * camswap.js — injected into the WKWebView at document-start, in the
 * main JS world, BEFORE the target site's own scripts run.
 *
 * What it does:
 *   1. Connects to the signaling server as the "receiver" and pulls
 *      in the WebRTC video track being published by the desktop
 *      sender (sender.html, which is fed by "OBS Virtual Camera").
 *   2. Renders that incoming video into a hidden <canvas> at a fixed
 *      frame rate.
 *   3. Overrides navigator.mediaDevices.getUserMedia (and
 *      enumerateDevices) so that when the site loaded in this
 *      WKWebView asks for the camera, it transparently receives
 *      canvas.captureStream() instead of the phone's real camera.
 *      The real microphone is still used for audio, so the
 *      streamer's live voice goes through normally.
 *
 * Configuration is provided by the native app via a small script
 * injected immediately before this one:
 *
 *   window.__CAMSWAP_CONFIG__ = {
 *     serverUrl: "wss://your-server.example.com",
 *     room: "stream-1234",
 *     videoWidth: 1280,
 *     videoHeight: 720,
 *     fps: 30,
 *     showStatusBadge: true
 *   };
 *
 * If no config is present, this script does nothing (site behaves
 * like a stock browser with the real camera).
 */
(function () {
  const cfg = window.__CAMSWAP_CONFIG__;
  if (!cfg || !cfg.serverUrl || !cfg.room) {
    console.warn('[camswap] no config found, real camera will be used');
    return;
  }

  const WIDTH = cfg.videoWidth || 1280;
  const HEIGHT = cfg.videoHeight || 720;
  const FPS = cfg.fps || 30;

  const nativeGetUserMedia = navigator.mediaDevices.getUserMedia
    ? navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices)
    : null;
  const nativeEnumerateDevices = navigator.mediaDevices.enumerateDevices
    ? navigator.mediaDevices.enumerateDevices.bind(navigator.mediaDevices)
    : null;

  // ---- anti-fingerprint helpers ------------------------------------------
  // Some platforms don't just call getUserMedia and accept whatever comes
  // back — they actively try to detect a "virtual camera" / spoofing tool
  // first, and quietly refuse if they find one (this is almost certainly
  // what "видит камеру, но специально не хочет её использовать" is). The
  // two most common checks:
  //   1. Function.prototype.toString() on navigator.mediaDevices.*: a real
  //      native browser method always stringifies to
  //      "function x() { [native code] }" — a plain JS override exposes
  //      its actual source instead, an instant tell.
  //   2. The reported device's deviceId/groupId/label: real iOS camera
  //      devices use long opaque hash-like ids and a real Apple label
  //      ("Back Camera"/"Front Camera"), not an obviously synthetic
  //      string like "camswap-virtual-camera".
  // Both are patched below so the substituted camera reads exactly like a
  // real one at the JS-introspection level, not just at the "did
  // getUserMedia resolve" level.

  function randomHex(len) {
    const bytes = new Uint8Array(Math.ceil(len / 2));
    if (window.crypto && window.crypto.getRandomValues) {
      window.crypto.getRandomValues(bytes);
    } else {
      for (let i = 0; i < bytes.length; i++) bytes[i] = Math.floor(Math.random() * 256);
    }
    return Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('').slice(0, len);
  }

  // CRITICAL: a real camera's deviceId/groupId is STABLE for a given site
  // across visits (Safari derives it from a per-origin salt and keeps
  // reusing it) — it never changes on its own between page loads. Picking
  // a brand new random id on every single reload/re-visit, as this used
  // to do, is one of the most standard fingerprint-consistency checks an
  // anti-fraud system can run: "this device's identity changed between
  // sessions" is a huge red flag, and it lines up exactly with the
  // reported symptom (works, then gets flagged specifically after
  // re-entering the same page). Persisting the id in localStorage (keyed
  // per-origin automatically, same as the real browser behavior it's
  // mimicking) fixes that: generated once, then reused on every later
  // visit to this same site for as long as the site's local data isn't
  // wiped (matching how a real device id would only change if the user
  // cleared site data too).
  function persistentFakeId(key, len) {
    try {
      const existing = window.localStorage.getItem(key);
      if (existing && existing.length === len) return existing;
    } catch (e) { /* localStorage unavailable in this context — fall through */ }
    const fresh = randomHex(len);
    try { window.localStorage.setItem(key, fresh); } catch (e) { /* ignore, not fatal */ }
    return fresh;
  }

  const FAKE_DEVICE_ID = persistentFakeId('__camswap_device_id', 64);
  const FAKE_GROUP_ID = persistentFakeId('__camswap_group_id', 64);
  // facingMode is 'environment' (rear lens) below, since this app is
  // about showing physical spaces — label it the way iOS itself labels
  // the rear camera rather than a generic/synthetic name.
  const FAKE_LABEL = 'Back Camera';

  // Patches Function.prototype.toString itself (once, globally) so any
  // function registered via nativeize() below reports a native-looking
  // string no matter how a page calls it (fn.toString(), String(fn),
  // Function.prototype.toString.call(fn), etc.), while every other
  // function on the page keeps stringifying normally.
  const nativeToStringMap = new WeakMap();
  const realFunctionToString = Function.prototype.toString;
  Function.prototype.toString = function () {
    if (nativeToStringMap.has(this)) return nativeToStringMap.get(this);
    return realFunctionToString.call(this);
  };
  // This patch is itself an overridden function and would unmask itself
  // the moment a page inspects Function.prototype.toString directly —
  // give it an entry in its own map too.
  nativeToStringMap.set(Function.prototype.toString, realFunctionToString.call(realFunctionToString));

  function nativeize(fn, name) {
    nativeToStringMap.set(fn, 'function ' + name + '() { [native code] }');
    return fn;
  }

  // A site can skip string/label checks entirely and just ask
  // "is this actually a CanvasCaptureMediaStreamTrack object?" via
  // `track instanceof CanvasCaptureMediaStreamTrack` — that's true here
  // no matter what we rename its fields to, since it really is one under
  // the hood, and a real hardware camera track never is. Patching
  // Symbol.hasInstance on the class itself is the only way to make that
  // specific check lie too, for exactly the track(s) we've faked.
  const fakedTracks = new WeakSet();
  if (typeof CanvasCaptureMediaStreamTrack !== 'undefined' && !CanvasCaptureMediaStreamTrack.__camswapPatched) {
    const defaultHasInstance = function (instance) {
      return typeof instance === 'object' && instance !== null &&
        CanvasCaptureMediaStreamTrack.prototype.isPrototypeOf(instance);
    };
    Object.defineProperty(CanvasCaptureMediaStreamTrack, Symbol.hasInstance, {
      value: nativeize(function (instance) {
        if (fakedTracks.has(instance)) return false;
        return defaultHasInstance(instance);
      }, '[Symbol.hasInstance]'),
      configurable: true
    });
    CanvasCaptureMediaStreamTrack.__camswapPatched = true;
  }

  // ---- hidden video + canvas plumbing ----------------------------------
  const hiddenVideo = document.createElement('video');
  hiddenVideo.setAttribute('playsinline', '');
  hiddenVideo.muted = true;
  hiddenVideo.autoplay = true;
  hiddenVideo.style.cssText = 'position:fixed;width:1px;height:1px;opacity:0;pointer-events:none;top:-9999px;left:-9999px;';

  const canvas = document.createElement('canvas');
  canvas.width = WIDTH;
  canvas.height = HEIGHT;
  const ctx = canvas.getContext('2d', { alpha: false });
  // Fallback fill so the substituted stream is never a fully blank
  // frame before the WebRTC connection is up.
  ctx.fillStyle = '#000';
  ctx.fillRect(0, 0, WIDTH, HEIGHT);

  // A canvas-captured track (CanvasCaptureMediaStreamTrack) reports empty/
  // missing getSettings()/getCapabilities() by default, unlike a real
  // camera track. Some sites validate the track this way (not just via
  // getUserMedia succeeding) before deciding a "real" camera is present,
  // and reject an empty-capabilities track. Patch the track's own methods
  // to report camera-like values so those checks pass too.
  function patchFakeVideoTrack(track) {
    const fakeSettings = {
      deviceId: FAKE_DEVICE_ID,
      groupId: FAKE_GROUP_ID,
      width: WIDTH,
      height: HEIGHT,
      frameRate: FPS,
      aspectRatio: WIDTH / HEIGHT,
      facingMode: 'environment',
      resizeMode: 'none'
    };
    // Capability ranges tuned to match the iPhone XR's actual single rear
    // camera specifically (not a generic/made-up range): its video capture
    // tops out at 4K/30fps or 1080p up to 60fps, aspect ratio is a normal
    // 16:9-ish range, and — critically — a real XR back-camera device
    // only ever reports 'environment' in its facingMode capability list,
    // never 'user' (that's the separate, distinct front-camera device on
    // a real phone). Reporting both here was itself a tell: this device
    // is supposed to BE the back camera, not a device that could be
    // either.
    const fakeCapabilities = {
      deviceId: FAKE_DEVICE_ID,
      groupId: FAKE_GROUP_ID,
      width: { min: 1, max: Math.max(WIDTH, 3840) },
      height: { min: 1, max: Math.max(HEIGHT, 2160) },
      frameRate: { min: 1, max: Math.max(FPS, 60) },
      aspectRatio: { min: 0.5625, max: 1.7778 },
      facingMode: ['environment'],
      resizeMode: ['none', 'crop-and-scale']
    };

    try {
      Object.defineProperty(track, 'label', { value: FAKE_LABEL, configurable: true });
    } catch (e) { /* some engines make label non-configurable; harmless if so */ }

    // Also mask the object's own class identity: a page that does
    // track.constructor.name would otherwise see
    // "CanvasCaptureMediaStreamTrack" instead of "MediaStreamTrack".
    try {
      if (typeof MediaStreamTrack !== 'undefined') {
        Object.defineProperty(track, 'constructor', { value: MediaStreamTrack, configurable: true });
      }
    } catch (e) { /* non-configurable in some engines; harmless if so */ }

    // Makes `track instanceof CanvasCaptureMediaStreamTrack` report false
    // for this specific track (see the Symbol.hasInstance patch above) —
    // a real camera track never is one, so a site checking the object's
    // actual type instead of just its label/id would otherwise still
    // catch the substitution here.
    fakedTracks.add(track);

    const nativeGetSettings = track.getSettings ? track.getSettings.bind(track) : null;
    track.getSettings = nativeize(function getSettings() {
      const base = nativeGetSettings ? (nativeGetSettings() || {}) : {};
      return Object.assign({}, base, fakeSettings);
    }, 'getSettings');

    track.getCapabilities = nativeize(function getCapabilities() {
      return fakeCapabilities;
    }, 'getCapabilities');

    // Real getUserMedia callers sometimes call applyConstraints() after
    // the fact (e.g. to switch resolution/facingMode) — a canvas track
    // can't actually honor that, but resolving instead of throwing keeps
    // sites that don't check the result from treating it as fatal.
    track.applyConstraints = nativeize(function applyConstraints() {
      return Promise.resolve();
    }, 'applyConstraints');

    return track;
  }

  let canvasStream = null;
  function getCanvasStream() {
    if (!canvasStream) {
      canvasStream = canvas.captureStream(FPS);
      canvasStream.getVideoTracks().forEach(patchFakeVideoTrack);
    }
    return canvasStream;
  }

  let drawing = false;
  function startDrawLoop() {
    if (drawing) return;
    drawing = true;
    const draw = () => {
      if (!drawing) return;
      if (hiddenVideo.readyState >= 2) {
        // letterbox/cover the incoming frame into the fixed canvas size
        const vw = hiddenVideo.videoWidth || WIDTH;
        const vh = hiddenVideo.videoHeight || HEIGHT;
        const scale = Math.max(WIDTH / vw, HEIGHT / vh);
        const dw = vw * scale, dh = vh * scale;
        const dx = (WIDTH - dw) / 2, dy = (HEIGHT - dh) / 2;
        ctx.drawImage(hiddenVideo, dx, dy, dw, dh);
      }
      requestAnimationFrame(draw);
    };
    requestAnimationFrame(draw);
  }

  document.documentElement.appendChild(hiddenVideo);

  // ---- status reporting ---------------------------------------------------
  // The connection/video status is now shown as a small native dot in the
  // app's own bottom bar (see BrowserTab.swift + ContentView.swift)
  // instead of an in-page DOM badge, so it can't be seen/removed by the
  // site itself and doesn't clutter the page. This posts a structured
  // {kind, text} message to the native side on every status change; the
  // in-page badge below is kept ONLY as an opt-in debugging aid
  // (cfg.showStatusBadge), off by default.
  let badge = null;
  function postNativeStatus(kind, text) {
    try {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.camswapStatus) {
        window.webkit.messageHandlers.camswapStatus.postMessage({ kind: kind, text: text });
      }
    } catch (e) { /* no bridge registered (e.g. running outside the app) — ignore */ }
  }
  function setStatus(text, color, kind) {
    postNativeStatus(kind || 'idle', text);
    if (!cfg.showStatusBadge) return;
    if (!badge) {
      badge = document.createElement('div');
      badge.style.cssText = 'position:fixed;bottom:8px;left:8px;z-index:2147483647;font:12px -apple-system,sans-serif;padding:4px 8px;border-radius:6px;background:rgba(0,0,0,0.6);color:#fff;pointer-events:none;';
      const attach = () => document.documentElement.appendChild(badge);
      if (document.body) attach(); else document.addEventListener('DOMContentLoaded', attach);
    }
    badge.textContent = 'camswap: ' + text;
    badge.style.color = color || '#fff';
  }

  // ---- signaling / WebRTC receiver --------------------------------------
  let ws = null;
  let pc = null;
  let reconnectTimer = null;

  function iceServers() {
    return [{ urls: 'stun:stun.l.google.com:19302' }];
  }

  function connectSignaling() {
    setStatus('соединение...', '#66aaff', 'connecting');

    try {
      ws = new WebSocket(cfg.serverUrl);
    } catch (e) {
      // Most common cause: the page is https:// but serverUrl is ws://
      // (not wss://) — browsers throw a SecurityError synchronously for
      // that "mixed content" combination instead of failing later.
      //
      // Schedule the retry directly instead of going through
      // scheduleReconnect() — that function immediately overwrites the
      // status text with "переподключение...", which would otherwise
      // hide this message the instant it appears.
      setStatus('ошибка: небезопасное соединение — используйте wss:// вместо ws:// (' + e.message + ')', '#ff6b6b', 'error');
      if (!reconnectTimer) {
        reconnectTimer = setTimeout(() => {
          reconnectTimer = null;
          connectSignaling();
        }, 4000);
      }
      return;
    }

    ws.onopen = () => {
      ws.send(JSON.stringify({ type: 'join', room: cfg.room, role: 'receiver' }));
    };

    ws.onclose = scheduleReconnect;
    ws.onerror = scheduleReconnect;

    ws.onmessage = async (ev) => {
      let msg;
      try { msg = JSON.parse(ev.data); } catch (e) { return; }

      if (msg.type === 'joined') {
        setStatus('в комнате, жду сигнал от OBS...', '#66aaff', 'connecting');
        return;
      }

      if (msg.type === 'error') {
        setStatus('ошибка сервера: ' + msg.message, '#ff6b6b', 'error');
        return;
      }

      if (msg.type === 'peer-left') {
        setStatus('источник отключился', '#66aaff', 'connecting');
        if (pc) { pc.close(); pc = null; }
        return;
      }

      if (msg.type === 'offer') {
        pc = new RTCPeerConnection({ iceServers: iceServers() });

        pc.ontrack = (ev2) => {
          hiddenVideo.srcObject = ev2.streams[0];
          hiddenVideo.play().catch(() => {});
          startDrawLoop();
          setStatus('видео получено', '#7CFC7C', 'connected');
        };

        pc.onicecandidate = (ev2) => {
          if (ev2.candidate) {
            ws.send(JSON.stringify({ type: 'ice-candidate', candidate: ev2.candidate }));
          }
        };

        pc.onconnectionstatechange = () => {
          if (pc.connectionState === 'failed' || pc.connectionState === 'disconnected') {
            setStatus('соединение прервано (' + pc.connectionState + ')', '#ff6b6b', 'error');
          }
        };

        await pc.setRemoteDescription(new RTCSessionDescription(msg.sdp));
        const answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        ws.send(JSON.stringify({ type: 'answer', sdp: answer }));
        return;
      }

      if (msg.type === 'ice-candidate' && pc && msg.candidate) {
        try { await pc.addIceCandidate(msg.candidate); } catch (e) { /* ignore */ }
        return;
      }
    };
  }

  function scheduleReconnect() {
    if (reconnectTimer) return;
    setStatus('переподключение...', '#ffdd55', 'reconnecting');
    reconnectTimer = setTimeout(() => {
      reconnectTimer = null;
      connectSignaling();
    }, 2000);
  }

  // ---- getUserMedia / enumerateDevices override --------------------------
  // IMPORTANT: this override is installed BEFORE connectSignaling() runs
  // below. If the signaling connection throws (e.g. mixed-content
  // SecurityError from ws:// on an https:// page) or fails for any other
  // reason, the site still gets the substituted camera (showing a black
  // frame until a stream arrives) instead of silently falling back to the
  // phone's real camera because an unrelated error aborted the script.
  const fakeVideoDevice = {
    deviceId: FAKE_DEVICE_ID,
    groupId: FAKE_GROUP_ID,
    kind: 'videoinput',
    label: FAKE_LABEL,
    toJSON() { return this; }
  };

  navigator.mediaDevices.getUserMedia = nativeize(async function getUserMedia(constraints) {
    const wantsVideo = !!(constraints && constraints.video);
    const wantsAudio = !!(constraints && constraints.audio);

    if (!wantsVideo) {
      // Pure audio (or empty) request: pass straight through to the
      // real device, nothing to substitute.
      if (!nativeGetUserMedia) throw new DOMException('getUserMedia unavailable', 'NotSupportedError');
      return nativeGetUserMedia(constraints);
    }

    const tracks = [getCanvasStream().getVideoTracks()[0]];

    if (wantsAudio) {
      try {
        if (!nativeGetUserMedia) throw new Error('no native getUserMedia');
        const audioOnly = await nativeGetUserMedia({ audio: constraints.audio });
        const at = audioOnly.getAudioTracks()[0];
        if (at) tracks.push(at);
      } catch (e) {
        console.warn('[camswap] could not acquire real microphone:', e);
      }
    }

    return new MediaStream(tracks);
  }, 'getUserMedia');

  if (nativeEnumerateDevices) {
    navigator.mediaDevices.enumerateDevices = nativeize(async function enumerateDevices() {
      const real = await nativeEnumerateDevices();
      // Keep real audio inputs (so mic selection still works), but
      // replace video inputs with the single fake camera entry so
      // device pickers on the site don't expose/select the real lens.
      const audioOnly = real.filter(d => d.kind !== 'videoinput');
      return [fakeVideoDevice, ...audioOnly];
    }, 'enumerateDevices');
  }

  // ---- navigator.permissions.query override -----------------------------
  // Some sites check camera/mic permission status via the Permissions API
  // BEFORE ever calling getUserMedia — if that reports anything other than
  // "granted" (WKWebView's support for the 'camera'/'microphone' query
  // names is unreliable), the site can bail out early with a "no camera"
  // message without ever reaching our getUserMedia override above. This
  // makes those two names always resolve as already-granted; everything
  // else (e.g. 'geolocation', 'notifications') still goes through the
  // native implementation untouched.
  if (navigator.permissions && navigator.permissions.query) {
    const nativePermissionsQuery = navigator.permissions.query.bind(navigator.permissions);

    function fakePermissionStatus(name) {
      const target = new EventTarget();
      Object.defineProperties(target, {
        state: { value: 'granted', writable: false, enumerable: true },
        name: { value: name, writable: false, enumerable: true },
        onchange: { value: null, writable: true, enumerable: true }
      });
      return target;
    }

    navigator.permissions.query = nativeize(function query(descriptor) {
      const name = descriptor && descriptor.name;
      if (name === 'camera' || name === 'microphone') {
        return Promise.resolve(fakePermissionStatus(name));
      }
      return nativePermissionsQuery(descriptor);
    }, 'query');
  }

  console.info('[camswap] camera substitution active, room=' + cfg.room);

  connectSignaling();
})();
