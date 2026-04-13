// Phase 7: Concrete BundleEngineManager implementation.

#ifndef IVI_HOMESCREEN_OSGI_BUNDLE_ENGINE_MANAGER_IMPL_H_
#define IVI_HOMESCREEN_OSGI_BUNDLE_ENGINE_MANAGER_IMPL_H_

#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>

#include "ivi_homescreen_osgi/bundle_engine_manager.h"
#include "ivi_homescreen_osgi/bundle_manifest.h"
#include "ivi_homescreen_osgi/comp_surf_lifecycle.h"
#include "ivi_homescreen_osgi/vsync_coordinator.h"

// Forward declarations for Flutter embedder API types.
// These are provided by flutter_engine.h in the ivi-homescreen build.
// NOLINTNEXTLINE(bugprone-reserved-identifier)
using FlutterEngine = struct FlutterEngineTag*;

namespace ivi_homescreen_osgi {

/// Tracks one running bundle engine.
struct EngineEntry {
  FlutterEngine engine = nullptr;
  BundleManifest manifest;
  int32_t surface_id = -1;
  bool active = false;
};

/// Concrete [BundleEngineManager] that spawns and destroys FlutterEngine
/// instances for each bundle.
///
/// Coordinates with [VsyncCoordinator] for frame timing and
/// [CompSurfLifecycle] for surface visibility management.
class BundleEngineManagerImpl : public BundleEngineManager {
 public:
  /// @param vsync        Shared vsync coordinator (owned externally).
  /// @param comp_surf    Shared compositor surface lifecycle (owned
  /// externally).
  BundleEngineManagerImpl(VsyncCoordinator* vsync,
                          CompSurfLifecycle* comp_surf);
  ~BundleEngineManagerImpl() override;

  // BundleEngineManager interface
  void SpawnBundleEngine(const BundleManifest& manifest) override;
  void DestroyBundleEngine(const std::string& symbolic_name) override;
  void SetFrameworkPort(int64_t framework_port) override;
  [[nodiscard]] size_t ActiveEngineCount() const override;

  /// Access an engine entry by symbolic name (for bridge plugin use).
  [[nodiscard]] const EngineEntry* GetEntry(
      const std::string& symbolic_name) const;

 private:
  /// Initialize a FlutterEngine for the given manifest.
  /// Returns nullptr on failure.
  FlutterEngine InitializeEngine(const BundleManifest& manifest);

  /// Shut down and clean up a single engine.
  void ShutdownEngine(EngineEntry& entry);

  VsyncCoordinator* vsync_;
  CompSurfLifecycle* comp_surf_;
  int64_t framework_port_ = 0;

  mutable std::mutex mutex_;
  std::unordered_map<std::string, std::unique_ptr<EngineEntry>> engines_;
};

}  // namespace ivi_homescreen_osgi

#endif  // IVI_HOMESCREEN_OSGI_BUNDLE_ENGINE_MANAGER_IMPL_H_
