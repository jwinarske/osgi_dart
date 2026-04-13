// Phase 5: OsgiBridgePlugin — bridges framework Dart_Port into each engine.

#ifndef IVI_HOMESCREEN_OSGI_OSGI_BRIDGE_PLUGIN_H_
#define IVI_HOMESCREEN_OSGI_OSGI_BRIDGE_PLUGIN_H_

#include <cstdint>
#include <string>

namespace ivi_homescreen_osgi {

/// Bridges the framework Dart_Port into each Flutter engine instance.
///
/// Uses dart_api_dl.h for dynamic linking — no static Dart API dependency.
/// Registers the framework port with each engine via Dart_PostCObject_DL
/// so that Dart bundle isolates can communicate with the framework
/// isolate without platform channels.
///
/// Platform channels are only used for C++ plugin calls (GStreamer,
/// Filament, Wayland surface ops).
class OsgiBridgePlugin {
 public:
  virtual ~OsgiBridgePlugin() = default;

  /// Register the framework Dart_Port with a bundle engine.
  ///
  /// @param framework_port The framework isolate's Dart_Port.
  /// @param bundle_init_port The bundle's init port for receiving the
  ///        framework port as the initial message.
  virtual void RegisterFrameworkPort(int64_t framework_port,
                                     int64_t bundle_init_port) = 0;

  /// Register the plugin with a Flutter engine's registrar.
  ///
  /// @param registrar Opaque FlutterDesktopPluginRegistrar pointer.
  virtual void RegisterWithRegistrar(void* registrar) = 0;

  /// Query whether the bridge has been established for a bundle.
  virtual bool IsBridged(const std::string& symbolic_name) const = 0;
};

}  // namespace ivi_homescreen_osgi

#endif  // IVI_HOMESCREEN_OSGI_OSGI_BRIDGE_PLUGIN_H_
