// Phase 7: OsgiBridgePlugin implementation.

#include "osgi_bridge_plugin_impl.h"

// dart_api_dl.h is provided by the Flutter engine for dynamic API access.
// #include <dart_api_dl.h>

namespace ivi_homescreen_osgi {

OsgiBridgePluginImpl::OsgiBridgePluginImpl() = default;
OsgiBridgePluginImpl::~OsgiBridgePluginImpl() = default;

void OsgiBridgePluginImpl::RegisterFrameworkPort(int64_t framework_port,
                                                 int64_t bundle_init_port) {
  if (post_cobject_ == nullptr) {
    // Dart_PostCObject_DL not yet resolved — skip.
    return;
  }

  // Build a Dart_CObject carrying the framework port as an int64.
  //
  // In the actual build with dart_api_dl.h:
  //
  //   Dart_CObject port_msg;
  //   port_msg.type = Dart_CObject_kInt64;
  //   port_msg.value.as_int64 = framework_port;
  //   post_cobject_(bundle_init_port, &port_msg);
  //
  (void)framework_port;
  (void)bundle_init_port;
}

void OsgiBridgePluginImpl::RegisterWithRegistrar(void* registrar) {
  // In the actual build:
  //
  //   // Initialize the Dart dynamic API.
  //   intptr_t result = Dart_InitializeApiDL(
  //       FlutterDesktopGetDartObject(registrar));
  //   if (result != 0) return;
  //
  //   // Resolve Dart_PostCObject_DL.
  //   post_cobject_ = reinterpret_cast<PostCObjectFn>(
  //       Dart_PostCObject_DL);
  //
  (void)registrar;
}

bool OsgiBridgePluginImpl::IsBridged(const std::string& symbolic_name) const {
  return bridged_bundles_.count(symbolic_name) > 0;
}

void OsgiBridgePluginImpl::MarkBridged(const std::string& symbolic_name) {
  bridged_bundles_.insert(symbolic_name);
}

}  // namespace ivi_homescreen_osgi
