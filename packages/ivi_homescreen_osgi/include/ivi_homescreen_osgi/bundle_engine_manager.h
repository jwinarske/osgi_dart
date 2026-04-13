// Phase 5: Updated with BundleManifest definition and FlutterEngineBundleLoader
// integration.

#ifndef IVI_HOMESCREEN_OSGI_BUNDLE_ENGINE_MANAGER_H_
#define IVI_HOMESCREEN_OSGI_BUNDLE_ENGINE_MANAGER_H_

#include <cstdint>
#include <string>
#include <vector>

#include "bundle_manifest.h"

namespace ivi_homescreen_osgi {

/// Manages Flutter engine instances, one per bundle AOT .so.
///
/// Spawns and destroys FlutterEngine instances per bundle.
/// Reference-counted engine lifecycle. Coordinates with
/// VsyncCoordinator for frame timing and CompSurfLifecycle
/// for surface visibility.
class BundleEngineManager {
 public:
  BundleEngineManager() = default;
  virtual ~BundleEngineManager() = default;
  BundleEngineManager(const BundleEngineManager&) = delete;
  BundleEngineManager& operator=(const BundleEngineManager&) = delete;
  BundleEngineManager(BundleEngineManager&&) = delete;
  BundleEngineManager& operator=(BundleEngineManager&&) = delete;

  /// Spawn a new FlutterEngine for the given bundle manifest.
  ///
  /// For Flutter bundles: calls FlutterEngineInitialize with the AOT .so,
  /// passes framework Dart_Port as initial message.
  /// For Dart bundles: delegates to Dart-side IsolateBundleLoader.
  virtual void SpawnBundleEngine(const BundleManifest& manifest) = 0;

  /// Destroy the engine associated with the given symbolic name.
  virtual void DestroyBundleEngine(const std::string& symbolic_name) = 0;

  /// Set the framework Dart_Port used for handshake with bundle isolates.
  virtual void SetFrameworkPort(int64_t framework_port) = 0;

  /// Get the number of currently active bundle engines.
  [[nodiscard]] virtual size_t ActiveEngineCount() const = 0;
};

}  // namespace ivi_homescreen_osgi

#endif  // IVI_HOMESCREEN_OSGI_BUNDLE_ENGINE_MANAGER_H_
