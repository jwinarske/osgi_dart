// Phase 5: comp_surf lifecycle hooks — surface show/hide on bundle state
// transitions.

#ifndef IVI_HOMESCREEN_OSGI_COMP_SURF_LIFECYCLE_H_
#define IVI_HOMESCREEN_OSGI_COMP_SURF_LIFECYCLE_H_

#include <cstdint>
#include <string>

namespace ivi_homescreen_osgi {

/// Manages compositor surface visibility tied to bundle lifecycle.
///
/// - comp_surf.show() called when bundle transitions STARTING → ACTIVE
/// - comp_surf.hide() called when bundle transitions to STOPPING
/// - Surface z-ordering is priority-based via ivi-shell
class CompSurfLifecycle {
 public:
  CompSurfLifecycle() = default;
  virtual ~CompSurfLifecycle() = default;
  CompSurfLifecycle(const CompSurfLifecycle&) = delete;
  CompSurfLifecycle& operator=(const CompSurfLifecycle&) = delete;
  CompSurfLifecycle(CompSurfLifecycle&&) = delete;
  CompSurfLifecycle& operator=(CompSurfLifecycle&&) = delete;

  /// Show the surface for a bundle (STARTING → ACTIVE transition).
  ///
  /// @param symbolic_name Bundle identifier.
  /// @param surface_id The compositor surface ID.
  virtual void ShowSurface(const std::string& symbolic_name,
                           int32_t surface_id) = 0;

  /// Hide the surface for a bundle (STOPPING transition).
  virtual void HideSurface(const std::string& symbolic_name,
                           int32_t surface_id) = 0;

  /// Set the z-order for a bundle's surface.
  ///
  /// Higher values are rendered on top. Critical bundles default to
  /// the highest z-order.
  ///
  /// @param surface_id The compositor surface ID.
  /// @param z_order The z-order value.
  virtual void SetZOrder(int32_t surface_id, int32_t z_order) = 0;

  /// Query the current z-order of a surface.
  [[nodiscard]] virtual int32_t GetZOrder(int32_t surface_id) const = 0;
};

}  // namespace ivi_homescreen_osgi

#endif  // IVI_HOMESCREEN_OSGI_COMP_SURF_LIFECYCLE_H_
