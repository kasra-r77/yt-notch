import PlayerCore

/// Control Center and media keys.
///
/// SystemMedia mirrors the store to Now Playing and routes media keys and headphone buttons
/// back to the store, using Apple's MediaPlayer framework (I4.2).
///
/// Rule: imports PlayerCore and never the other modules. Public Apple frameworks only.
public enum SystemMedia {}
