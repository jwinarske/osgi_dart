cmake_minimum_required(VERSION 3.16)
project(ivi_homescreen_osgi LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Interface-only library — headers define the C++ contracts.
# Implementation is built within the ivi-homescreen CMake tree (Phase 7).

add_library(ivi_homescreen_osgi INTERFACE)

target_include_directories(ivi_homescreen_osgi INTERFACE
  ${CMAKE_CURRENT_SOURCE_DIR}/include
)

# Header listing for IDE integration.
set(IVI_HOMESCREEN_OSGI_HEADERS
  include/ivi_homescreen_osgi/bundle_engine_manager.h
  include/ivi_homescreen_osgi/bundle_manifest.h
  include/ivi_homescreen_osgi/comp_surf_lifecycle.h
  include/ivi_homescreen_osgi/flutter_engine_bundle_loader.h
  include/ivi_homescreen_osgi/osgi_bridge_plugin.h
  include/ivi_homescreen_osgi/vsync_coordinator.h
)
