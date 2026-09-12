/// The FFI shell transport for the Dart OSGi framework.
///
/// Flutter-free on purpose. A headless bundle -- a CAN decoder, a telemetry
/// sink -- has no views, and the MethodChannel transport would have it
/// initialize a UI binding and resolve against the Flutter SDK to send three
/// integers. This talks to `libihs_shared.so.1` instead, which is the surface
/// ivi-homescreen already documents for out-of-tree plugins.
///
/// It also keeps the ACTIVE report off the platform thread. That thread is at
/// its busiest during exactly the window the report has to cross -- first
/// frame, pipeline warm-up -- and a critical bundle's startup deadline is
/// running the whole time.
///
/// Which transport a bundle gets is a property of how far it is trusted, not of
/// what it needs: `dart:ffi` grants arbitrary access to the process address
/// space, so it can only be handed to code the image already trusts. A bundle's
/// own code is identical either way -- that is what `ShellTransport` is for.
library;

export 'package:osgi_api/osgi_api.dart';

export 'src/ffi_shell_transport.dart';
export 'src/osgi_bindings.dart'
    show NativeOsgiBindings, OsgiBindings, OsgiRegistration, OsgiStatus;
