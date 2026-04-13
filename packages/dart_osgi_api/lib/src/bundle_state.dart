/// OSGi bundle lifecycle states.
///
/// Transitions: INSTALLED → RESOLVED → STARTING → ACTIVE → STOPPING → UNINSTALLED
enum BundleState {
  installed,
  resolved,
  starting,
  active,
  stopping,
  uninstalled,
}
