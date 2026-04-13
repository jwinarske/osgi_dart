import 'package:dart_osgi_framework/dart_osgi_framework.dart';
import 'package:dart_osgi_test/dart_osgi_test.dart';
import 'package:test/test.dart';

void main() {
  group('DltLogger', () {
    group('constructor', () {
      test('default appId and contextId', () {
        final logger = DltLogger();
        expect(logger.appId, equals('OSGI'));
        expect(logger.contextId, equals('FWRK'));
      });

      test('custom appId and contextId', () {
        final logger = DltLogger(appId: 'TEST', contextId: 'MAIN');
        expect(logger.appId, equals('TEST'));
        expect(logger.contextId, equals('MAIN'));
      });
    });

    group('serviceName', () {
      test('has correct value', () {
        expect(DltLogger.serviceName, equals('com.ivi.logging.DltLogger'));
      });
    });

    group('logging methods', () {
      late DltLogger logger;

      setUp(() {
        logger = DltLogger();
      });

      test('fatal() does not throw', () {
        expect(() => logger.fatal('fatal message'), returnsNormally);
      });

      test('error() does not throw', () {
        expect(() => logger.error('error message'), returnsNormally);
      });

      test('warn() does not throw', () {
        expect(() => logger.warn('warn message'), returnsNormally);
      });

      test('info() does not throw', () {
        expect(() => logger.info('info message'), returnsNormally);
      });

      test('debug() does not throw', () {
        expect(() => logger.debug('debug message'), returnsNormally);
      });

      test('verbose() does not throw', () {
        expect(() => logger.verbose('verbose message'), returnsNormally);
      });

      test('all log methods work with custom appId/contextId', () {
        final custom = DltLogger(appId: 'APP1', contextId: 'CTX1');
        expect(() {
          custom.fatal('f');
          custom.error('e');
          custom.warn('w');
          custom.info('i');
          custom.debug('d');
          custom.verbose('v');
        }, returnsNormally);
      });
    });

    group('registerIn()', () {
      late ServiceRegistry registry;

      setUp(() {
        registry = ServiceRegistry();
      });

      tearDown(() {
        registry.dispose();
      });

      test('registers as OSGi service with correct className', () {
        final logger = DltLogger();
        final reg = logger.registerIn(registry, 'test.bundle');

        final ref = registry.getServiceReference<DltLogger>(
          DltLogger.serviceName,
        );
        expect(ref, isNotNull);

        final svc = registry.getService<DltLogger>(ref!);
        expect(svc, same(logger));

        // Clean up.
        reg.unregister();
      });

      test('registers with app.id and context.id properties', () {
        final logger = DltLogger(appId: 'MYAP', contextId: 'MYCT');
        final reg = logger.registerIn(registry, 'test.bundle');

        final ref = registry.getServiceReference<DltLogger>(
          DltLogger.serviceName,
        );
        expect(ref, isNotNull);
        expect(ref!.getProperty('app.id'), equals('MYAP'));
        expect(ref.getProperty('context.id'), equals('MYCT'));

        reg.unregister();
      });

      test('returns a valid ServiceRegistration', () {
        final logger = DltLogger();
        final reg = logger.registerIn(registry, 'test.bundle');

        expect(reg.reference, isNotNull);
        expect(reg.reference.bundleSymbolicName, equals('test.bundle'));

        reg.unregister();
      });
    });
  });
}
