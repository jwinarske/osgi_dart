// Phase 7: BundleStartupOrchestrator implementation.

#include "bundle_startup_orchestrator_impl.h"

#include <algorithm>
#include <chrono>
#include <fstream>
#include <sstream>
#include <thread>

#include "ivi_homescreen_osgi/bundle_engine_manager.h"

namespace ivi_homescreen_osgi {

BundleStartupOrchestratorImpl::BundleStartupOrchestratorImpl() = default;
BundleStartupOrchestratorImpl::~BundleStartupOrchestratorImpl() = default;

std::vector<BundleManifest> BundleStartupOrchestratorImpl::LoadManifests(
    const std::string& config_path) {
  // Parse the multi-bundle JSON config.
  //
  // Expected format:
  // {
  //   "global": { "app_id": "ivi_cluster" },
  //   "osgi": {
  //     "framework_core": 0,
  //     "bundles": [
  //       { "path": "bundles/instrument-cluster", "priority": "critical" },
  //       { "path": "bundles/navigation",         "priority": "normal"   }
  //     ]
  //   }
  // }
  //
  // For each entry in bundles[], read {path}/bundle.yaml and parse it.
  //
  // In the actual ivi-homescreen build this uses the existing JSON/TOML
  // config parser. Here we document the contract.

  std::vector<BundleManifest> manifests;

  // TODO: Parse config_path JSON, iterate bundles[], call ParseBundleYaml
  // for each entry.
  (void)config_path;

  // Sort by priority: critical first, then normal, then background.
  std::sort(manifests.begin(), manifests.end(),
            [](const BundleManifest& a, const BundleManifest& b) {
              return static_cast<int>(a.priority) <
                     static_cast<int>(b.priority);
            });

  return manifests;
}

bool BundleStartupOrchestratorImpl::StartCriticalBundles(
    BundleEngineManager* engine_manager,
    const std::vector<BundleManifest>& manifests, int32_t timeout_ms) {
  using clock = std::chrono::steady_clock;
  const auto deadline = clock::now() + std::chrono::milliseconds(timeout_ms);

  for (const auto& manifest : manifests) {
    if (manifest.priority != BundlePriority::kCritical) {
      continue;
    }

    engine_manager->SpawnBundleEngine(manifest);

    // Block until this bundle is ACTIVE or per-bundle timeout.
    // In the actual implementation, this polls the bundle state
    // via the Dart framework port or a shared-memory flag.
    //
    // For now, we respect the per-bundle timeout from the manifest
    // and the overall deadline.
    const auto per_bundle_timeout =
        std::min(std::chrono::milliseconds(manifest.timeout_ms),
                 std::chrono::duration_cast<std::chrono::milliseconds>(
                     deadline - clock::now()));

    if (per_bundle_timeout.count() <= 0) {
      return false;  // Overall timeout exceeded.
    }

    // TODO: Poll for bundle ACTIVE state.
    // Stub: sleep for a fraction of the timeout to simulate startup.
    std::this_thread::sleep_for(std::chrono::milliseconds(1));

    if (clock::now() >= deadline) {
      return false;
    }
  }

  return true;
}

void BundleStartupOrchestratorImpl::StartRemainingBundles(
    BundleEngineManager* engine_manager,
    const std::vector<BundleManifest>& manifests) {
  for (const auto& manifest : manifests) {
    if (manifest.priority == BundlePriority::kCritical) {
      continue;  // Already started.
    }
    engine_manager->SpawnBundleEngine(manifest);
  }
}

BundleManifest BundleStartupOrchestratorImpl::ParseBundleYaml(
    const std::string& bundle_dir) {
  // In the actual build, parse {bundle_dir}/bundle.yaml using a YAML
  // parser (yaml-cpp or similar). Map fields to BundleManifest struct.
  //
  // The Dart-side BundleManifest.parse() is authoritative for the
  // schema — this C++ parser must produce equivalent results.

  BundleManifest manifest;
  manifest.symbolic_name = bundle_dir;  // Placeholder.
  manifest.priority = BundlePriority::kNormal;
  manifest.timeout_ms = 5000;
  return manifest;
}

}  // namespace ivi_homescreen_osgi
