// Phase 5: C++ bundle manifest representation.

#ifndef IVI_HOMESCREEN_OSGI_BUNDLE_MANIFEST_H_
#define IVI_HOMESCREEN_OSGI_BUNDLE_MANIFEST_H_

#include <cstdint>
#include <string>
#include <vector>

namespace ivi_homescreen_osgi {

/// Bundle type: Flutter UI or pure Dart.
enum class BundleType { kFlutter, kDart };

/// Startup priority.
enum class BundlePriority { kCritical, kNormal, kBackground };

/// C++ representation of a bundle.yaml manifest, parsed at load time.
struct BundleManifest {
  std::string symbolic_name;
  std::string version;
  BundleType type = BundleType::kDart;
  std::string activator;
  std::string flutter_asset;  // AOT .so path; empty for dart-type bundles
  BundlePriority priority = BundlePriority::kNormal;
  int32_t timeout_ms = 5000;
  std::vector<std::string> vm_args;
  int32_t surface_z_order = 0;  // Priority-ordered surface stack via ivi-shell
};

}  // namespace ivi_homescreen_osgi

#endif  // IVI_HOMESCREEN_OSGI_BUNDLE_MANIFEST_H_
