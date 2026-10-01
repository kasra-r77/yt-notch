import AppKit
import WebKit

// Phase 0 spike. Throwaway code.
// S0.1: a visible web view on music.youtube.com with a current Safari user agent and the
//       default persistent data store.
// S0.2: the same web view in a hidden host window that stays ordered in but sits far
//       off-screen, with a playback monitor that logs whether audio keeps moving.

enum Spike {
    static let startURL = URL(string: "https://music.youtube.com")!

    /// Cookies whose presence means the YouTube Music session is signed in.
    static let signInCookies = ["LOGIN_INFO", "SAPISID", "__Secure-3PSID"]

    /// Safari's user agent, built from the Safari installed on this Mac so it stays current.
    static var safariUserAgent: String {
        let plist = URL(fileURLWithPath: "/Applications/Safari.app/Contents/Info.plist")
        let version = NSDictionary(contentsOf: plist)?["CFBundleShortVersionString"] as? String ?? "26.0"
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(version) Safari/605.1.15"
    }

    /// How WebKit schedules the page while the view is not visible. `--policy suspend|throttle|none`;
    /// `none` (no throttling) unless asked otherwise.
    static var schedulingPolicy: WKPreferences.InactiveSchedulingPolicy {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--policy"), i + 1 < args.count else { return .none }
        switch args[i + 1] {
        case "suspend": return .suspend
        case "throttle": return .throttle
        default: return .none
        }
    }

    static func name(of policy: WKPreferences.InactiveSchedulingPolicy) -> String {
        switch policy {
        case .suspend: return "suspend"
        case .throttle: return "throttle"
        case .none: return "none"
        @unknown default: return "unknown"
        }
    }

    static let logsFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs")
    static let logFile = logsFolder.appendingPathComponent("YTNotchSpike.log")
    static let playbackFile = logsFolder.appendingPathComponent("YTNotchSpike-playback.csv")

    /// Logs to the system log and appends to ~/Library/Logs/YTNotchSpike.log.
    static func log(_ message: String) {
        NSLog("[spike] %@", message)
        append("\(ISO8601DateFormatter().string(from: Date())) \(message)\n", to: logFile)
    }

    static func append(_ text: String, to file: URL) {
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? Data(text.utf8).write(to: file)
        }
    }

    /// Reports which sign-in cookies exist in the default data store. Never reads cookie values.
    @MainActor
    static func signInReport() async -> (signedIn: Bool, text: String) {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        var lines: [String] = []
        for name in signInCookies {
            let domains = Set(cookies.filter { $0.name == name }.map(\.domain)).sorted()
            lines.append("\(name): \(domains.isEmpty ? "missing" : domains.joined(separator: ", "))")
        }
        let onYouTube = { (name: String) in
            cookies.contains { $0.name == name && $0.domain.hasSuffix("youtube.com") }
        }
        let signedIn = onYouTube("LOGIN_INFO") && onYouTube("SAPISID")
        let text = (["Signed in: \(signedIn ? "yes" : "no")"] + lines
            + ["\(cookies.count) cookies in the default data store (values are never shown)"])
            .joined(separator: "\n")
        return (signedIn, text)
    }
}

/// A window the system never pulls back on screen, so it can sit far off-screen while
/// staying ordered in.
final class HostWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Samples the page every 5 seconds and logs whether playback keeps pace with the clock.
/// Logs counts and times only; track titles are compared in memory and never written.
final class PlaybackMonitor {
    struct Sample: Decodable {
        let hasVideo: Bool
        let t: Double
        let paused: Bool
        let track: String
        let hidden: Bool
        let waiting: Int
        let stalled: Int
        let pauses: Int
    }

    /// Counts media events on the page from the moment it starts.
    static let statsScript = """
    (() => {
      const s = window.__spikeStats = { waiting: 0, stalled: 0, pause: 0, playing: 0, ended: 0 };
      for (const name of Object.keys(s)) {
        document.addEventListener(name, (e) => { if (e.target instanceof HTMLMediaElement) s[name]++; }, true);
      }
    })();
    """

    static let sampleScript = """
    (() => {
      const v = document.querySelector('video');
      const m = navigator.mediaSession && navigator.mediaSession.metadata;
      const s = window.__spikeStats || {};
      return JSON.stringify({
        hasVideo: !!v, t: v ? v.currentTime : -1, paused: v ? v.paused : true,
        track: m ? (m.title + '\\u0001' + m.artist) : '', hidden: document.hidden,
        waiting: s.waiting || 0, stalled: s.stalled || 0, pauses: s.pause || 0
      });
    })()
    """

    private weak var webView: WKWebView?
    private let policy: String
    private var timer: Timer?
    private var last: (sample: Sample, at: Date)?
    private var trackIndex = 0
    private let startedAt = Date()

    var isHidden = false
    var isDisplayAsleep = false
    var userToggledAt = Date.distantPast

    private(set) var hiddenSeconds = 0.0
    private(set) var playingSeconds = 0.0
    private(set) var playedSeconds = 0.0
    private(set) var stalls = 0
    private(set) var unexpectedPauses = 0
    private(set) var trackChanges = 0
    private(set) var longestGap = 0.0
    private(set) var displaySleeps = 0
    private(set) var spaceChanges = 0
    private var firstEvents: Sample?

    init(webView: WKWebView, policy: String) {
        self.webView = webView
        self.policy = policy
    }

