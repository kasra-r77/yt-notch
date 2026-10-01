import PlayerCore

/// The single web view for the app's lifetime.
///
/// WebPlayer owns the hidden web view, injects `bridge.js`, passes messages both ways and
/// keeps the login. It implements `PlayerEngine` for the real site (W3.1).
///
/// Rule: imports PlayerCore and never the other modules. The only module that imports
/// WebKit. It does not parse the page itself; that is the bridge's job.
public enum WebPlayer {}
