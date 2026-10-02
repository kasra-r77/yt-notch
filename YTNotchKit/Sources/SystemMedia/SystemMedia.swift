import PlayerCore

/// Control Center and media keys, deliberately empty: WebKit already registers the app's web
/// view as a Now Playing app and sends media keys to the site, as Safari does. Publishing Now
/// Playing here too would show a second YT Notch player and split the keys between the two.
public enum SystemMedia {}