    func start() {
        Spike.append("time,elapsed,window,policy,appActive,displayAsleep,pageHidden,hasVideo,paused,position,wallDelta,playDelta,track,waiting,stalled,pauseEvents,note\n", to: Spike.playbackFile)
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = 0.5
        Spike.log("playback monitor started, policy \(policy), writing \(Spike.playbackFile.path)")
    }

    func note(_ event: String) {
        if event == "display-sleep" { displaySleeps += 1 }
        if event == "space-change" { spaceChanges += 1 }
        Spike.append("\(ISO8601DateFormatter().string(from: Date())),\(Int(Date().timeIntervalSince(startedAt))),,,,,,,,,,,,,,,\(event)\n", to: Spike.playbackFile)
        Spike.log(event)
    }

    private func tick() {
        webView?.evaluateJavaScript(Self.sampleScript) { [weak self] result, _ in
            guard let self, let json = result as? String,
                  let sample = try? JSONDecoder().decode(Sample.self, from: Data(json.utf8)) else { return }
            self.record(sample, at: Date())
        }
    }

    private func record(_ sample: Sample, at now: Date) {
        if firstEvents == nil { firstEvents = sample }
        var wallDelta = 0.0
        var playDelta = 0.0
        var note = ""
        if let (previous, previousAt) = last {
            wallDelta = now.timeIntervalSince(previousAt)
            longestGap = max(longestGap, wallDelta)
            if isHidden { hiddenSeconds += wallDelta }
            let sameTrack = previous.track == sample.track
            if !sameTrack, !sample.track.isEmpty {
                trackIndex += 1
                trackChanges += 1
                note = "track-change"
            } else if !previous.paused, !sample.paused {
                playDelta = sample.t - previous.t
                playingSeconds += wallDelta
                playedSeconds += max(0, playDelta)
                if playDelta < wallDelta * 0.8 {
                    stalls += 1
                    note = "stall"
                }
            }
            if !previous.paused, sample.paused {
                if now.timeIntervalSince(userToggledAt) < 10 {
                    note = "user-pause"
                } else {
                    unexpectedPauses += 1
                    note = "unexpected-pause"
                }
            }
        }
        last = (sample, now)
        let fields: [String] = [
            ISO8601DateFormatter().string(from: now),
            String(Int(now.timeIntervalSince(startedAt))),
            isHidden ? "hidden" : "visible",
            policy,
            NSApp.isActive ? "1" : "0",
            isDisplayAsleep ? "1" : "0",
            sample.hidden ? "1" : "0",
            sample.hasVideo ? "1" : "0",
            sample.paused ? "1" : "0",
            String(format: "%.1f", sample.t),
            String(format: "%.1f", wallDelta),
            String(format: "%.1f", playDelta),
            String(trackIndex),
            String(sample.waiting),
            String(sample.stalled),
            String(sample.pauses),
            note,
        ]
        Spike.append(fields.joined(separator: ",") + "\n", to: Spike.playbackFile)
        if !note.isEmpty { Spike.log("playback: \(note)") }
    }

    var summary: String {
        let minutes = { (s: Double) in String(format: "%.1f min", s / 60) }
        let pace = playingSeconds > 0 ? String(format: "%.1f%%", playedSeconds / playingSeconds * 100) : "n/a"
        let events = { (key: KeyPath<Sample, Int>) -> Int in
            guard let first = self.firstEvents, let latest = self.last?.sample else { return 0 }
            return latest[keyPath: key] - first[keyPath: key]
        }
        return [
            "Monitored: \(minutes(Date().timeIntervalSince(startedAt))), hidden for \(minutes(hiddenSeconds))",
            "Inactive scheduling policy: \(policy)",
            "Playing: \(minutes(playingSeconds)) of wall time, audio advanced \(minutes(playedSeconds)) (\(pace))",
            "Stalls (audio under 80% of the clock in a 5 s window): \(stalls)",
            "Unexpected pauses: \(unexpectedPauses)",
            "Media events since start: waiting \(events(\.waiting)), stalled \(events(\.stalled))",
            "Track changes: \(trackChanges)",
            "Display sleeps: \(displaySleeps), Space changes (full screen): \(spaceChanges)",
            String(format: "Longest gap between samples: %.1f s", longestGap),
        ].joined(separator: "\n")
    }
}

/// S0.3: checks each core bridge source from the plan's contract on the live site.
/// Records presence, shapes and timings only; titles, artists and URLs are never written.
enum BridgeCheck {
    static let reportFile = Spike.logsFolder.appendingPathComponent("YTNotchSpike-bridge.json")

    /// Runs before the site's own scripts and keeps a reference to every Media Session action
    /// handler the site registers, plus its last position state.
    static let captureScript = """
    (() => {
      if (!window.MediaSession) return;
      // Patch the prototype, so calls made through it (or `.call`) are seen too.
      const proto = MediaSession.prototype;
      const handlers = window.__spikeHandlers = {};
      window.__spikeActionCalls = [];
      const setActionHandler = proto.setActionHandler;
      proto.setActionHandler = function (action, handler) {
        window.__spikeActionCalls.push(action + (handler ? '' : ':null'));
        if (handler) handlers[action] = handler; else delete handlers[action];
        return setActionHandler.call(this, action, handler);
      };
      proto.setActionHandler.__spike = true;
      if (proto.setPositionState) {
        const setPositionState = proto.setPositionState;
        window.__spikePositionCalls = 0;
        proto.setPositionState = function (state) {
          window.__spikePositionCalls++;
          window.__spikePosition = state ? { duration: state.duration, position: state.position, playbackRate: state.playbackRate } : null;
          return setPositionState.call(this, state);
        };
      }
    })();
    """

