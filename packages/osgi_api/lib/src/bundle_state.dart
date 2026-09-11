/// The OSGi bundle lifecycle, mirrored from the shell.
///
/// Values match the OSGi core specification's `Bundle` constants, which is also
/// what `shell/osgi/bundle_state.h` uses — so a state crosses the boundary as
/// an int with no translation table on either side.
library;

enum BundleState {
  uninstalled(0x01),
  installed(0x02),
  resolved(0x04),
  starting(0x08),
  stopping(0x10),
  active(0x20);

  const BundleState(this.value);

  /// The OSGi spec constant. Stable across the wire.
  final int value;

  static BundleState fromValue(int value) => switch (value) {
    0x01 => BundleState.uninstalled,
    0x02 => BundleState.installed,
    0x04 => BundleState.resolved,
    0x08 => BundleState.starting,
    0x10 => BundleState.stopping,
    0x20 => BundleState.active,
    _ => throw ArgumentError.value(value, 'value', 'not a BundleState'),
  };

  /// Running, or on the way to running. The shell holds bridge and vsync
  /// registrations across exactly this.
  bool get isLive => this == BundleState.starting || this == BundleState.active;

  bool get isTerminal => this == BundleState.uninstalled;
}

/// Whether `from -> to` is a legal lifecycle edge.
///
/// The graph is the OSGi one, not a linear chain, and matches
/// `ihs::osgi::IsLegalTransition` in the shell. Two edges carry the weight:
///
///   * `stopping -> resolved`, not on to `uninstalled`. This is what makes
///     restart a normal operation rather than a teardown.
///   * `starting -> stopping`, so a failed start unwinds the same way a healthy
///     stop does — an activator that throws and a bundle that misses its
///     deadline are one path, not two.
///
/// A self-transition is not an edge: a caller re-asserting the current state has
/// lost track of the bundle, and accepting it would hide that.
bool isLegalTransition(BundleState from, BundleState to) {
  if (from == to) return false;
  return switch (from) {
    BundleState.installed =>
      to == BundleState.resolved || to == BundleState.uninstalled,
    BundleState.resolved =>
      to == BundleState.starting ||
          to == BundleState.installed ||
          to == BundleState.uninstalled,
    BundleState.starting =>
      to == BundleState.active || to == BundleState.stopping,
    BundleState.active => to == BundleState.stopping,
    BundleState.stopping => to == BundleState.resolved,
    BundleState.uninstalled => false,
  };
}
