// Phase 7: BundleStartupOrchestrator — priority-ordered bundle startup.

#ifndef IVI_HOMESCREEN_OSGI_BUNDLE_STARTUP_ORCHESTRATOR_H_
#define IVI_HOMESCREEN_OSGI_BUNDLE_STARTUP_ORCHESTRATOR_H_

#include <cstdint>
#include <string>
#include <vector>

#include "bundle_manifest.h"

namespace ivi_homescreen_osgi {

class BundleEngineManager;

/// Reads bundle manifests, sorts by priority, and starts critical
/// bundles synchronously before the Wayland event loop begins.
///
/// Startup sequence:
/// 1. Parse all bundle.yaml manifests from the config.
/// 2. Sort by priority: critical → normal → background.
/// 3. Start all critical bundles and BLOCK until each is ACTIVE
///    (max timeout per bundle from manifest, overall max 500ms).
/// 4. Start remaining bundles asynchronously after event loop begins.
class BundleStartupOrchestrator {
 public:
  BundleStartupOrchestrator() = default;
  virtual ~BundleStartupOrchestrator() = default;
  BundleStartupOrchestrator(const BundleStartupOrchestrator&) = delete;
  BundleStartupOrchestrator& operator=(const BundleStartupOrchestrator&) =
      delete;
  BundleStartupOrchestrator(BundleStartupOrchestrator&&) = delete;
  BundleStartupOrchestrator& operator=(BundleStartupOrchestrator&&) = delete;

  /// Load bundle manifests from the multi-bundle config.
  ///
  /// @param config_path Path to the JSON config file.
  /// @return Parsed manifests sorted by priority.
  virtual std::vector<BundleManifest> LoadManifests(
      const std::string& config_path) = 0;

  /// Start all critical bundles synchronously.
  ///
  /// Blocks until all critical bundles are ACTIVE or timeout.
  /// Returns true if all critical bundles started successfully.
  ///
  /// @param engine_manager The engine manager to spawn bundles.
  /// @param manifests Pre-sorted list of bundle manifests.
  /// @param timeout_ms Max time to wait for all critical bundles (default 500).
  virtual bool StartCriticalBundles(
      BundleEngineManager* engine_manager,
      const std::vector<BundleManifest>& manifests,
      int32_t timeout_ms = 500) = 0;

  /// Start remaining (non-critical) bundles asynchronously.
  ///
  /// Called after the Wayland event loop is running.
  virtual void StartRemainingBundles(
      BundleEngineManager* engine_manager,
      const std::vector<BundleManifest>& manifests) = 0;
};

}  // namespace ivi_homescreen_osgi

#endif  // IVI_HOMESCREEN_OSGI_BUNDLE_STARTUP_ORCHESTRATOR_H_