    /// The body of an async function: plays muted, seeks, pauses, then next and previous
    /// through the captured handlers, and leaves the player paused with its mute restored.
    static let checkScript = """
    const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
    const ms = navigator.mediaSession;
    const handlers = window.__spikeHandlers || {};
    const video = () => document.querySelector('video');
    const round = (n) => Math.round(n * 10) / 10;
    const key = () => (ms && ms.metadata) ? ms.metadata.title + '\\u0001' + ms.metadata.artist : '';
    const meta = () => {
      const m = ms && ms.metadata;
      if (!m) return null;
      return {
        title: !!m.title, artist: !!m.artist, album: !!m.album,
        artwork: (m.artwork || []).map((a) => {
          let host = 'invalid';
          try { host = new URL(a.src).host; } catch (e) {}
          return { sizes: a.sizes || '', type: a.type || '', host };
        }),
      };
    };
    const find = (selectors) => {
      for (const selector of selectors) { const el = document.querySelector(selector); if (el) return { el, selector }; }
      return null;
    };
    const playButtonSelectors = ['ytmusic-player-bar #play-pause-button', '#play-pause-button', '.play-pause-button'];
    const nextButtonSelectors = ['ytmusic-player-bar .next-button', '.next-button'];
    const previousButtonSelectors = ['ytmusic-player-bar .previous-button', '.previous-button'];
    const state = () => {
      const v = video();
      const found = find(playButtonSelectors);
      const button = found ? found.el : null;
      return {
        hasVideo: !!v,
        paused: v ? v.paused : null,
        position: v ? round(v.currentTime) : null,
        duration: v ? (isFinite(v.duration) ? round(v.duration) : String(v.duration)) : null,
        readyState: v ? v.readyState : null,
        playbackState: ms ? ms.playbackState : null,
        pageButton: button ? (button.getAttribute('title') || button.getAttribute('aria-label') || '') : null,
        positionState: window.__spikePosition || null,
        positionStateCalls: window.__spikePositionCalls || 0,
      };
    };
    const keepMuted = () => { const v = video(); if (v) v.muted = true; };
    const waitFor = async (test, timeout) => {
      const start = Date.now();
      while (Date.now() - start < timeout) {
        keepMuted();
        if (test()) return Date.now() - start;
        await sleep(200);
      }
      return -1;
    };

    const report = {
      capture: {
        wrapperInstalled: !!(window.MediaSession && MediaSession.prototype.setActionHandler.__spike),
        actionCalls: window.__spikeActionCalls || [],
      },
      handlers: Object.keys(handlers).sort(),
      buttons: {
        playPause: (find(playButtonSelectors) || {}).selector || null,
        next: (find(nextButtonSelectors) || {}).selector || null,
        previous: (find(previousButtonSelectors) || {}).selector || null,
      },
      metadata: meta(),
      initial: state(),
      steps: {},
    };

    // What the player bar's DOM looks like, to pick fallback selectors.
    const describe = (el) => el.tagName.toLowerCase() + (el.id ? '#' + el.id : '')
      + (typeof el.className === 'string' && el.className.trim() ? '.' + el.className.trim().split(/\\s+/).slice(0, 3).join('.') : '');
    const discover = (word) => [...document.querySelectorAll('[id*="' + word + '"], [class*="' + word + '"]')].slice(0, 8).map(describe);
    const discovery = () => {
      const bar = document.querySelector('ytmusic-player-bar');
      return {
        playerBar: !!bar,
        playerBarShadowRoot: !!(bar && bar.shadowRoot),
        playerBarButtons: bar ? [...bar.querySelectorAll('button, [role="button"], tp-yt-paper-icon-button, yt-icon-button')].slice(0, 20).map(describe) : [],
        next: discover('next-button'),
        previous: discover('previous-button'),
        playPause: discover('play-pause'),
      };
    };
    report.discovery = discovery();

    // The same search, also inside open shadow roots, with the chain of shadow hosts.
    const deepAll = (root, out) => {
      for (const el of root.querySelectorAll('*')) { out.push(el); if (el.shadowRoot) deepAll(el.shadowRoot, out); }
      return out;
    };
    const hostChain = (el) => {
      const chain = [];
      let node = el;
      while (node) {
        const root = node.getRootNode();
        if (!root || root === document || !root.host) break;
        chain.unshift(root.host.tagName.toLowerCase());
        node = root.host;
      }
      return chain.join(' > ');
    };
    const deepDiscovery = () => {
      const all = deepAll(document, []);
      const match = (word) => all
        .filter((el) => (el.id && el.id.includes(word)) || (typeof el.className === 'string' && el.className.includes(word)))
        .slice(0, 6).map((el) => (hostChain(el) || 'document') + ' :: ' + describe(el));
      return {
        elements: all.length,
        shadowHosts: all.filter((el) => el.shadowRoot).length,
        iframes: document.querySelectorAll('iframe').length,
        playerBarTags: all.filter((el) => el.tagName.toLowerCase().includes('player-bar')).slice(0, 5).map((el) => (hostChain(el) || 'document') + ' :: ' + describe(el)),
        next: match('next-button'),
        previous: match('previous-button'),
        playPause: match('play-pause'),
        ariaNext: all.filter((el) => /next/i.test(el.getAttribute('aria-label') || '')).slice(0, 4).map((el) => (hostChain(el) || 'document') + ' :: ' + describe(el) + ' [' + el.getAttribute('aria-label') + ']'),
      };
    };
    report.deepDiscovery = deepDiscovery();
    const first = video();
    if (!first) { report.error = 'no video element'; return JSON.stringify(report); }
    const wasMuted = first.muted;
    first.muted = true;
    try {
      let playError = null;
      const t0 = first.currentTime;
      try { await first.play(); } catch (e) { playError = String((e && e.name) || e); }
      await sleep(3000);
      report.steps.play = { error: playError, advanced: round(video().currentTime - t0), ...state() };

      const v = video();
      const target = Math.max(1, Math.min((isFinite(v.duration) ? v.duration : 60) - 15, v.currentTime + 30));
      v.currentTime = target;
      await sleep(1500);
      report.steps.seekViaVideo = { target: round(target), landed: round(video().currentTime), ok: Math.abs(video().currentTime - target) < 3, ...state() };

      if (handlers.seekto) {
        const target2 = Math.max(1, video().currentTime - 20);
        handlers.seekto({ action: 'seekto', seekTime: target2 });
        await sleep(1500);
        report.steps.seekViaHandler = { target: round(target2), landed: round(video().currentTime), ok: Math.abs(video().currentTime - target2) < 3 };
      }

      video().pause();
      await sleep(1200);
      report.steps.pauseViaVideo = state();

      if (handlers.play) {
        handlers.play({ action: 'play' });
        await sleep(2000);
        report.steps.playViaHandler = state();
      }
      if (handlers.pause) {
        handlers.pause({ action: 'pause' });
        await sleep(1200);
        report.steps.pauseViaHandler = state();
      }
      await video().play().catch(() => {});
      await sleep(1500);

      // Next and previous: the site's own Media Session handler if it registered one,
      // otherwise the page's player-bar button (the plan's selector fallback).
      const press = (action, selectors) => {
        if (handlers[action]) { handlers[action]({ action }); return 'handler'; }
        const button = find(selectors);
        if (button) { button.el.click(); return 'button ' + button.selector; }
        return 'none';
      };

      const before = key();
      const elementBefore = video();
      const nextVia = press('nexttrack', nextButtonSelectors);
      const nextMs = await waitFor(() => key() !== '' && key() !== before, 10000);
      await sleep(2000);
      report.steps.next = { via: nextVia, changedAfterMs: nextMs, sameVideoElement: video() === elementBefore, metadata: meta(), ...state() };

      const afterNext = key();
      const previousVia = press('previoustrack', previousButtonSelectors);
      const previousMs = await waitFor(() => key() !== '' && key() !== afterNext, 10000);
      await sleep(1500);
      report.steps.previous = { via: previousVia, changedAfterMs: previousMs, backToFirstTrack: key() === before, ...state() };
      // Fallback for next with no handler and no button: seek to the end and let the site
      // advance on its own.
      const beforeEnd = key();
      const ending = video();
      if (isFinite(ending.duration)) ending.currentTime = ending.duration - 0.5;
      await ending.play().catch(() => {});
      const endMs = await waitFor(() => key() !== '' && key() !== beforeEnd, 10000);
      await sleep(1000);
      report.steps.nextViaSeekToEnd = { changedAfterMs: endMs, ...state() };

      report.discoveryAfterPlay = discovery();
      report.handlersAtEnd = Object.keys(handlers).sort();
      report.capture.actionCallsAtEnd = window.__spikeActionCalls || [];
    } finally {
      const v = video();
      if (v) v.pause();
      await sleep(800);
      const last = video();
      if (last) last.muted = wasMuted;
      report.final = state();
    }
    return JSON.stringify(report);
    """
}

