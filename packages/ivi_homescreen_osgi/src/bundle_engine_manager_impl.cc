// Phase 7: BundleEngineManager implementation.

#include "bundle_engine_manager_impl.h"

#include <cassert>
#include <utility>

// Flutter embedder API headers — provided by the ivi-homescreen build.
// #include <flutter_embedder.h>

namespace ivi_homescreen_osgi {

BundleEngineManagerImpl::BundleEngineManagerImpl(VsyncCoordinator* vsync,
                                                 CompSurfLifecycle* comp_surf)
    : vsync_(vsync), comp_surf_(comp_surf) {
  assert(vsync_ != nullptr);
  assert(comp_surf_ != nullptr);
}

BundleEngineManagerImpl::~BundleEngineManagerImpl() {
  // Shut down all remaining engines.
  std::lock_guard<std::mutex> lock(mutex_);
  for (auto& [name, entry] : engines_) {
    ShutdownEngine(*entry);
  }
  engines_.clear();
}

void BundleEngineManagerImpl::SpawnBundleEngine(
    const BundleManifest& manifest) {
  std::lock_guard<std::mutex> lock(mutex_);

  // Prevent duplicate engine for the same bundle.
  if (engines_.count(manifest.symbolic_name) > 0) {
    return;
  }

  auto entry = std::make_unique<EngineEntry>();
  entry->manifest = manifest;

  // Initialize the Flutter engine with the bundle's AOT .so.
  entry->engine = InitializeEngine(manifest);
  if (entry->engine == nullptr) {
    return;
  }

  // Register with vsync coordinator.
  vsync_->RegisterEngine(manifest.symbolic_name, entry->engine);

  // Assign surface z-order based on manifest priority.
  entry->surface_id = manifest.surface_z_order;
  if (entry->surface_id >= 0) {
    comp_surf_->SetZOrder(entry->surface_id, manifest.surface_z_order);
  }

  entry->active = true;

  // Show surface (STARTING → ACTIVE transition).
  if (entry->surface_id >= 0) {
    comp_surf_->ShowSurface(manifest.symbolic_name, entry->surface_id);
  }

  engines_[manifest.symbolic_name] = std::move(entry);
}

void BundleEngineManagerImpl::DestroyBundleEngine(
    const std::string& symbolic_name) {
  std::lock_guard<std::mutex> lock(mutex_);

  auto it = engines_.find(symbolic_name);
  if (it == engines_.end()) {
    return;
  }

  ShutdownEngine(*it->second);
  engines_.erase(it);
}

void BundleEngineManagerImpl::SetFrameworkPort(int64_t framework_port) {
  framework_port_ = framework_port;
}

size_t BundleEngineManagerImpl::ActiveEngineCount() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return engines_.size();
}

const EngineEntry* BundleEngineManagerImpl::GetEntry(
    const std::string& symbolic_name) const {
  std::lock_guard<std::mutex> lock(mutex_);
  auto it = engines_.find(symbolic_name);
  return (it != engines_.end()) ? it->second.get() : nullptr;
}

FlutterEngine BundleEngineManagerImpl::InitializeEngine(
    const BundleManifest& manifest) {
  // ── Flutter Embedder API calls ──
  //
  // In the actual ivi-homescreen build, this calls:
  //
  //   FlutterRendererConfig renderer_config = { ... };
  //   FlutterProjectArgs project_args = { ... };
  //   project_args.aot_library_path = manifest.flutter_asset.c_str();
  //   project_args.dart_entrypoint_argc = manifest.vm_args.size();
  //   // ... set up vm_args ...
  //
  //   FlutterEngine engine = nullptr;
  //   FlutterEngineResult result = FlutterEngineInitialize(
  //       FLUTTER_ENGINE_VERSION,
  //       &renderer_config,
  //       &project_args,
  //       this,
  //       &engine);
  //
  //   if (result != kSuccess) return nullptr;
  //
  //   // Pass framework Dart_Port as initial message to bundle isolate.
  //   Dart_CObject port_msg;
  //   port_msg.type = Dart_CObject_kInt64;
  //   port_msg.value.as_int64 = framework_port_;
  //   Dart_PostCObject_DL(bundle_init_port, &port_msg);
  //
  //   FlutterEngineRunInitialized(engine);
  //   return engine;
  //
  // Stub: returns nullptr until linked against flutter_engine.

  (void)manifest;
  return nullptr;
}

void BundleEngineManagerImpl::ShutdownEngine(EngineEntry& entry) {
  // Hide surface (STOPPING transition).
  if (entry.surface_id >= 0) {
    comp_surf_->HideSurface(entry.manifest.symbolic_name, entry.surface_id);
  }

  // Unregister from vsync.
  vsync_->UnregisterEngine(entry.manifest.symbolic_name);

  // Shut down the Flutter engine.
  //
  // In the actual build:
  //   FlutterEngineShutdown(entry.engine);
  //
  entry.engine = nullptr;
  entry.active = false;
}

}  // namespace ivi_homescreen_osgi
