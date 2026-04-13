import 'dart:developer';

import 'package:dart_osgi_framework/dart_osgi_framework.dart';

/// DLT (Diagnostic Log and Trace) logging bridge for production
/// vehicle logging.
///
/// On the Dart side, this service captures framework events and
/// forwards them via `dart:developer` log calls that the C++ host
/// routes to the DLT daemon.
///
/// On the C++ side, `OsgiBridgePlugin` uses `DLT_LOG` macros to
/// write directly to the DLT daemon.
///
/// DLT log levels map to `dart:developer` levels:
/// - DLT_LOG_FATAL  → 1200
/// - DLT_LOG_ERROR  → 1000
/// - DLT_LOG_WARN   → 900
/// - DLT_LOG_INFO   → 800
/// - DLT_LOG_DEBUG  → 500
/// - DLT_LOG_VERBOSE → 300
class DltLogger {
  DltLogger({this.appId = 'OSGI', this.contextId = 'FWRK'});

  static const serviceName = 'com.ivi.logging.DltLogger';

  /// DLT application ID (4 chars).
  final String appId;

  /// DLT context ID (4 chars).
  final String contextId;

  /// Log at DLT_LOG_FATAL level.
  void fatal(String message) => _log(message, 1200, 'FATAL');

  /// Log at DLT_LOG_ERROR level.
  void error(String message) => _log(message, 1000, 'ERROR');

  /// Log at DLT_LOG_WARN level.
  void warn(String message) => _log(message, 900, 'WARN');

  /// Log at DLT_LOG_INFO level.
  void info(String message) => _log(message, 800, 'INFO');

  /// Log at DLT_LOG_DEBUG level.
  void debug(String message) => _log(message, 500, 'DEBUG');

  /// Log at DLT_LOG_VERBOSE level.
  void verbose(String message) => _log(message, 300, 'VERBOSE');

  void _log(String message, int level, String levelName) {
    log(message, name: '$appId.$contextId', level: level);
  }

  /// Register this DltLogger as an OSGi service.
  ServiceRegistration<DltLogger> registerIn(
    ServiceRegistry registry,
    String bundleSymbolicName,
  ) {
    return registry.register<DltLogger>(serviceName, this, bundleSymbolicName, {
      'app.id': appId,
      'context.id': contextId,
    });
  }

  /// Wire framework events to DLT logging.
  ///
  /// Logs bundle lifecycle transitions and service events at INFO level.
  void wireFrameworkEvents(DartOSGiFramework framework) {
    framework.bundleEvents.listen((event) {
      info('Bundle ${event.type.name}: ${event.bundle.symbolicName}');
    });
    framework.serviceEvents.listen((event) {
      info(
        'Service ${event.type.name}: '
        '${event.reference.getProperty('objectClass')}',
      );
    });
  }
}
