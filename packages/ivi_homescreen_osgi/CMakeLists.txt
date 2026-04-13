cmake_minimum_required(VERSION 3.16)
project(ivi_homescreen_osgi LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ── Public interface library (headers only) ──────────────────────────
# Consumed by ivi-homescreen and downstream plugins.

add_library(ivi_homescreen_osgi_headers INTERFACE)

target_include_directories(ivi_homescreen_osgi_headers INTERFACE
  ${CMAKE_CURRENT_SOURCE_DIR}/include
)

set(IVI_HOMESCREEN_OSGI_HEADERS
  include/ivi_homescreen_osgi/bundle_engine_manager.h
  include/ivi_homescreen_osgi/bundle_manifest.h
  include/ivi_homescreen_osgi/bundle_startup_orchestrator.h
  include/ivi_homescreen_osgi/comp_surf_lifecycle.h
  include/ivi_homescreen_osgi/flutter_engine_bundle_loader.h
  include/ivi_homescreen_osgi/osgi_bridge_plugin.h
  include/ivi_homescreen_osgi/vsync_coordinator.h
)

# ── Implementation library ───────────────────────────────────────────
# Built within the ivi-homescreen CMake tree where flutter_engine and
# Wayland dependencies are available.
#
# When building standalone (e.g. for IDE indexing), the Flutter embedder
# API stubs are not available — build only if the target exists.

if(TARGET flutter_engine OR DEFINED FLUTTER_ENGINE_LIBRARY)
  add_library(ivi_homescreen_osgi STATIC
    src/bundle_engine_manager_impl.cc
    src/bundle_startup_orchestrator_impl.cc
    src/osgi_bridge_plugin_impl.cc
    src/vsync_coordinator_impl.cc
  )

  target_include_directories(ivi_homescreen_osgi
    PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include
    PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src
  )

  target_link_libraries(ivi_homescreen_osgi
    PUBLIC ivi_homescreen_osgi_headers
  )

  # Link flutter_engine if available.
  if(TARGET flutter_engine)
    target_link_libraries(ivi_homescreen_osgi PRIVATE flutter_engine)
  endif()
endif()
