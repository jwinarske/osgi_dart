// Phase 5: VsyncCoordinator — single frame callback driving all bundle engines.

#ifndef IVI_HOMESCREEN_OSGI_VSYNC_COORDINATOR_H_
#define IVI_HOMESCREEN_OSGI_VSYNC_COORDINATOR_H_

#include <cstdint>
#include <string>

namespace ivi_homescreen_osgi {

/// Coordinates vsync across all active Flutter bundle engines.
///
/// A single Wayland frame callback drives all bundle engines atomically.
/// This prevents surface tearing across bundles — one wl_surface.commit
/// per display cycle.
///
/// The coordinator batches FlutterEngineOnVsync calls so all engines
/// render at the same time, then commits all surfaces together.
class VsyncCoordinator {
 public:
  virtual ~VsyncCoordinator() = default;

  /// Register a bundle engine to receive vsync callbacks.
  ///
  /// @param symbolic_name Bundle identifier.
  /// @param engine Opaque engine handle (FlutterEngine).
  virtual void RegisterEngine(const std::string& symbolic_name,
                              void* engine) = 0;

  /// Unregister a bundle engine from vsync callbacks.
  virtual void UnregisterEngine(const std::string& symbolic_name) = 0;

  /// Called by the Wayland frame callback. Dispatches vsync to all
  /// registered engines and batches wl_surface.commit.
  ///
  /// @param frame_time_nanos Timestamp from the compositor.
  virtual void OnVsync(int64_t frame_time_nanos) = 0;

  /// Set the target frame interval in nanoseconds.
  /// Default: 16666666 (60 Hz).
  virtual void SetFrameInterval(int64_t interval_nanos) = 0;
};

}  // namespace ivi_homescreen_osgi

#endif  // IVI_HOMESCREEN_OSGI_VSYNC_COORDINATOR_H_
