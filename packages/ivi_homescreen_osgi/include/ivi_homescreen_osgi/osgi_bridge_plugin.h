// Phase 0: interface declaration only — implementation in Phase 5/7.

#ifndef IVI_HOMESCREEN_OSGI_OSGI_BRIDGE_PLUGIN_H_
#define IVI_HOMESCREEN_OSGI_OSGI_BRIDGE_PLUGIN_H_

#include <cstdint>

namespace ivi_homescreen_osgi {

/// Bridges the framework Dart_Port into each Flutter engine instance.
///
/// Registers the framework port with each engine via Dart_PostCObject_DL
/// so that Dart bundle isolates can communicate with the framework
/// isolate without platform channels.
class OsgiBridgePlugin {
 public:
  virtual ~OsgiBridgePlugin() = default;

  /// Register the framework Dart_Port with the bundle engine.
  virtual void RegisterFrameworkPort(int64_t framework_port,
                                     int64_t bundle_init_port) = 0;
};

}  // namespace ivi_homescreen_osgi

#endif  // IVI_HOMESCREEN_OSGI_OSGI_BRIDGE_PLUGIN_H_
