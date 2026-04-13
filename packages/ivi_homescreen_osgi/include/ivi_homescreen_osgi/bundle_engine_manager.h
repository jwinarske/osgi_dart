// Phase 0: interface declaration only — implementation in Phase 7.

#ifndef IVI_HOMESCREEN_OSGI_BUNDLE_ENGINE_MANAGER_H_
#define IVI_HOMESCREEN_OSGI_BUNDLE_ENGINE_MANAGER_H_

#include <cstdint>
#include <string>
#include <vector>

namespace ivi_homescreen_osgi {

/// Forward declaration — actual struct defined in Phase 7.
struct BundleManifest;

/// Manages Flutter engine instances, one per bundle AOT .so.
///
/// Spawns and destroys FlutterEngine instances per bundle.
/// Reference-counted engine lifecycle.
class BundleEngineManager {
 public:
  virtual ~BundleEngineManager() = default;

  /// Spawn a new FlutterEngine for the given bundle manifest.
  virtual void SpawnBundleEngine(const BundleManifest& manifest) = 0;

  /// Destroy the engine associated with the given symbolic name.
  virtual void DestroyBundleEngine(const std::string& symbolic_name) = 0;
};

}  // namespace ivi_homescreen_osgi

#endif  // IVI_HOMESCREEN_OSGI_BUNDLE_ENGINE_MANAGER_H_
