import Foundation
import Observation

/// The shared player state and the only place it is written.
///
/// PlayerCore holds the current track, the playlist list and the queue, turns user intents
/// into commands, and decides health (ok, signed out, bridge broken). It defines the
/// `PlayerEngine` protocol that WebPlayer implements and FakeEngine fakes (F1.3).
///
/// Rule: imports only Foundation and Observation. No view or web code.
public enum PlayerCore {}
