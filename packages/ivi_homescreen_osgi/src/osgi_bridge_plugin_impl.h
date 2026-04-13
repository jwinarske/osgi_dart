// Phase 7: Concrete OsgiBridgePlugin implementation.

#ifndef IVI_HOMESCREEN_OSGI_OSGI_BRIDGE_PLUGIN_IMPL_H_
#define IVI_HOMESCREEN_OSGI_OSGI_BRIDGE_PLUGIN_IMPL_H_

#include <cstdint>
#include <string>
#include <unordered_set>

#include "ivi_homescreen_osgi/osgi_bridge_plugin.h"

namespace ivi_homescreen_osgi {

/// Concrete [OsgiBridgePlugin] using dart_api_dl.h for dynamic linking.
///
/// Bridges the framework Dart_Port into each Flutter engine instance.
/// No static Dart API dependency — uses Dart_PostCObject_DL loaded at
/// runtime from the Flutter engine shared library.
class OsgiBridgePluginImpl : public OsgiBridgePlugin {
 public:
  OsgiBridgePluginImpl();
  ~OsgiBridgePluginImpl() override;

  // OsgiBridgePlugin interface
  void RegisterFrameworkPort(int64_t framework_port,
                             int64_t bundle_init_port) override;
  void RegisterWithRegistrar(void* registrar) override;
  [[nodiscard]] bool IsBridged(const std::string& symbolic_name) const override;

  /// Record that a bundle has been bridged.
  void MarkBridged(const std::string& symbolic_name);

 private:
  /// Dynamically loaded Dart_PostCObject function pointer.
  /// Resolved from dart_api_dl.h at plugin registration time.
  using PostCObjectFn = bool (*)(int64_t port_id, void* message);
  PostCObjectFn post_cobject_ = nullptr;

  std::unordered_set<std::string> bridged_bundles_;
};

}  // namespace ivi_homescreen_osgi

#endif  // IVI_HOMESCREEN_OSGI_OSGI_BRIDGE_PLUGIN_IMPL_H_
