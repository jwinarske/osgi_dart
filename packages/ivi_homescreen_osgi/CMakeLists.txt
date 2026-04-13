cmake_minimum_required(VERSION 3.16)
project(ivi_homescreen_osgi LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Phase 0: placeholder — headers only, no implementation yet.
# Implementation arrives in Phase 5 (FlutterEngineBundleLoader, OsgiBridgePlugin)
# and Phase 7 (BundleEngineManager, VsyncCoordinator, BundleStartupOrchestrator).

add_library(ivi_homescreen_osgi INTERFACE)

target_include_directories(ivi_homescreen_osgi INTERFACE
  ${CMAKE_CURRENT_SOURCE_DIR}/include
)
