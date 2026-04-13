// Phase 7: Concrete BundleStartupOrchestrator implementation.

#ifndef IVI_HOMESCREEN_OSGI_BUNDLE_STARTUP_ORCHESTRATOR_IMPL_H_
#define IVI_HOMESCREEN_OSGI_BUNDLE_STARTUP_ORCHESTRATOR_IMPL_H_

#include <string>
#include <vector>

#include "ivi_homescreen_osgi/bundle_startup_orchestrator.h"

namespace ivi_homescreen_osgi {

/// Concrete [BundleStartupOrchestrator] that parses the multi-bundle
/// JSON config and orchestrates priority-ordered startup.
class BundleStartupOrchestratorImpl : public BundleStartupOrchestrator {
 public:
  BundleStartupOrchestratorImpl();
  ~BundleStartupOrchestratorImpl() override;

  // BundleStartupOrchestrator interface
  std::vector<BundleManifest> LoadManifests(
      const std::string& config_path) override;
  bool StartCriticalBundles(BundleEngineManager* engine_manager,
                            const std::vector<BundleManifest>& manifests,
                            int32_t timeout_ms = 500) override;
  void StartRemainingBundles(
      BundleEngineManager* engine_manager,
      const std::vector<BundleManifest>& manifests) override;

 private:
  /// Parse a single bundle.yaml from a bundle directory.
  static BundleManifest ParseBundleYaml(const std::string& bundle_dir);
};

}  // namespace ivi_homescreen_osgi

#endif  // IVI_HOMESCREEN_OSGI_BUNDLE_STARTUP_ORCHESTRATOR_IMPL_H_
