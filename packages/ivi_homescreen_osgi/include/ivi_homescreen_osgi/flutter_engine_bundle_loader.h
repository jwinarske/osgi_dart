// Phase 5: FlutterEngineBundleLoader — spawns a FlutterEngine per bundle AOT
// .so.

#ifndef IVI_HOMESCREEN_OSGI_FLUTTER_ENGINE_BUNDLE_LOADER_H_
#define IVI_HOMESCREEN_OSGI_FLUTTER_ENGINE_BUNDLE_LOADER_H_

#include <cstdint>
#include <string>

#include "bundle_manifest.h"

namespace ivi_homescreen_osgi {

/// Loads Flutter UI bundles by calling FlutterEngineInitialize for each
/// bundle's AOT .so.
///
/// Each bundle gets its own FlutterEngine instance within the shared
/// Dart VM process. The loader:
/// 1. Calls FlutterEngineInitialize with the bundle's AOT .so
/// 2. Passes the framework Dart_Port as the initial message
/// 3. Waits for the handshake SendPort from the bundle isolate
///
/// All engines share the Dart VM — SendPort works cross-engine.
class FlutterEngineBundleLoader {
 public:
  FlutterEngineBundleLoader() = default;
  virtual ~FlutterEngineBundleLoader() = default;
  FlutterEngineBundleLoader(const FlutterEngineBundleLoader&) = delete;
  FlutterEngineBundleLoader& operator=(const FlutterEngineBundleLoader&) =
      delete;
  FlutterEngineBundleLoader(FlutterEngineBundleLoader&&) = delete;
  FlutterEngineBundleLoader& operator=(FlutterEngineBundleLoader&&) = delete;

  /// Load and start a Flutter bundle engine.
  ///
  /// @param manifest The parsed bundle manifest.
  /// @param framework_port The framework isolate's Dart_Port for handshake.
  /// @return true if the engine was initialized and the handshake succeeded.
  virtual bool LoadBundle(const BundleManifest& manifest,
                          int64_t framework_port) = 0;

  /// Unload a Flutter bundle engine.
  ///
  /// Sends the stop signal and calls FlutterEngineShutdown.
  virtual void UnloadBundle(const std::string& symbolic_name) = 0;

  /// Check if a bundle engine is currently running.
  [[nodiscard]] virtual bool IsRunning(
      const std::string& symbolic_name) const = 0;
};

}  // namespace ivi_homescreen_osgi

#endif  // IVI_HOMESCREEN_OSGI_FLUTTER_ENGINE_BUNDLE_LOADER_H_
