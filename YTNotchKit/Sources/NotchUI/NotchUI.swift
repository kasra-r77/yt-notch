import PlayerCore

/// The notch windows on every chosen display, collapsed and expanded.
///
/// NotchUI reads the store and calls its methods. Shapes, sizes and timings follow
/// `docs/design/notch-shapes.md` (N2.1 to N2.7).
///
/// Rule: imports PlayerCore and never the other modules. Never imports WebKit or knows the
/// site exists.
public enum NotchUI {}