/// S0.4: checks the page sources for the Playlists and Up next views and for shuffle and
/// repeat. Records counts, structure, ID patterns and button labels; never titles or IDs.
enum LibraryCheck {
    static let reportFile = Spike.logsFolder.appendingPathComponent("YTNotchSpike-library.json")

    /// Check mode only: every media element stays truly muted, whatever the page sets. The
    /// page still reads back the value it last set, so its own volume settings never change.
    static let muteScript = """
    (() => {
      const muted = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'muted');
      Object.defineProperty(HTMLMediaElement.prototype, 'muted', {
        configurable: true,
        get() { return this.__spikePageMuted || false; },
        set(value) { this.__spikePageMuted = !!value; muted.set.call(this, true); },
      });
      const play = HTMLMediaElement.prototype.play;
      HTMLMediaElement.prototype.play = function () { muted.set.call(this, true); return play.apply(this, arguments); };
      document.addEventListener('playing', (e) => { if (e.target instanceof HTMLMediaElement) muted.set.call(e.target, true); }, true);
      document.addEventListener('loadstart', (e) => { if (e.target instanceof HTMLMediaElement) muted.set.call(e.target, true); }, true);
      window.__spikeReallyMuted = (el) => muted.get.call(el);
    })();
    """

    static let helpers = """
    const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
    const describe = (el) => el.tagName.toLowerCase() + (el.id ? '#' + el.id : '')
      + (typeof el.className === 'string' && el.className.trim() ? '.' + el.className.trim().split(/\\s+/).slice(0, 3).join('.') : '');
    const hash = (text) => { let h = 0; for (const c of text) h = (h * 31 + c.charCodeAt(0)) | 0; return h; };
    const listId = (href) => { try { return new URL(href, location.href).searchParams.get('list'); } catch (e) { return null; } };
    const idKind = (id) => id === 'LM' ? 'LM' : id.slice(0, 2);
    """

