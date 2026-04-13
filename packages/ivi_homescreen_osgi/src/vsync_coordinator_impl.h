// Phase 7: Concrete VsyncCoordinator implementation.

#ifndef IVI_HOMESCREEN_OSGI_VSYNC_COORDINATOR_IMPL_H_
#define IVI_HOMESCREEN_OSGI_VSYNC_COORDINATOR_IMPL_H_

#include <cstdint>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include "ivi_homescreen_osgi/vsync_coordinator.h"

namespace ivi_homescreen_osgi {

/// Tracks a registered engine for vsync dispatch.
struct VsyncEntry {
  std::string symbolic_name;
  void* engine = nullptr;  // Opaque FlutterEngine handle.
};

/// Concrete [VsyncCoordinator] that drives all active Flutter bundle
/// engines from a single Wayland frame callback.
///
/// On each vsync:
/// 1. Calls FlutterEngineOnVsync for every registered engine.
/// 2. Batches wl_surface.commit to prevent cross-bundle tearing.
class VsyncCoordinatorImpl : public VsyncCoordinator {
 public:
  VsyncCoordinatorImpl();
  ~VsyncCoordinatorImpl() override;

  // VsyncCoordinator interface
  void RegisterEngine(const std::string& symbolic_name, void* engine) override;
  void UnregisterEngine(const std::string& symbolic_name) override;
  void OnVsync(int64_t frame_time_nanos) override;
  void SetFrameInterval(int64_t interval_nanos) override;

  /// Number of currently registered engines.
  [[nodiscard]] size_t EngineCount() const;

 private:
  mutable std::mutex mutex_;
  std::unordered_map<std::string, VsyncEntry> engines_;
  int64_t frame_interval_nanos_ = 16666666;  // 60 Hz default
};

}  // namespace ivi_homescreen_osgi

#endif  // IVI_HOMESCREEN_OSGI_VSYNC_COORDINATOR_IMPL_H_
