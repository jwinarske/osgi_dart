# OSGi Dart / Flutter

A Dart-native OSGi framework targeting embedded Linux IVI systems running on
[ivi-homescreen](https://github.com/toyota-connected/ivi-homescreen). Maps OSGi
lifecycle, service registry, and event administration concepts to Dart Isolates
and Flutter engine instances sharing a single Dart VM process.

## Key Design Principles

| Principle | Implementation |
|---|---|
| Control plane / data plane split | Registry stores endpoint references (ports, addresses, texture IDs), never data payloads |
| Single Dart VM | All Flutter bundles share the process VM; `SendPort` works cross-engine without platform channels |
| Zero-copy by default | Pointer addresses, mmap ring buffers, DMA-BUF fds; `TransferableTypedData` for bulk transfers |
| CAN via can_engine exclusively | All CAN bus access uses [can_engine](https://github.com/jwinarske/can_dart) |
| Priority isolation | Framework isolate dual-port; instrument cluster on critical port; startup ordering enforced in C++ |

## Packages

```
packages/
  dart_osgi_api/           Pure Dart abstract interfaces (no Flutter dependency)
  dart_osgi_framework/     Framework implementation: registry, event admin, isolate bus,
                           bundle lifecycle, zero-copy transport, performance hardening
  dart_osgi_flutter/       Flutter-specific helpers: FlutterBundleContext, OsgiBundleApp
  dart_osgi_test/          Test harness, mock registry, service test builder, DLT logger
  ivi_homescreen_osgi/     C++ plugin: BundleEngineManager, OsgiBridgePlugin, VsyncCoordinator
  sensor_bundles/          CAN, LIDAR, IMU service bundles
  plugin_adapters/         Filament, NavRender, GStreamer, Camera, WebView adapters
```

## Quick Start

### Install dependencies

```bash
dart pub get
```

Flutter packages resolve separately:

```bash
flutter pub get --directory=packages/dart_osgi_flutter
flutter pub get --directory=packages/plugin_adapters
```

### Run tests

```bash
dart test packages/dart_osgi_framework/test/ packages/dart_osgi_test/test/
```

### Run tests with coverage

```bash
dart test --coverage=coverage packages/dart_osgi_framework/test/
dart pub global activate coverage
dart pub global run coverage:format_coverage \
  --lcov --in=coverage --out=coverage/lcov.info --package=. --report-on=lib
```

### Analyze

```bash
dart analyze packages/dart_osgi_api
dart analyze packages/dart_osgi_framework
dart analyze packages/dart_osgi_test
dart analyze packages/sensor_bundles
dart analyze packages/dart_osgi_flutter
dart analyze packages/plugin_adapters
```

## Usage

### Standalone framework

```dart
import 'package:dart_osgi_framework/dart_osgi_framework.dart';

void main() async {
  final fw = DartOSGiFramework.instance;
  fw.start();

  // Install a bundle from a manifest
  final manifest = BundleManifest.parse('''
bundle:
  symbolicName: com.example.hello
  version: 1.0.0
  type: dart
  activator: lib/activator.dart
  exports:
    - com.example.HelloService
''');

  fw.installBundle(manifest);
  fw.resolveAll();
  final ctx = fw.startBundle('com.example.hello');

  // Register and look up services
  ctx.registerService<String>(
    'com.example.HelloService', 'Hello!', {'lang': 'en'},
  );
  final ref = ctx.getServiceReference<String>('com.example.HelloService');
  print(fw.registry.getService(ref!)); // Hello!

  // EventAdmin pub/sub
  final eventAdmin = EventAdmin();
  eventAdmin.subscribe('com/example/*').listen(print);
  eventAdmin.post('com/example/STARTED', const {'status': 'ok'});

  await fw.stop();
}
```

### Writing a bundle activator

```dart
class MyActivator implements BundleActivator {
  ServiceRegistration<MyService>? _reg;

  @override
  Future<void> start(BundleContext ctx) async {
    _reg = ctx.registerService<MyService>(
      'com.ivi.MyService', MyServiceImpl(), {'version': '1.0'},
    );
  }

  @override
  Future<void> stop(BundleContext ctx) async {
    await _reg?.unregister();
  }
}
```

### Testing bundles

```dart
import 'package:dart_osgi_test/dart_osgi_test.dart';
import 'package:test/test.dart';

void main() {
  late BundleTestHarness harness;

  setUp(() async {
    harness = BundleTestHarness();
    harness.services
      .when('com.ivi.can.CanEngineService')
      .thenReturn(mockCanEngine);
    harness.services.apply();
    await harness.start();
  });

  tearDown(() => harness.dispose());

  test('bundle registers signals', () async {
    await harness.installAndStartFromYaml(canBundleYaml);
    expect(
      harness.registry.registrations,
      contains(predicate<RegisterCall>(
        (c) => c.className.startsWith('com.ivi.can.signal.'),
      )),
    );
  });
}
```

### Bundle manifest (bundle.yaml)

```yaml
bundle:
  symbolicName: com.ivi.instrument-cluster
  version: 1.0.0
  type: flutter
  activator: lib/activator.dart
  flutterAsset: build/cluster
  startup:
    priority: critical
    timeout_ms: 500
  imports:
    - com.ivi.can.CanBusService: ">=1.0.0"
  exports:
    - com.ivi.cluster.ClusterService
  vm_args:
    - "--old_gen_heap_size=32"
    - "--new_gen_semi_max_size=4"
  cpu_affinity: 0
  priority_port: true
```

### Multi-bundle config (ivi-homescreen)

```json
{
  "global": { "app_id": "ivi_cluster" },
  "osgi": {
    "framework_core": 0,
    "bundles": [
      { "path": "bundles/instrument-cluster", "priority": "critical" },
      { "path": "bundles/can-service",        "priority": "critical" },
      { "path": "bundles/navigation",         "priority": "normal"   },
      { "path": "bundles/media-player",       "priority": "normal"   }
    ]
  }
}
```

## Architecture

### Zero-Copy Transport

| Data type | Transport | Copies |
|---|---|---|
| CAN frames | can_engine shared-memory snapshot | Per can_engine impl |
| DBC signal values | Dart decode, same isolate | Zero |
| Large buffers (LIDAR) | `Pointer.address` as `int` via `SendPort` | Zero |
| High-freq sensors (IMU) | mmap SPSC ring buffer (Rust FFI) | Zero |
| Video frames | GStreamer EGL external texture | Zero (GPU-only) |
| Service property maps | `const Map` sent by VM reference | Zero |
| Audio / bulk transfers | `TransferableTypedData` | One-time O(1) move |

**Caveat**: `Pointer.asTypedList(finalizer:)` is isolate-bound, not
isolate-group-bound ([dart-lang/sdk #55800](https://github.com/dart-lang/sdk/issues/55800)).
Always use raw `Pointer.address` for cross-isolate zero-copy.

### Startup Sequence

1. C++ `BundleStartupOrchestrator` reads `default_config.json`
2. **Critical** bundles start synchronously, block until ACTIVE (max 500ms)
3. **Normal** bundles start staggered 50ms apart
4. **Background** bundles start after all normal bundles

### Framework Isolate Priority

The framework isolate runs dual `ReceivePort`s. The scheduler drains
**all** priority messages before processing **one** normal message per
event loop turn. Only bundles with `priority_port: true` in their
manifest access the critical port.

## CI

GitHub Actions workflow runs on push/PR to `main` and `v2.0`:

- **Format** check across all pure Dart packages
- **Analyze** per package (Dart and Flutter separately)
- **Test** with LCOV coverage uploaded to Codecov
- **clang-format** advisory check on C++ files

## License

See [LICENSE](LICENSE) for details.