    /// Run on the home page: the playlist list in the sidebar.
    static let sidebarScript = helpers + """
    const links = [...document.querySelectorAll('a[href*="list="]')];
    const guide = document.querySelector('ytmusic-guide-renderer') || document.querySelector('[id*="guide"]');
    const inGuide = guide ? links.filter((a) => guide.contains(a)) : [];
    const entries = [...document.querySelectorAll('ytmusic-guide-entry-renderer')];
    // Guide entries are not links; each element carries its renderer data as a property.
    const dataOf = (e) => e.data || e.__data || null;
    const browseIdOf = (e) => {
      const d = dataOf(e);
      const endpoint = d && d.navigationEndpoint;
      return (endpoint && endpoint.browseEndpoint && endpoint.browseEndpoint.browseId) || null;
    };
    const browseIds = entries.map(browseIdOf);
    const ids = [...new Set(browseIds.filter((id) => id && id.startsWith('VL')).map((id) => id.slice(2)))];
    const sampleData = entries.map(dataOf).find((d) => d && d.navigationEndpoint);
    const entryLinks = entries.map((e) => e.querySelector('a[href*="list="]')).filter(Boolean);
    const report = {
      entriesWithData: entries.filter((e) => dataOf(e)).length,
      dataKeys: sampleData ? Object.keys(sampleData).slice(0, 20) : null,
      endpointKeys: sampleData ? Object.keys(sampleData.navigationEndpoint) : null,
      browseIdKinds: browseIds.map((id) => id ? id.slice(0, 4) : null),
      entriesWithThumbnailData: entries.filter((e) => { const d = dataOf(e); return d && (d.thumbnail || d.thumbnailRenderer); }).length,
      guide: guide ? describe(guide) : null,
      guideEntries: entries.length,
      linksWithList: links.length,
      linksInGuide: inGuide.length,
      uniquePlaylists: ids.length,
      firstIsLikedMusic: ids[0] === 'LM',
      idKinds: ids.map(idKind),
      entriesWithLink: entryLinks.length,
      entriesWithText: entries.filter((e) => (e.textContent || '').trim().length > 0).length,
      entriesWithImage: entries.filter((e) => e.querySelector('img')).length,
      sampleEntry: entries.length ? [describe(entries[entries.length - 1]), ...[...entries[entries.length - 1].querySelectorAll('*')].slice(0, 8).map(describe)] : [],
    };

    // Thumbnails: the sidebar has none, so try the Library page, reached through the
    // site's own navigation (a click on the Library entry) so playback is not interrupted.
    const libraryEntry = entries.find((e) => browseIdOf(e) === 'FEmusic_library_landing');
    if (libraryEntry) {
      (libraryEntry.querySelector('tp-yt-paper-item') || libraryEntry).click();
      await sleep(5000);
      const cards = [...document.querySelectorAll('ytmusic-two-row-item-renderer, ytmusic-responsive-list-item-renderer')];
      const cardId = (c) => {
        const d = c.data || c.__data;
        const runs = d && d.title && d.title.runs;
        const endpoint = d && (d.navigationEndpoint || (runs && runs[0] && runs[0].navigationEndpoint));
        const browseId = endpoint && endpoint.browseEndpoint && endpoint.browseEndpoint.browseId;
        if (browseId && browseId.startsWith('VL')) return browseId.slice(2);
        const a = c.querySelector('a[href*="list="]');
        return a ? listId(a.href) : null;
      };
      const withImage = new Set();
      for (const c of cards) {
        const id = cardId(c);
        const img = c.querySelector('img');
        if (id && img && img.src && !img.src.startsWith('data:')) withImage.add(id);
      }
      report.library = {
        path: location.pathname,
        cards: cards.length,
        playlistCardsWithImage: withImage.size,
        sidebarPlaylistsWithThumbnail: ids.filter((id) => withImage.has(id)).length,
      };
    }
    return JSON.stringify({ report, chosen: ids.includes('LM') ? 'LM' : (ids[0] || null) });
    """

