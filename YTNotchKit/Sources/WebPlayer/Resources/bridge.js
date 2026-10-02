// YT Notch bridge.
//
// Injected at document start into the main frame of music.youtube.com. It reads what is
// playing and presses the site's own controls, and talks to the app through the `ytNotch`
// message handler (page to app) and `window.__ytNotch.command(name, value)` (app to page).
// `window.__ytNotch.refresh()` makes it report everything again, for recovery and wake.
// The contract is in the plan, section "Web bridge contract".
//
// The app downloads nothing itself: the pictures it shows (the track's artwork, the queue's
// thumbnails) come from here, read through the page.
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

    // Library playlists, from the sidebar. The entries are not links: each element carries
    // its data as a property, and `data.navigationEndpoint.browseEndpoint.browseId` is "VL"
    // plus the playlist ID. The sidebar has no thumbnails.
    guideEntry: 'ytmusic-guide-entry-renderer',
    guideEntryTitle: '.title',
    playlistBrowseIdPrefix: 'VL',
    // Liked music's playlist ID. It is pinned first in the list.
    likedMusicId: 'LM',
    // Starting a playlist goes by its address on the site, a full page load. The player
    // page's address keeps the playlist in this parameter while it plays.
    playlistPath: '/watch?list=',
    playlistParam: 'list',

    // The queue. `#contents` holds the playlist; Autoplay suggestions in `#automix-contents`
    // are left out. Songs that also have a video come in pairs, and the counterpart half is
    // left out. The current item's `play-button-state` is "playing" or "paused".
    queueItem: 'ytmusic-player-queue #contents ytmusic-player-queue-item',
    queueItemCounterpart: '#counterpart-renderer',
    queueItemTitle: '.song-title',
    queueItemArtist: '.byline',
    queueItemPlayButton: 'ytmusic-play-button-renderer',
    // Each item's thumbnail and its length as text ("3:45").
    queueItemThumbnail: 'img',
    queueItemDuration: '.duration',

    // Shuffle and repeat live in the player page's controls (on /watch, not the home page).
    // Shuffle: `aria-pressed`. Repeat: `aria-pressed` is false when off, in any language;
    // all and one differ only in the label, which is in the site's language. An unknown
    // label reports repeat as missing rather than guessing.
    shuffleButton: '.ytmusicPlayerControlsShuffleButton button',
    repeatButton: '.ytmusicPlayerControlsRepeatButton button',
    repeatLabels: { 'Repeat off': 'off', 'Repeat all': 'all', 'Repeat one': 'one' },
  };

  const ARTWORK_MIN_PX = 192;
  // Pictures larger than this are not handed over; the app shows its placeholder.
  const ARTWORK_MAX_BYTES = 1000000;
  const ARTWORK_READS_AT_ONCE = 2;
  const HEARTBEAT_PLAYING_MS = 1000;
  const HEARTBEAT_PAUSED_MS = 3000;
  const MEDIA_EVENTS = ['play', 'playing', 'pause', 'ended', 'seeked', 'durationchange', 'loadedmetadata', 'emptied', 'ratechange'];

  const handlers = Object.create(null);
  let readyPosted = false;
  let lastSignedIn = null;
  let lastStateJSON = null;
  let lastHealthJSON = null;
  let lastPlaylistsJSON = null;
  let lastQueueJSON = null;
  let lastModesJSON = null;
  let reportTimer = null;
  // Pictures in use that were sent, or tried, since the page loaded; and those waiting.
  const artworkTried = new Set();
  const artworkWaiting = [];
  let artworkReading = 0;
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
  const findAll = (selector) => attempt(() => Array.from(document.querySelectorAll(selector)), []);
  const textOf = (element) => attempt(() => (element.textContent || '').trim(), '');

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
      playlistId: readPlaylistId(),
    };
  }

  // The playlist in the address, while one plays.
  function readPlaylistId() {
    const id = attempt(() => new URLSearchParams(window.location.search).get(PAGE.playlistParam), null);
    return id || null;
  }

  // Names match PlayerCore's Feature. Each feature is checked on its own, so one broken
  // selector hides only that feature. Player controls count as missing only once a track
  // is loaded.
  function readMissing() {
    const missing = [];
    const media = video();
    const track = readTrack();
    if (media || track) {
      if (!media) missing.push('playPause', 'seek');
      if (!handlers.nexttrack && !(media && finite(media.duration) !== null)) missing.push('next');
      if (!handlers.previoustrack && !media) missing.push('previous');
      if (!find(PAGE.likeButton)) missing.push('like');
      if (!track) missing.push('metadata');
    }
    if (!readPlaylists().length) missing.push('playlists');
    if (!queueElements().length) missing.push('queue');
    const modes = readModes();
    if (modes.shuffle === null) missing.push('shuffle');
    if (modes.repeat === null) missing.push('repeat');
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

  // Library playlists, in sidebar order, without duplicates.
  function readPlaylists() {
    const items = [];
    const seen = new Set();
    for (const entry of findAll(PAGE.guideEntry)) {
      const data = attempt(() => entry.data || entry.__data, null);
      const browseId = attempt(() => data.navigationEndpoint.browseEndpoint.browseId, null);
      if (typeof browseId !== 'string' || !browseId.startsWith(PAGE.playlistBrowseIdPrefix)) continue;
      const id = browseId.slice(PAGE.playlistBrowseIdPrefix.length);
      if (!id || seen.has(id)) continue;
      const title = textOf(attempt(() => entry.querySelector(PAGE.guideEntryTitle), null))
        || attempt(() => data.formattedTitle.runs.map((run) => run.text).join(''), '');
      if (!title) continue;
      seen.add(id);
      items.push({ id, title, thumbnailURL: null, isLikedMusic: id === PAGE.likedMusicId });
    }
    // Liked music first, the rest in sidebar order.
    return items.filter((item) => item.isLikedMusic).concat(items.filter((item) => !item.isLikedMusic));
  }

  // The queue's items in order; their positions are the indexes playQueueItem takes.
  function queueElements() {
    return findAll(PAGE.queueItem).filter((item) => !attempt(() => item.closest(PAGE.queueItemCounterpart), null));
  }

  function isCurrentQueueItem(item) {
    const state = attempt(() => item.getAttribute('play-button-state'), null);
    return (Boolean(state) && state !== 'default') || attempt(() => item.hasAttribute('selected'), false);
  }

  function readQueue() {
    return queueElements().map((item, index) => ({
      index,
      title: textOf(attempt(() => item.querySelector(PAGE.queueItemTitle), null)),
      artist: textOf(attempt(() => item.querySelector(PAGE.queueItemArtist), null)),
      isCurrent: isCurrentQueueItem(item),
      artworkURL: readThumbnail(item),
      duration: parseClock(textOf(attempt(() => item.querySelector(PAGE.queueItemDuration), null))),
    }));
  }

  // A web address only: the site shows placeholders before its thumbnails load.
  function readThumbnail(item) {
    const src = attempt(() => String(item.querySelector(PAGE.queueItemThumbnail).src || ''), '');
    return /^https?:/.test(src) ? src : null;
  }

  // "3:45" or "1:02:03" in seconds, or null.
  function parseClock(text) {
    if (!/^\d+(:\d{1,2}){1,2}$/.test(text)) return null;
    return text.split(':').reduce((total, part) => total * 60 + Number(part), 0);
  }

  // 'off', 'all', 'one', or null when the button's label is not one we know.
  function readRepeat(button) {
    if (attempt(() => button.getAttribute('aria-pressed'), null) === 'false') return 'off';
    const label = attempt(() => (button.getAttribute('aria-label') || button.getAttribute('title') || '').trim(), '');
    return Object.prototype.hasOwnProperty.call(PAGE.repeatLabels, label) ? PAGE.repeatLabels[label] : null;
  }

  // Each mode is null when it can't be read.
  function readModes() {
    const shuffle = find(PAGE.shuffleButton);
    const repeat = find(PAGE.repeatButton);
    return {
      shuffle: shuffle ? attempt(() => shuffle.getAttribute('aria-pressed') === 'true', null) : null,
      repeat: repeat ? readRepeat(repeat) : null,
    };
  }

  // MARK: Artwork

  // Hands over the pictures in use, each once while it stays in use. One that can't be read
  // is not tried again until it has left use and come back, so nothing retries in a loop.
  function requestArtwork(urls) {
    const inUse = new Set(urls.filter((url) => typeof url === 'string' && url));
    for (const url of Array.from(artworkTried)) {
      if (!inUse.has(url)) artworkTried.delete(url);
    }
    for (const url of inUse) {
      if (artworkTried.has(url)) continue;
      artworkTried.add(url);
      artworkWaiting.push(url);
    }
    readWaitingArtwork();
  }

  function readWaitingArtwork() {
    while (artworkReading < ARTWORK_READS_AT_ONCE && artworkWaiting.length) {
      const url = artworkWaiting.shift();
      if (!artworkTried.has(url)) continue;
      artworkReading += 1;
      readArtwork(url)
        .then((picture) => {
          if (picture && artworkTried.has(url)) post('artwork', picture);
        })
        .catch(() => {})
        .finally(() => {
          artworkReading -= 1;
          readWaitingArtwork();
        });
    }
  }

  // The page's own request for a picture it shows: from its cache where it can be, and
  // without cookies. Resolves to { url, mediaType, data } with the bytes in base64, or null.
  // (Not `type`: that names the message.)
  async function readArtwork(url) {
    const response = await window.fetch(url, { cache: 'force-cache', credentials: 'omit', mode: 'cors' });
    if (!response.ok) return null;
    const blob = await response.blob();
    if (!/^image\//.test(blob.type) || blob.size === 0 || blob.size > ARTWORK_MAX_BYTES) return null;
    const dataURL = await new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(String(reader.result));
      reader.onerror = () => reject(reader.error);
      reader.readAsDataURL(blob);
    });
    return { url, mediaType: blob.type, data: dataURL.slice(dataURL.indexOf(',') + 1) };
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

      const playlists = readPlaylists();
      const playlistsJSON = JSON.stringify(playlists);
      if (playlists.length && playlistsJSON !== lastPlaylistsJSON) {
        lastPlaylistsJSON = playlistsJSON;
        post('playlists', { items: playlists });
      }

      const queue = readQueue();
      const queueJSON = JSON.stringify(queue);
      if (queue.length && queueJSON !== lastQueueJSON) {
        lastQueueJSON = queueJSON;
        post('queue', { items: queue });
      }

      requestArtwork([state.artworkURL].concat(queue.map((item) => item.artworkURL)));

      const modes = readModes();
      const modesJSON = JSON.stringify(modes);
      if ((modes.shuffle !== null || modes.repeat !== null) && modesJSON !== lastModesJSON) {
        lastModesJSON = modesJSON;
        post('modes', modes);
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
    playPlaylist(id) {
      if (typeof id !== 'string' || !id) throw new Error('no playlist id');
      window.location.assign(window.location.origin + PAGE.playlistPath + encodeURIComponent(id));
    },
    playQueueItem(index) {
      const item = queueElements()[Number(index)];
      if (!item) throw new Error('no queue item ' + index);
      (item.querySelector(PAGE.queueItemPlayButton) || item).click();
    },
    setShuffle(isOn) {
      const button = find(PAGE.shuffleButton);
      if (!button) throw new Error('no shuffle button');
      if ((button.getAttribute('aria-pressed') === 'true') !== Boolean(isOn)) button.click();
    },
    setRepeat(mode) {
      if (!Object.values(PAGE.repeatLabels).includes(mode)) throw new Error('unknown repeat mode: ' + mode);
      const button = find(PAGE.repeatButton);
      if (!button) throw new Error('no repeat button');
      if (readRepeat(button) === null) throw new Error('repeat mode unreadable');
      // The button cycles off, all, one; click until it shows the mode, at most twice.
      // Stop if the label becomes unreadable, rather than click on blindly.
      return (async () => {
        for (let clicks = 0; clicks < 2; clicks += 1) {
          const shown = readRepeat(button);
          if (shown === mode || shown === null) break;
          button.click();
          await new Promise((resolve) => setTimeout(resolve, 300));
        }
        scheduleReport();
      })();
    },
    // Not a player command: the full window uses it to open the site's own sign-in, which
    // goes on to Google's pages. Fails when there is no sign-in link (already signed in).
    signIn() {
      const link = find(PAGE.signInLink);
      if (!link) throw new Error('no sign-in link');
      link.click();
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

  // Forgets what was last reported and reports everything again.
  function refresh() {
    try {
      lastStateJSON = null;
      lastHealthJSON = null;
      lastPlaylistsJSON = null;
      lastQueueJSON = null;
      lastModesJSON = null;
      if (readyPosted) report(false);
      else postReady();
      return true;
    } catch (error) {
      return false;
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
    value: Object.freeze({ version: BRIDGE_VERSION, command, refresh }),
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
