/*
 * CloudFloat MediaProbe.js
 *
 * Injected at documentEnd into every frame. It is strictly observational:
 * - never reads or reports media URLs, cookies, tokens or page paths;
 * - only reports origin (scheme + host + port), element counts, readyState and media events;
 * - does not modify the host page's business JavaScript;
 * - optionally adds a small shadow-DOM PiP control because WebKit requires a genuine
 *   user activation inside the web content to enter HTML5 picture-in-picture.
 *
 * The placeholder __CF_BUTTON_ENABLED__ is replaced natively at injection time.
 */
(() => {
  'use strict';

  if (window.__cloudFloatProbeInstalled) {
    return;
  }
  window.__cloudFloatProbeInstalled = true;

  const VERSION = '1.0.0';
  const MAX_VIDEOS = 8;
  const SNAPSHOT_DEBOUNCE_MS = 600;
  const DEFAULT_BUTTON_ENABLED = __CF_BUTTON_ENABLED__;

  const frameId = (() => {
    const bytes = new Uint8Array(8);
    try {
      (window.crypto || {}).getRandomValues(bytes);
      let out = '';
      for (let i = 0; i < bytes.length; i += 1) {
        out += bytes[i].toString(16).padStart(2, '0');
      }
      return out;
    } catch (error) {
      return Math.random().toString(16).slice(2).padEnd(16, '0').slice(0, 16);
    }
  })();

  const origin = (() => {
    try {
      if (!window.location.origin || window.location.origin === 'null') {
        return 'opaque';
      }
      return window.location.origin;
    } catch (error) {
      return 'unavailable';
    }
  })();

  const isTopFrame = (() => {
    try {
      return window.top === window;
    } catch (error) {
      return false;
    }
  })();

  const nativeHandler = (() => {
    try {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.cloudFloatMedia) {
        return window.webkit.messageHandlers.cloudFloatMedia;
      }
    } catch (error) {
      // Ignore; the script must never break the page.
    }
    return null;
  })();

  function post(payload) {
    if (!nativeHandler) {
      return;
    }
    try {
      nativeHandler.postMessage(payload);
    } catch (error) {
      // Ignore.
    }
  }

  // ---------- DOM inspection (no URLs) ----------

  // Open shadow roots are accessible; closed roots are not. Many modern players put
  // <video> inside a web component, so walking open roots materially increases coverage.
  const MAX_SHADOW_ELEMENTS = 4000;

  function collectVideos(root, out, depth) {
    if (!root || depth > 6 || out.length >= MAX_VIDEOS * 4) {
      return;
    }
    try {
      const videos = root.querySelectorAll ? root.querySelectorAll('video') : [];
      for (let i = 0; i < videos.length; i += 1) {
        out.push(videos[i]);
      }
      const elements = root.querySelectorAll ? root.querySelectorAll('*') : [];
      const limit = Math.min(elements.length, MAX_SHADOW_ELEMENTS);
      for (let i = 0; i < limit; i += 1) {
        const shadow = elements[i].shadowRoot;
        if (shadow) {
          collectVideos(shadow, out, depth + 1);
        }
      }
    } catch (error) {
      // Ignore inaccessible/cross-origin roots.
    }
  }

  function allVideos() {
    const out = [];
    collectVideos(document, out, 0);
    return Array.from(new Set(out));
  }

  function pipSupport(video) {
    try {
      if (typeof video.webkitSupportsPresentationMode === 'function') {
        return !!video.webkitSupportsPresentationMode('picture-in-picture');
      }
      if (typeof video.requestPictureInPicture === 'function') {
        return true;
      }
      return false;
    } catch (error) {
      return false;
    }
  }

  function presentationMode(video) {
    try {
      return typeof video.webkitPresentationMode === 'string' ? video.webkitPresentationMode : null;
    } catch (error) {
      return null;
    }
  }

  function srcKind(video) {
    try {
      if (video.srcObject) {
        return 'mediastream';
      }
      const source = video.currentSrc || video.src || '';
      if (!source) {
        return 'none';
      }
      if (source.indexOf('blob:') === 0) {
        return 'blob';
      }
      if (source.indexOf('data:') === 0) {
        return 'data';
      }
      if (source.indexOf('mediastream:') === 0) {
        return 'mediastream';
      }
      return 'network';
    } catch (error) {
      return 'unknown';
    }
  }

  function pipFeatureAllowed() {
    try {
      if (document.featurePolicy && typeof document.featurePolicy.allowsFeature === 'function') {
        return !!document.featurePolicy.allowsFeature('picture-in-picture');
      }
    } catch (error) {
      // Ignore.
    }
    return null;
  }

  function isDRMProtected(video) {
    try {
      return !!(video.mediaKeys || video.webkitKeys);
    } catch (error) {
      return false;
    }
  }

  function describeVideo(video, index) {
    const mode = presentationMode(video);
    return {
      index: index,
      playing: !video.paused && !video.ended,
      paused: !!video.paused,
      ended: !!video.ended,
      readyState: Number(video.readyState) || 0,
      networkState: Number(video.networkState) || 0,
      width: Number(video.videoWidth) || 0,
      height: Number(video.videoHeight) || 0,
      durationSeconds: Number.isFinite(video.duration) ? Math.round(video.duration * 100) / 100 : null,
      muted: !!video.muted,
      volume: Number.isFinite(video.volume) ? video.volume : 0,
      hasSrcObject: !!video.srcObject,
      srcKind: srcKind(video),
      pipSupported: pipSupport(video),
      presentationMode: mode,
      inPiP: mode === 'picture-in-picture',
      drmProtected: isDRMProtected(video),
      pipFeatureAllowed: pipFeatureAllowed()
    };
  }

  function buildSnapshot(reason) {
    const videos = allVideos();
    const inspected = videos.slice(0, MAX_VIDEOS).map(describeVideo);
    const canvases = document.querySelectorAll('canvas').length;
    const iframes = document.querySelectorAll('iframe').length;
    return {
      type: 'snapshot',
      frameId: frameId,
      origin: origin,
      isTopFrame: isTopFrame,
      visibilityState: document.visibilityState || 'unknown',
      videoCount: videos.length,
      videos: inspected,
      canvasCount: canvases,
      iframeCount: iframes,
      documentPiPEnabled: !!document.pictureInPictureEnabled,
      pipFeatureAllowed: pipFeatureAllowed(),
      pageKind: videos.length ? 'media' : (canvases ? 'canvas' : (iframes ? 'nested' : 'static')),
      reason: reason || 'manual',
      timestamp: Date.now()
    };
  }

  function postSnapshot(reason) {
    post(buildSnapshot(reason));
  }

  // ---------- Event reporting ----------

  const lastEventAtByName = Object.create(null);

  function postEvent(name, video, source, force) {
    const now = Date.now();
    const last = lastEventAtByName[name] || 0;
    if (!force && now - last < 200) {
      return;
    }
    lastEventAtByName[name] = now;
    let videoIndex = null;
    if (video) {
      const index = allVideos().indexOf(video);
      videoIndex = index >= 0 ? index : null;
    }
    post({
      type: 'event',
      frameId: frameId,
      origin: origin,
      isTopFrame: isTopFrame,
      name: name,
      videoIndex: videoIndex,
      readyState: video ? Number(video.readyState) || 0 : null,
      presentationMode: video ? presentationMode(video) : null,
      isPlaying: video ? (!video.paused && !video.ended) : null,
      hasVideo: allVideos().length > 0,
      source: source || 'event',
      timestamp: now
    });
    scheduleSnapshot('event:' + name);
    updatePiPButton();
  }

  const STANDARD_MEDIA_EVENTS = [
    'playing',
    'pause',
    'waiting',
    'stalled',
    'emptied',
    'error',
    'loadedmetadata',
    'loadeddata'
  ];

  STANDARD_MEDIA_EVENTS.forEach((name) => {
    document.addEventListener(name, (event) => {
      const target = event.target;
      if (target && target.tagName === 'VIDEO') {
        postEvent(name, target, 'media-event');
      }
    }, true);
  });

  const pipStateByVideo = new WeakMap();

  function reportPiPTransition(video, source) {
    const current = presentationMode(video) === 'picture-in-picture';
    const previous = pipStateByVideo.has(video) ? pipStateByVideo.get(video) : null;
    pipStateByVideo.set(video, current);
    if (current && previous !== true) {
      postEvent('enterpictureinpicture', video, source, true);
    } else if (!current && previous === true) {
      postEvent('leavepictureinpicture', video, source, true);
    } else {
      postEvent('presentationmodechanged', video, source);
    }
  }

  ['enterpictureinpicture', 'leavepictureinpicture', 'webkitpresentationmodechanged'].forEach((name) => {
    document.addEventListener(name, (event) => {
      const target = event.target;
      if (target && target.tagName === 'VIDEO') {
        reportPiPTransition(target, name);
      }
    }, true);
  });

  // ---------- Mutation-driven snapshots ----------

  let snapshotTimer = null;

  function scheduleSnapshot(reason) {
    if (snapshotTimer !== null) {
      return;
    }
    snapshotTimer = window.setTimeout(() => {
      snapshotTimer = null;
      postSnapshot(reason);
    }, SNAPSHOT_DEBOUNCE_MS);
  }

  function isInterestingNode(node) {
    if (!node || node.nodeType !== 1) {
      return false;
    }
    if (node.id === 'cf-pip-host') {
      return false;
    }
    const tag = node.tagName ? node.tagName.toLowerCase() : '';
    if (tag === 'video' || tag === 'canvas' || tag === 'iframe') {
      return true;
    }
    try {
      if (node.querySelector('video,canvas,iframe')) {
        return true;
      }
      if (node.shadowRoot && node.shadowRoot.querySelector('video,canvas,iframe')) {
        return true;
      }
      return false;
    } catch (error) {
      return false;
    }
  }

  function startObserver() {
    try {
      const target = document.documentElement || document;
      if (!target || typeof MutationObserver !== 'function') {
        return;
      }
      const observedRoots = new WeakSet();

      function observeShadowRoots(root, depth) {
        if (!root || depth > 6) {
          return;
        }
        try {
          const elements = root.querySelectorAll ? root.querySelectorAll('*') : [];
          const limit = Math.min(elements.length, MAX_SHADOW_ELEMENTS);
          for (let i = 0; i < limit; i += 1) {
            const shadow = elements[i].shadowRoot;
            if (shadow && !observedRoots.has(shadow)) {
              observedRoots.add(shadow);
              observer.observe(shadow, { childList: true, subtree: true });
              observeShadowRoots(shadow, depth + 1);
            }
          }
        } catch (error) {
          // Ignore.
        }
      }

      const observer = new MutationObserver((records) => {
        let interesting = false;
        for (let i = 0; i < records.length; i += 1) {
          const added = records[i].addedNodes;
          if (!added) {
            continue;
          }
          for (let j = 0; j < added.length; j += 1) {
            if (isInterestingNode(added[j])) {
              interesting = true;
              break;
            }
          }
          if (interesting) {
            break;
          }
        }
        observeShadowRoots(document, 0);
        if (interesting) {
          postEvent('domchanged', null, 'mutation');
          scheduleSnapshot('mutation');
        }
      });
      observer.observe(target, { childList: true, subtree: true });
      observeShadowRoots(document, 0);
    } catch (error) {
      // Ignore.
    }
  }

  // ---------- In-page PiP button ----------

  let buttonEnabled = !!DEFAULT_BUTTON_ENABLED;
  let buttonHost = null;
  let buttonElement = null;
  let toastElement = null;
  let toastTimer = null;
  let temporarilyForced = false;

  function currentlyInPiP() {
    return allVideos().some((video) => presentationMode(video) === 'picture-in-picture');
  }

  function pickBestVideo(preferredIndex) {
    const videos = allVideos();
    if (typeof preferredIndex === 'number' && videos[preferredIndex]) {
      return videos[preferredIndex];
    }
    const playing = videos.filter((video) => !video.paused && !video.ended);
    return playing.filter(pipSupport)[0] || playing[0] || videos.filter(pipSupport)[0] || videos[0] || null;
  }

  const BUTTON_POSITION_KEY = 'cf.pipButtonPosition.v1';
  const BUTTON_SIZE = 44;
  let buttonDrag = null;
  let suppressButtonClick = false;
  let buttonResizeListenerInstalled = false;

  function readStoredButtonPosition() {
    try {
      const raw = window.localStorage.getItem(BUTTON_POSITION_KEY);
      if (!raw) {
        return null;
      }
      const parsed = JSON.parse(raw);
      if (Number.isFinite(parsed.x) && Number.isFinite(parsed.y)) {
        return { x: parsed.x, y: parsed.y };
      }
    } catch (error) {
      // Local storage can be unavailable in sandboxed frames.
    }
    return null;
  }

  function storeButtonPosition(point) {
    try {
      window.localStorage.setItem(BUTTON_POSITION_KEY, JSON.stringify(point));
    } catch (error) {
      // Ignore; dragging still works for this page load.
    }
  }

  function clampButtonPosition(point) {
    const margin = 8;
    // Keep the in-page PiP control below the status bar / Dynamic Island. WKWebView's
    // env(safe-area-inset-top) is often 0 when the page runs edge-to-edge, so use a
    // conservative floor instead of letting a dragged/stored position hide it.
    const topMargin = Math.max(70, margin);
    const width = Math.max(0, window.innerWidth || 0);
    const height = Math.max(0, window.innerHeight || 0);
    return {
      x: Math.min(Math.max(margin, point.x), Math.max(margin, width - BUTTON_SIZE - margin)),
      y: Math.min(
        Math.max(topMargin, point.y),
        Math.max(topMargin, height - BUTTON_SIZE - margin)
      )
    };
  }

  function setButtonPosition(point, persist) {
    if (!buttonHost) {
      return;
    }
    const clamped = clampButtonPosition(point);
    buttonHost.style.setProperty('left', clamped.x + 'px', 'important');
    buttonHost.style.setProperty('top', clamped.y + 'px', 'important');
    buttonHost.style.setProperty('right', 'auto', 'important');
    buttonHost.style.setProperty('bottom', 'auto', 'important');
    if (persist) {
      storeButtonPosition(clamped);
    }
  }

  function installButtonDrag() {
    if (!buttonElement) {
      return;
    }

    buttonElement.addEventListener('pointerdown', (event) => {
      if (event.pointerType === 'mouse' && event.button !== 0) {
        return;
      }
      const rect = buttonHost.getBoundingClientRect();
      event.stopPropagation();
      buttonDrag = {
        pointerId: event.pointerId,
        startX: event.clientX,
        startY: event.clientY,
        left: rect.left,
        top: rect.top,
        moved: false
      };
      suppressButtonClick = false;
      try {
        buttonElement.setPointerCapture(event.pointerId);
      } catch (error) {
        // Ignore.
      }
    }, true);

    buttonElement.addEventListener('pointermove', (event) => {
      if (!buttonDrag || event.pointerId !== buttonDrag.pointerId) {
        return;
      }
      const dx = event.clientX - buttonDrag.startX;
      const dy = event.clientY - buttonDrag.startY;
      if (!buttonDrag.moved && Math.abs(dx) < 5 && Math.abs(dy) < 5) {
        return;
      }
      buttonDrag.moved = true;
      event.preventDefault();
      event.stopPropagation();
      setButtonPosition({ x: buttonDrag.left + dx, y: buttonDrag.top + dy }, false);
    }, true);

    const finishDrag = (event) => {
      if (!buttonDrag || event.pointerId !== buttonDrag.pointerId) {
        return;
      }
      const moved = buttonDrag.moved;
      buttonDrag = null;
      try {
        buttonElement.releasePointerCapture(event.pointerId);
      } catch (error) {
        // Ignore.
      }
      if (!moved) {
        return;
      }
      suppressButtonClick = true;
      window.setTimeout(() => { suppressButtonClick = false; }, 400);
      if (buttonHost) {
        const rect = buttonHost.getBoundingClientRect();
        storeButtonPosition(clampButtonPosition({ x: rect.left, y: rect.top }));
      }
      event.preventDefault();
      event.stopPropagation();
    };
    buttonElement.addEventListener('pointerup', finishDrag, true);
    buttonElement.addEventListener('pointercancel', finishDrag, true);

    if (!buttonResizeListenerInstalled) {
      buttonResizeListenerInstalled = true;
      window.addEventListener('resize', () => {
        if (!buttonHost) {
          return;
        }
        const rect = buttonHost.getBoundingClientRect();
        setButtonPosition({ x: rect.left, y: rect.top }, true);
      }, { passive: true });
    }
  }

  function ensureButton() {
    if (buttonHost) {
      return;
    }
    try {
      buttonHost = document.createElement('div');
      buttonHost.id = 'cf-pip-host';
      buttonHost.setAttribute('data-cloudfloat', 'pip-control');
      buttonHost.style.cssText = [
        'all: initial !important',
        'position: fixed !important',
        'top: max(calc(env(safe-area-inset-top, 0px) + 10px), 70px) !important',
        'right: calc(env(safe-area-inset-right, 0px) + 10px) !important',
        'z-index: 2147483647 !important',
        'width: 44px !important',
        'height: 44px !important',
        'display: block !important',
        'pointer-events: auto !important'
      ].join(';');

      const shadow = buttonHost.attachShadow({ mode: 'closed' });
      shadow.innerHTML = `
        <style>
          :host { all: initial; }
          button {
            all: initial;
            box-sizing: border-box;
            width: 44px;
            height: 44px;
            border-radius: 12px;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            gap: 3px;
            background: rgba(12, 15, 22, 0.72);
            color: #ffffff;
            border: 1px solid rgba(255, 255, 255, 0.30);
            box-shadow: 0 4px 16px rgba(0, 0, 0, 0.35);
            -webkit-backdrop-filter: blur(10px);
            backdrop-filter: blur(10px);
            font: 600 9px/1 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
            letter-spacing: 0.02em;
            cursor: pointer;
            -webkit-user-select: none;
            user-select: none;
            -webkit-tap-highlight-color: transparent;
            -webkit-user-drag: none;
            touch-action: none;
          }
          button:active { transform: scale(0.94); }
          .icon {
            width: 17px;
            height: 11px;
            border: 1.5px solid currentColor;
            border-radius: 3px;
            position: relative;
          }
          .icon::after {
            content: '';
            position: absolute;
            right: -4px;
            bottom: -4px;
            width: 8px;
            height: 6px;
            border: 1.5px solid currentColor;
            border-radius: 2px;
            background: #0c0f16;
          }
          .toast {
            position: fixed;
            top: 60px;
            right: 10px;
            max-width: 200px;
            padding: 7px 10px;
            border-radius: 9px;
            background: rgba(12, 15, 22, 0.92);
            color: #ffffff;
            font: 500 11px/1.4 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
            box-shadow: 0 4px 14px rgba(0, 0, 0, 0.3);
            display: none;
          }
        </style>
        <button type="button" aria-label="进入系统画中画" title="进入系统画中画">
          <span class="icon"></span>
          <span>PiP</span>
        </button>
        <div class="toast" role="status"></div>
      `;
      buttonElement = shadow.querySelector('button');
      toastElement = shadow.querySelector('.toast');
      buttonElement.addEventListener('click', (event) => {
        if (suppressButtonClick) {
          suppressButtonClick = false;
          event.preventDefault();
          event.stopPropagation();
          return;
        }
        const requestId = 'ui-' + Math.random().toString(16).slice(2, 10);
        requestPiP(requestId, null, true);
      }, true);
      const parent = document.documentElement || document.body;
      if (parent) {
        parent.appendChild(buttonHost);
      }
      installButtonDrag();
      const storedPosition = readStoredButtonPosition();
      if (storedPosition) {
        setButtonPosition(storedPosition, false);
      }
    } catch (error) {
      buttonHost = null;
    }
  }

  function showToast(message) {
    if (!toastElement) {
      return;
    }
    toastElement.textContent = message;
    if (buttonHost) {
      const rect = buttonHost.getBoundingClientRect();
      const width = Math.min(200, Math.max(0, window.innerWidth - 16));
      const left = Math.min(Math.max(8, rect.left), Math.max(8, window.innerWidth - width - 8));
      const top = Math.min(rect.bottom + 8, Math.max(8, window.innerHeight - 64));
      toastElement.style.left = left + 'px';
      toastElement.style.top = top + 'px';
      toastElement.style.right = 'auto';
    }
    toastElement.style.display = 'block';
    if (toastTimer !== null) {
      window.clearTimeout(toastTimer);
    }
    toastTimer = window.setTimeout(() => {
      toastElement.style.display = 'none';
      toastTimer = null;
    }, 3200);
  }

  function updatePiPButton() {
    const enabled = buttonEnabled || temporarilyForced;
    if (!enabled) {
      if (buttonHost && buttonHost.parentNode) {
        buttonHost.parentNode.removeChild(buttonHost);
      }
      buttonHost = null;
      buttonElement = null;
      toastElement = null;
      return;
    }
    const videos = allVideos();
    const wantsButton = !currentlyInPiP() &&
      videos.some((video) => !video.paused && !video.ended && pipSupport(video));
    if (!wantsButton) {
      if (buttonHost && buttonHost.parentNode) {
        buttonHost.parentNode.removeChild(buttonHost);
      }
      buttonHost = null;
      buttonElement = null;
      toastElement = null;
      return;
    }
    ensureButton();
  }

  function setButtonEnabled(enabled) {
    buttonEnabled = !!enabled;
    updatePiPButton();
    return buttonEnabled;
  }

  function showPiPButton() {
    temporarilyForced = true;
    updatePiPButton();
    const visible = !!buttonHost;
    if (!visible) {
      // The reason is surfaced natively; this is only a hint in the page.
      showToast('请先开始播放视频');
    }
    return visible;
  }

  function hidePiPButton() {
    temporarilyForced = false;
    updatePiPButton();
    return true;
  }

  // ---------- PiP control ----------

  function normalizePiPError(error) {
    const name = (error && error.name) || 'Error';
    if (name === 'NotAllowedError') {
      return 'requiresUserGesture';
    }
    if (name === 'NotSupportedError') {
      return 'notSupported';
    }
    if (name === 'SecurityError') {
      return 'securityError';
    }
    if (name === 'InvalidStateError' || name === 'AbortError') {
      return 'invalidState';
    }
    return 'promiseRejected:' + name;
  }

  function requestPiP(requestId, preferredIndex, forceReport) {
    const safeRequestId = String(requestId || ('req-' + Math.random().toString(16).slice(2)));
    const video = pickBestVideo(preferredIndex);
    let responded = false;

    function respond(ok, reason, method) {
      if (responded) {
        return;
      }
      responded = true;
      post({
        type: 'pipResult',
        requestId: safeRequestId,
        ok: !!ok,
        reason: reason || null,
        method: method || null,
        frameId: frameId,
        origin: origin,
        isTopFrame: isTopFrame,
        timestamp: Date.now()
      });
      updatePiPButton();
    }

    if (!video) {
      respond(false, 'noVideo');
      return;
    }
    if (video.paused || video.ended) {
      respond(false, 'notPlaying');
      return;
    }
    if (!pipSupport(video)) {
      respond(false, 'notSupported');
      return;
    }
    const mode = presentationMode(video);
    if (mode === 'picture-in-picture') {
      respond(true, null, 'alreadyActive');
      return;
    }
    if (mode === 'fullscreen' && typeof video.webkitSetPresentationMode !== 'function') {
      respond(false, 'invalidState');
      return;
    }

    try {
      if (typeof video.webkitSetPresentationMode === 'function') {
        video.webkitSetPresentationMode('picture-in-picture');
        let attempts = 0;
        const timer = window.setInterval(() => {
          attempts += 1;
          if (presentationMode(video) === 'picture-in-picture') {
            window.clearInterval(timer);
            respond(true, null, 'presentationMode');
          } else if (attempts >= 15) {
            window.clearInterval(timer);
            respond(false, 'presentationModeNotApplied');
          }
        }, 100);
        return;
      }
      if (typeof video.requestPictureInPicture === 'function') {
        const result = video.requestPictureInPicture();
        if (result && typeof result.then === 'function') {
          result.then(() => {
            respond(true, null, 'requestPictureInPicture');
          }).catch((error) => {
            respond(false, normalizePiPError(error), 'requestPictureInPicture');
          });
        } else {
          let attempts = 0;
          const timer = window.setInterval(() => {
            attempts += 1;
            if (document.pictureInPictureElement === video) {
              window.clearInterval(timer);
              respond(true, null, 'requestPictureInPicture');
            } else if (attempts >= 15) {
              window.clearInterval(timer);
              respond(false, 'notApplied');
            }
          }, 100);
        }
        return;
      }
      respond(false, 'notSupported');
    } catch (error) {
      respond(false, normalizePiPError(error), 'exception');
    }
  }

  function exitPiP() {
    try {
      if (document.pictureInPictureElement && typeof document.exitPictureInPicture === 'function') {
        document.exitPictureInPicture().catch(() => {});
        return true;
      }
      const video = allVideos().filter((item) => presentationMode(item) === 'picture-in-picture')[0];
      if (video && typeof video.webkitSetPresentationMode === 'function') {
        video.webkitSetPresentationMode('inline');
        return true;
      }
    } catch (error) {
      return false;
    }
    return false;
  }

  // ---------- Wiring ----------

  document.addEventListener('visibilitychange', () => {
    postEvent('visibilitychange', null, 'visibility');
    postSnapshot('visibility');
    updatePiPButton();
  }, true);

  window.addEventListener('pagehide', () => {
    if (buttonHost && buttonHost.parentNode) {
      buttonHost.parentNode.removeChild(buttonHost);
    }
    buttonHost = null;
    buttonElement = null;
    toastElement = null;
  }, true);

  window.addEventListener('pageshow', () => {
    postSnapshot('pageshow');
    updatePiPButton();
  }, true);

  function install() {
    try {
      startObserver();
      postSnapshot('install');
      updatePiPButton();
      // Give the page a moment to create its media elements.
      window.setTimeout(() => {
        postSnapshot('install-delayed');
        updatePiPButton();
      }, 800);
    } catch (error) {
      // Ignore.
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', install, { once: true });
  } else {
    install();
  }

  const api = {
    version: VERSION,
    frameId: frameId,
    origin: origin,
    snapshot: function (reason) {
      const snapshot = buildSnapshot(reason);
      post(snapshot);
      return snapshot;
    },
    refresh: function () {
      postSnapshot('native-refresh');
      return true;
    },
    requestPiP: requestPiP,
    exitPiP: exitPiP,
    setButtonEnabled: setButtonEnabled,
    showPiPButton: showPiPButton,
    hidePiPButton: hidePiPButton
  };

  try {
    Object.defineProperty(window, '__cloudFloatProbe', {
      value: api,
      configurable: true,
      enumerable: false,
      writable: false
    });
  } catch (error) {
    window.__cloudFloatProbe = api;
  }
})();