    /// Run on the watch page after starting a playlist by its address.
    static let playerScript = helpers + """
    const video = () => document.querySelector('video');
    const key = () => (navigator.mediaSession && navigator.mediaSession.metadata) ? hash(navigator.mediaSession.metadata.title + '|' + navigator.mediaSession.metadata.artist) : 0;
    const waitFor = async (test, timeout) => {
      const start = Date.now();
      while (Date.now() - start < timeout) { if (test()) return Date.now() - start; await sleep(200); }
      return -1;
    };
    const report = {};
    const v = video();
    report.start = {
      path: location.pathname,
      hasListParam: new URL(location.href).searchParams.has('list'),
      hasVideo: !!v,
      playing: v ? !v.paused : null,
      reallyMuted: v && window.__spikeReallyMuted ? window.__spikeReallyMuted(v) : null,
      playbackState: navigator.mediaSession ? navigator.mediaSession.playbackState : null,
    };
    if (v && v.paused) { await v.play().catch(() => {}); await sleep(2000); report.start.playingAfterPlay = !video().paused; }

    const bar = document.querySelector('ytmusic-player-bar');
    const label = (el) => el ? (el.getAttribute('aria-label') || el.getAttribute('title') || '') : null;
    // Find controls by their accessible labels, wherever they live.
    const all = [...document.querySelectorAll('*')];
    const labelled = (re) => all.filter((el) => re.test(el.getAttribute('aria-label') || '') || re.test(el.getAttribute('title') || ''));
    const show = (els) => els.slice(0, 6).map((el) => describe(el) + ' [' + label(el) + '] in ' + (el.parentElement ? describe(el.parentElement) : '-'));
    report.controls = {
      playerBarTag: !!bar,
      playerTags: [...new Set(all.map((e) => e.tagName.toLowerCase()).filter((t) => t.includes('player')))],
      shuffle: show(labelled(/shuffle/i)),
      repeat: show(labelled(/repeat/i)),
      next: show(labelled(/^next/i)),
      playPause: show(labelled(/^(play|pause)$/i)),
    };

    const queueItems = () => [...document.querySelectorAll('ytmusic-player-queue-item')];
    const current = (items) => items.findIndex((i) => i.getAttribute('play-button-state') === 'playing');
    const indices = (items, test) => items.map((i, n) => test(i) ? n : -1).filter((n) => n >= 0).slice(0, 6);
    const order = () => hash(queueItems().map((i) => (i.textContent || '').trim()).join('|'));
    const items = queueItems();
    report.queue = {
      items: items.length,
      sample: items[0] ? describe(items[0]) : null,
      attributes: items[0] ? [...new Set(items.flatMap((i) => [...i.attributes].map((a) => a.name)))] : [],
      selectedCount: items.filter((i) => i.hasAttribute('selected')).length,
      selectedIndices: indices(items, (i) => i.hasAttribute('selected')),
      playingIndices: indices(items, (i) => i.getAttribute('play-button-state') === 'playing'),
      automixIndicesFirst: indices(items, (i) => i.hasAttribute('is-automix')),
      automixCount: items.filter((i) => i.hasAttribute('is-automix')).length,
      wrappers: [...new Set(items.map((i) => i.parentElement ? describe(i.parentElement) : '-'))].slice(0, 4),
      currentIndex: current(items),
      playButtonStates: [...new Set(items.map((i) => i.getAttribute('play-button-state')).filter(Boolean))],
      withTitle: items.filter((i) => i.querySelector('.song-title')).length,
      withArtist: items.filter((i) => i.querySelector('.byline')).length,
      withThumbnail: items.filter((i) => i.querySelector('img')).length,
      withDuration: items.filter((i) => i.querySelector('.duration')).length,
    };

    const firstLabelled = (re) => { const el = labelled(re)[0]; return el ? { el, selector: describe(el) } : null; };
    const repeat = firstLabelled(/repeat/i);
    const shuffle = firstLabelled(/shuffle/i);
    report.modes = {
      repeatSelector: repeat ? repeat.selector : null,
      shuffleSelector: shuffle ? shuffle.selector : null,
      repeatInitial: repeat ? label(repeat.el) : null,
      shuffleInitial: shuffle ? label(shuffle.el) : null,
      shuffleAriaPressed: shuffle ? shuffle.el.getAttribute('aria-pressed') : null,
      barRepeatAttribute: bar ? bar.getAttribute('repeat-mode') : null,
    };
    if (repeat) {
      const cycle = [label(repeat.el) + ' / ' + (bar ? bar.getAttribute('repeat-mode') : '')];
      for (let i = 0; i < 3; i++) {
        repeat.el.click();
        await sleep(700);
        cycle.push(label(repeat.el) + ' / ' + (bar ? bar.getAttribute('repeat-mode') : ''));
      }
      report.modes.repeatCycle = cycle;
      report.modes.repeatRestored = cycle[cycle.length - 1] === cycle[0];
    }
    if (shuffle) {
      // Toggle shuffle twice, then make sure it ends off.
      const pressed = () => shuffle.el.getAttribute('aria-pressed');
      const before = order();
      const currentBefore = key();
      shuffle.el.click();
      await sleep(2000);
      const mid = order();
      report.modes.afterFirstClick = { pressed: pressed(), queueOrderChanged: mid !== before, currentTrackKept: key() === currentBefore };
      shuffle.el.click();
      await sleep(2000);
      report.modes.afterSecondClick = { pressed: pressed(), queueOrderChanged: order() !== mid, backToFirstOrder: order() === before, currentTrackKept: key() === currentBefore };
      if (pressed() !== 'false') { shuffle.el.click(); await sleep(1500); }
      report.modes.shuffleFinalPressed = pressed();
      report.modes.queueItemsAfter = queueItems().length;
    }

    const afterShuffle = queueItems();
    const targetIndex = Math.min(3, afterShuffle.length - 1);
    if (targetIndex > 0) {
      const target = afterShuffle[targetIndex];
      const before = key();
      const clickTarget = target.querySelector('ytmusic-play-button-renderer') || target.querySelector('.song-title') || target;
      clickTarget.click();
      const ms = await waitFor(() => key() !== 0 && key() !== before, 8000);
      await sleep(1000);
      report.queueJump = {
        targetIndex,
        clicked: describe(clickTarget),
        changedAfterMs: ms,
        newCurrentIndex: current(queueItems()),
        playing: video() ? !video().paused : null,
      };
    }

    const last = video();
    if (last) { last.pause(); await sleep(500); }
    report.final = {
      paused: last ? last.paused : null,
      reallyMuted: last && window.__spikeReallyMuted ? window.__spikeReallyMuted(last) : null,
      pageSeesMuted: last ? last.muted : null,
      repeat: repeat ? label(repeat.el) : null,
    };
    return JSON.stringify(report);
    """
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, NSMenuDelegate {
    private var window: HostWindow!
    private var webView: WKWebView!
    private var monitor: PlaybackMonitor?
    private var statusItem: NSStatusItem?
    private var visibleFrame: NSRect?
    private var isCheckingOnly = false
    private var bridgeCheckPending = CommandLine.arguments.contains("--check-bridge")

    private enum LibraryStep { case off, waitingForHome, waitingForWatch, running }
    private var libraryStep: LibraryStep = CommandLine.arguments.contains("--check-library") ? .waitingForHome : .off
    private var sidebarReport: Any = NSNull()

    private var isPlayerHidden: Bool { visibleFrame != nil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `--check-sign-in`: print the cookie report and quit, without showing a window.
        // WebKit only loads saved cookies once a web view uses the store, so load a blank
        // page in a hidden web view first and report when it finishes.
        if CommandLine.arguments.contains("--check-sign-in") {
            NSApp.setActivationPolicy(.prohibited)
            isCheckingOnly = true
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .default()
            webView = WKWebView(frame: .zero, configuration: configuration)
            webView.navigationDelegate = self
            webView.loadHTMLString("", baseURL: URL(string: "https://music.youtube.com"))
            return
        }

        buildMenu()
        buildStatusItem()

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.inactiveSchedulingPolicy = Spike.schedulingPolicy
        configuration.userContentController.addUserScript(
            WKUserScript(source: PlaybackMonitor.statsScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        configuration.userContentController.addUserScript(
            WKUserScript(source: BridgeCheck.captureScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        if libraryStep != .off {
            configuration.userContentController.addUserScript(
                WKUserScript(source: LibraryCheck.muteScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            )
        }

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = Spike.safariUserAgent
        webView.isInspectable = true
        webView.navigationDelegate = self
        webView.uiDelegate = self

        window = HostWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "YT Notch spike"
        window.contentView = webView
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let policy = Spike.name(of: Spike.schedulingPolicy)
        Spike.log("launched, policy \(policy), user agent: \(Spike.safariUserAgent)")
        webView.load(URLRequest(url: Spike.startURL))

        let monitor = PlaybackMonitor(webView: webView, policy: policy)
        monitor.start()
        self.monitor = monitor

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.monitor?.isDisplayAsleep = true
            self?.monitor?.note("display-sleep")
        }
        workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.monitor?.isDisplayAsleep = false
            self?.monitor?.note("display-wake")
        }
        workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.monitor?.note("space-change")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor { Spike.log("summary | " + monitor.summary.replacingOccurrences(of: "\n", with: " | ")) }
    }

    // MARK: Hiding the player

    /// Moves the host window far off-screen (still ordered in) and turns the app into a
    /// menu bar app, as the real app will be.
    private func hidePlayer() {
        guard !isPlayerHidden else { return }
        visibleFrame = window.frame
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        NSApp.setActivationPolicy(.accessory)
        monitor?.isHidden = true
        monitor?.note("hidden")
    }

    private func showPlayer() {
        guard let frame = visibleFrame else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        visibleFrame = nil
        NSApp.setActivationPolicy(.regular)
        window.setFrame(frame, display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        monitor?.isHidden = false
        monitor?.note("shown")
    }

    @objc private func togglePlayerWindow(_ sender: Any?) {
        isPlayerHidden ? showPlayer() : hidePlayer()
    }

    @objc private func playPause(_ sender: Any?) {
        monitor?.userToggledAt = Date()
        webView.evaluateJavaScript("(() => { const v = document.querySelector('video'); if (!v) return 'none'; if (v.paused) { v.play(); return 'play'; } v.pause(); return 'pause'; })()") { result, _ in
            Spike.log("user play/pause: \(result as? String ?? "?")")
        }
    }

    @objc private func showSummary(_ sender: Any?) {
        guard let monitor else { return }
        Spike.log("summary | " + monitor.summary.replacingOccurrences(of: "\n", with: " | "))
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Playback summary"
        alert.informativeText = monitor.summary
        alert.runModal()
    }

    // MARK: Menus

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "YT Notch spike")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu == statusItem?.menu else { return }
        menu.removeAllItems()
        menu.addItem(withTitle: isPlayerHidden ? "Show Player Window" : "Hide Player Window", action: #selector(togglePlayerWindow(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Play or Pause", action: #selector(playPause(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Playback Summary…", action: #selector(showSummary(_:)), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit YT Notch spike", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
    }

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit YT Notch spike", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        mainMenu.addItem(submenu: appMenu, title: "YT Notch spike")

        // Without an Edit menu, paste does not work in Google's sign-in fields.
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        mainMenu.addItem(submenu: editMenu, title: "Edit")

        let spikeMenu = NSMenu(title: "Spike")
        spikeMenu.addItem(withTitle: "Check Sign-in", action: #selector(checkSignIn(_:)), keyEquivalent: "i").target = self
        spikeMenu.addItem(withTitle: "Reload", action: #selector(reload(_:)), keyEquivalent: "r").target = self
        spikeMenu.addItem(withTitle: "Go to YouTube Music", action: #selector(goHome(_:)), keyEquivalent: "h").target = self
        spikeMenu.addItem(.separator())
        spikeMenu.addItem(withTitle: "Hide Player Window", action: #selector(togglePlayerWindow(_:)), keyEquivalent: "H").target = self
        spikeMenu.addItem(withTitle: "Playback Summary…", action: #selector(showSummary(_:)), keyEquivalent: "").target = self
        spikeMenu.addItem(withTitle: "Check Bridge Sources", action: #selector(checkBridgeSources(_:)), keyEquivalent: "b").target = self
        spikeMenu.addItem(.separator())
        spikeMenu.addItem(withTitle: "Delete Website Data…", action: #selector(deleteWebsiteData(_:)), keyEquivalent: "").target = self
        mainMenu.addItem(submenu: spikeMenu, title: "Spike")

        NSApp.mainMenu = mainMenu
    }

    @objc private func checkSignIn(_ sender: Any?) {
        Task { @MainActor in
            let report = await Spike.signInReport()
            Spike.log(report.text.replacingOccurrences(of: "\n", with: " | "))
            let alert = NSAlert()
            alert.messageText = report.signedIn ? "Signed in" : "Not signed in"
            alert.informativeText = report.text
            alert.beginSheetModal(for: window, completionHandler: nil)
        }
    }

    @objc private func reload(_ sender: Any?) { webView.reload() }

    @objc private func goHome(_ sender: Any?) { webView.load(URLRequest(url: Spike.startURL)) }

    @objc private func deleteWebsiteData(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Delete this spike's website data?"
        alert.informativeText = "Signs the spike out by removing its cookies and storage. Safari and other apps are not affected."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let store = WKWebsiteDataStore.default()
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
                Spike.log("website data deleted")
                self.goHome(nil)
            }
        }
    }

    // MARK: Web view

    // Pages that open a new window (target=_blank, window.open) load in this one instead.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if isCheckingOnly {
            Task { @MainActor in
                let report = await Spike.signInReport()
                print(report.text)
                exit(report.signedIn ? 0 : 1)
            }
            return
        }
        let host = webView.url?.host ?? "?"
        window.title = "YT Notch spike · \(host)"
        Spike.log("loaded \(host)\(webView.url?.path ?? "")")

        if libraryStep != .off, host == "music.youtube.com" {
            advanceLibraryCheck(path: webView.url?.path ?? "")
        }

        // `--check-bridge`: once the player has had time to start up, run the check and quit.
        if bridgeCheckPending, host == "music.youtube.com" {
            bridgeCheckPending = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.runBridgeCheck { NSApp.terminate(nil) }
            }
        }
    }

    /// `--check-library`: read the sidebar on the home page, start the chosen playlist by its
    /// address, then check the queue, shuffle and repeat on the watch page, write the report
    /// and quit.
    private func advanceLibraryCheck(path: String) {
        switch (libraryStep, path) {
        case (.waitingForHome, "/"):
            libraryStep = .running
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                guard let self else { return }
                Spike.log("library check: reading the sidebar")
                self.webView.callAsyncJavaScript(LibraryCheck.sidebarScript, arguments: [:], in: nil, in: .page) { result in
                    let object = Self.jsonObject(result)
                    let dict = object as? [String: Any]
                    self.sidebarReport = dict?["report"] ?? object
                    guard let chosen = dict?["chosen"] as? String,
                          var components = URLComponents(string: "https://music.youtube.com/watch") else {
                        self.finishLibraryCheck(player: ["error": "no playlist in the sidebar"])
                        return
                    }
                    components.queryItems = [URLQueryItem(name: "list", value: chosen)]
                    self.libraryStep = .waitingForWatch
                    Spike.log("library check: starting a playlist by its address")
                    self.webView.load(URLRequest(url: components.url!))
                }
            }
        case (.waitingForWatch, "/watch"):
            libraryStep = .running
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                guard let self else { return }
                Spike.log("library check: checking queue, shuffle and repeat")
                self.webView.callAsyncJavaScript(LibraryCheck.playerScript, arguments: [:], in: nil, in: .page) { result in
                    self.finishLibraryCheck(player: Self.jsonObject(result))
                }
            }
        default:
            break
        }
    }

    private func finishLibraryCheck(player: Any) {
        let report: [String: Any] = ["sidebar": sidebarReport, "player": player]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: LibraryCheck.reportFile)
        }
        Spike.log("library check finished, wrote \(LibraryCheck.reportFile.path)")
        NSApp.terminate(nil)
    }

    private static func jsonObject(_ result: Result<Any, Error>) -> Any {
        switch result {
        case .success(let value):
            if let text = value as? String, let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) {
                return object
            }
            return ["raw": "\(value)"]
        case .failure(let error):
            return ["error": error.localizedDescription]
        }
    }

    @objc private func checkBridgeSources(_ sender: Any?) {
        runBridgeCheck {}
    }

    private func runBridgeCheck(then done: @escaping () -> Void) {
        Spike.log("bridge check started")
        webView.callAsyncJavaScript(BridgeCheck.checkScript, arguments: [:], in: nil, in: .page) { result in
            let text: String
            switch result {
            case .success(let value): text = value as? String ?? "\(value)"
            case .failure(let error): text = "{\"error\": \"\(error.localizedDescription)\"}"
            }
            try? Data(text.utf8).write(to: BridgeCheck.reportFile)
            Spike.log("bridge check finished, wrote \(BridgeCheck.reportFile.path)")
            done()
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Spike.log("navigation failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Spike.log("load failed: \(error.localizedDescription)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        monitor?.note("web-content-terminated")
        webView.reload()
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
