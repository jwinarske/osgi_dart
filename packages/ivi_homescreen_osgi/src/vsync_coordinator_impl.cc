// Phase 7: VsyncCoordinator implementation.

#include "vsync_coordinator_impl.h"

// Flutter embedder API — provided by the ivi-homescreen build.
// #include <flutter_embedder.h>

namespace ivi_homescreen_osgi {

VsyncCoordinatorImpl::VsyncCoordinatorImpl() = default;
VsyncCoordinatorImpl::~VsyncCoordinatorImpl() = default;

void VsyncCoordinatorImpl::RegisterEngine(const std::string& symbolic_name,
                                          void* engine) {
  std::lock_guard<std::mutex> lock(mutex_);
  engines_[symbolic_name] = VsyncEntry{symbolic_name, engine};
}

void VsyncCoordinatorImpl::UnregisterEngine(const std::string& symbolic_name) {
  std::lock_guard<std::mutex> lock(mutex_);
  engines_.erase(symbolic_name);
}

void VsyncCoordinatorImpl::OnVsync(int64_t frame_time_nanos) {
  std::lock_guard<std::mutex> lock(mutex_);

  // Notify all registered engines of the vsync event.
  //
  // In the actual build with flutter_embedder.h:
  //
  //   for (auto& [name, entry] : engines_) {
  //     FlutterEngineOnVsync(
  //         entry.engine,
  //         baton,  // from the vsync callback
  //         frame_time_nanos,
  //         frame_time_nanos + frame_interval_nanos_);
  //   }
  //
  // After all engines have rendered, batch wl_surface.commit:
  //
  //   for (auto& [name, entry] : engines_) {
  //     wl_surface_commit(entry.surface);
  //   }
  //
  (void)frame_time_nanos;
}

void VsyncCoordinatorImpl::SetFrameInterval(int64_t interval_nanos) {
  frame_interval_nanos_ = interval_nanos;
}

size_t VsyncCoordinatorImpl::EngineCount() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return engines_.size();
}

}  // namespace ivi_homescreen_osgi
