import PlayerCore

/// Control Center and media keys.
///
/// The plan had SystemMedia mirror the store to Now Playing and route media keys and
/// headphone buttons back to the store (I4.2). WebKit already does both for the app's one
/// web view, as Safari does for a page: its media process registers YT Notch as a Now
/// Playing app with the site's own title, artist and artwork, and sends play, pause, next and
/// previous to the site, whose changes reach the store through the bridge like any other.
/// Publishing Now Playing here as well would show a second YT Notch player and split the
/// keys between the two, so this module stays empty (see `docs/decisions.md`).
///
/// Rule: imports PlayerCore and never the other modules. Public Apple frameworks only.
public enum SystemMedia {}
