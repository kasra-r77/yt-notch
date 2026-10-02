// YT Notch bridge.
//
// Injected at document start into the main frame of music.youtube.com. It reads what is
// playing and presses the site's own controls, and talks to the app through the `ytNotch`
// message handler (page to app) and `window.__ytNotch.command(name, value)` (app to page).
// The contract is in the plan, section "Web bridge contract".
//
// All Google-specific knowledge in the app lives in this file. Plain JavaScript, no
// dependencies, shipped inside the app and never downloaded. It never throws: a lookup that
// fails is reported in a `health` message. It keeps no state the app depends on, and after
// a page reload rebuilds everything from the page.
(() => {
  'use strict';

  if (window.__ytNotch) return;

  const BRIDGE_VERSION = '1';

  // Sources, most stable first:
  //   1. Media Session metadata for title, artist, album and artwork.
  //   2. The page's video element for position, duration, play, pause and seek.
  //   3. The Media Session action handlers the site registers, for next and previous.
  //   4. Page facts and selectors, only where nothing standard exists. All of them are here.
  // Checked against music.youtube.com on 2026-10-02 (docs/spike-report.md).
  const PAGE = {
    // The page's own config says whether the user is signed in; it is set early in <head>.
    signedInConfigKey: 'LOGGED_IN',
    // The like button in the player's action bar. `aria-pressed` is the liked state.
    likeButton: 'like-button-view-model button[aria-pressed]',
    // In the top bar only when signed in.
    accountButton: 'ytmusic-settings-button',
    // Shown when signed out.
    signInLink: 'a[href*="accounts.google.com/ServiceLogin"]',
  };

  const ARTWORK_MIN_PX = 192;
  const HEARTBEAT_PLAYING_MS = 1000;
  const HEARTBEAT_PAUSED_MS = 3000;
  const MEDIA_EVENTS = ['play', 'playing', 'pause', 'ended', 'seeked', 'durationchange', 'loadedmetadata', 'emptied', 'ratechange'];

  const handlers = Object.create(null);
  let readyPosted = false;
  let lastSignedIn = null;
  let lastStateJSON = null;
  let lastHealthJSON = null;
  let reportTimer = null;
  let pulseTimer = null;

  const attempt = (fn, fallback) => {
    try {
      return fn();
    } catch (error) {
      return fallback;
    }
  };

  // MARK: Talking to the app

  function post(type, payload) {
    attempt(() => window.webkit.messageHandlers.ytNotch.postMessage(Object.assign({ type }, payload || {})));
  }

  // MARK: Reading the page

  const video = () => attempt(() => document.querySelector('video'), null);
  const finite = (value) => (typeof value === 'number' && isFinite(value) ? value : null);
  const find = (selector) => attempt(() => document.querySelector(selector), null);

  function readTrack() {
    const metadata = attempt(() => navigator.mediaSession.metadata, null);
    if (!metadata || !metadata.title) return null;
    return {
      title: String(metadata.title),
      artist: String(metadata.artist || ''),
      album: metadata.album ? String(metadata.album) : null,
      artworkURL: pickArtwork(metadata.artwork),
    };
  }

  // The smallest image at least ARTWORK_MIN_PX wide, else the largest there is.
  function pickArtwork(artwork) {
    const images = attempt(() => Array.from(artwork || []), [])
      .map((image) => ({
        src: image && image.src ? String(image.src) : '',
        width: parseInt(String((image && image.sizes) || '0').split(/[x\s]/i)[0], 10) || 0,
      }))
      .filter((image) => image.src);
    if (!images.length) return null;
    images.sort((a, b) => a.width - b.width);
    const bigEnough = images.find((image) => image.width >= ARTWORK_MIN_PX);
    return (bigEnough || images[images.length - 1]).src;
  }

  // The site gives tracks no standard ID, so derive a stable one from the metadata.
  function trackId(track) {
    const text = [track.title, track.artist, track.album || ''].join('\u0001');
    let hash = 0;
    for (let i = 0; i < text.length; i += 1) hash = (hash * 31 + text.charCodeAt(i)) | 0;
    return 'm' + (hash >>> 0).toString(36);
  }

  function readState() {
    const media = video();
    const track = readTrack();
    const like = find(PAGE.likeButton);
    const duration = media ? finite(media.duration) : null;
    return {
      trackId: track ? trackId(track) : null,
      title: track ? track.title : null,
      artist: track ? track.artist : null,
      album: track ? track.album : null,
      artworkURL: track ? track.artworkURL : null,
      duration,
      position: media ? finite(media.currentTime) || 0 : 0,
      isPlaying: Boolean(media && !media.paused && !media.ended),
      canNext: Boolean(handlers.nexttrack || duration !== null),
      canPrevious: Boolean(handlers.previoustrack || media),
      liked: Boolean(like && like.getAttribute('aria-pressed') === 'true'),
    };
  }

  // Names match PlayerCore's Feature. Nothing is missing while no track is loaded.
  function readMissing() {
    const media = video();
    const track = readTrack();
    if (!media && !track) return [];
    const missing = [];
    if (!media) missing.push('playPause', 'seek');
    if (!handlers.nexttrack && !(media && finite(media.duration) !== null)) missing.push('next');
    if (!handlers.previoustrack && !media) missing.push('previous');
    if (!find(PAGE.likeButton)) missing.push('like');
    if (!track) missing.push('metadata');
    return missing;
  }

  // true, false, or null while the page can't tell yet.
  function readSignedIn() {
    const config = attempt(() => (window.ytcfg && typeof window.ytcfg.get === 'function' ? window.ytcfg.get(PAGE.signedInConfigKey) : undefined), undefined);
    if (typeof config === 'boolean') return config;
    if (find(PAGE.signInLink)) return false;
    if (find(PAGE.accountButton)) return true;
    return null;
  }

  // MARK: Reporting

  function scheduleReport() {
    if (reportTimer !== null) return;
    reportTimer = setTimeout(() => {
      reportTimer = null;
      report(false);
    }, 50);
  }

  // Posts state when it changed (and every second while playing), health when it changed,
  // and signedOut when the page drops into its sign-in prompt.
  function report(isHeartbeat) {
    try {
      if (!readyPosted) return;
      const state = readState();
      const stateJSON = JSON.stringify(Object.assign({}, state, { position: Math.round(state.position * 10) / 10 }));
      if (stateJSON !== lastStateJSON || (isHeartbeat && state.isPlaying)) {
        lastStateJSON = stateJSON;
        post('state', state);
      }

      const missing = readMissing();
      const healthJSON = JSON.stringify(missing);
      if (healthJSON !== lastHealthJSON) {
        lastHealthJSON = healthJSON;
        post('health', { ok: missing.length === 0, missing });
      }

      const signedIn = readSignedIn();
      if (signedIn === false && lastSignedIn !== false) post('signedOut');
      if (signedIn !== null) lastSignedIn = signedIn;

      schedulePulse(state.isPlaying);
    } catch (error) {
      schedulePulse(false);
    }
  }

  // A heartbeat for the position while playing, and a slower look for changes that fire no
  // event (the like button, the sign-in prompt) while paused.
  function schedulePulse(isPlaying) {
    if (pulseTimer !== null) clearTimeout(pulseTimer);
    pulseTimer = setTimeout(() => {
      pulseTimer = null;
      report(true);
    }, isPlaying ? HEARTBEAT_PLAYING_MS : HEARTBEAT_PAUSED_MS);
  }

  function postReady() {
    if (readyPosted) return;
    readyPosted = true;
    const signedIn = readSignedIn();
    lastSignedIn = signedIn;
    post('ready', { bridgeVersion: BRIDGE_VERSION, signedIn: signedIn === true });
    report(false);
  }

  // MARK: Commands

  function requireVideo() {
    const media = video();
    if (!media) throw new Error('no video element');
    return media;
  }

  function startPlayback(media) {
    const result = media.play();
    if (result && typeof result.catch === 'function') result.catch(() => {});
  }

  const commands = {
    play() {
      startPlayback(requireVideo());
    },
    pause() {
      requireVideo().pause();
    },
    toggle() {
      const media = requireVideo();
      if (media.paused) startPlayback(media);
      else media.pause();
    },
    next() {
      if (handlers.nexttrack) return handlers.nexttrack({ action: 'nexttrack' });
      // No handler: run to the end of the track and let the site move on by itself.
      const media = requireVideo();
      const duration = finite(media.duration);
      if (duration === null) throw new Error('no duration');
      media.currentTime = Math.max(0, duration - 0.5);
      return undefined;
    },
    previous() {
      if (handlers.previoustrack) return handlers.previoustrack({ action: 'previoustrack' });
      requireVideo().currentTime = 0;
      return undefined;
    },
    seek(seconds) {
      const media = requireVideo();
      const target = Math.max(0, Number(seconds) || 0);
      const duration = finite(media.duration);
      media.currentTime = duration === null ? target : Math.min(target, duration);
    },
    setLiked(liked) {
      const button = find(PAGE.likeButton);
      if (!button) throw new Error('no like button');
      if ((button.getAttribute('aria-pressed') === 'true') !== Boolean(liked)) button.click();
    },
  };

  // Runs a command and says whether it could. Its effect arrives later as a state message.
  function command(name, value) {
    try {
      if (!Object.prototype.hasOwnProperty.call(commands, name)) return { ok: false, error: 'unknown command: ' + name };
      const result = commands[name](value);
      if (result && typeof result.catch === 'function') result.catch(() => {});
      return { ok: true };
    } catch (error) {
      return { ok: false, error: String((error && error.message) || error) };
    } finally {
      scheduleReport();
    }
  }

  // MARK: Setup, at document start before the site's own scripts

  function captureMediaSession() {
    if (!window.MediaSession) return;
    const proto = window.MediaSession.prototype;

    // Keep the newest handler for each action. The site registers them through the
    // prototype, several times while it starts, so wrapping the instance is not enough.
    const setActionHandler = proto.setActionHandler;
    if (typeof setActionHandler === 'function') {
      proto.setActionHandler = function (action, handler) {
        attempt(() => {
          if (typeof handler === 'function') handlers[action] = handler;
          else delete handlers[action];
        });
        return setActionHandler.call(this, action, handler);
      };
    }

    // Metadata has no change event, so note every write.
    const metadata = Object.getOwnPropertyDescriptor(proto, 'metadata');
    if (metadata && metadata.get && metadata.set && metadata.configurable) {
      Object.defineProperty(proto, 'metadata', {
        configurable: true,
        enumerable: metadata.enumerable,
        get() {
          return metadata.get.call(this);
        },
        set(value) {
          metadata.set.call(this, value);
          scheduleReport();
        },
      });
    }
  }

  attempt(captureMediaSession);

  for (const name of MEDIA_EVENTS) {
    attempt(() => document.addEventListener(name, (event) => {
      if (event.target instanceof HTMLMediaElement) scheduleReport();
    }, true));
  }

  attempt(() => Object.defineProperty(window, '__ytNotch', {
    value: Object.freeze({ version: BRIDGE_VERSION, command }),
    configurable: false,
    enumerable: false,
    writable: false,
  }));

  // Ready once the document has loaded. If the page can't tell yet whether the user is
  // signed in, wait for the full load.
  attempt(() => {
    const readyWhenKnown = () => {
      if (readSignedIn() !== null || document.readyState === 'complete') postReady();
      else window.addEventListener('load', postReady, { once: true });
    };
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', readyWhenKnown, { once: true });
    else readyWhenKnown();
  });
})();
