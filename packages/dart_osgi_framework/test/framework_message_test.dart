import 'dart:isolate';

import 'package:dart_osgi_framework/dart_osgi_framework.dart';
import 'package:test/test.dart';

void main() {
  group('FrameworkMessageType', () {
    test('has all expected values', () {
      final expected = [
        FrameworkMessageType.registerService,
        FrameworkMessageType.unregisterService,
        FrameworkMessageType.setServiceProperties,
        FrameworkMessageType.getServiceReference,
        FrameworkMessageType.getServiceReferences,
        FrameworkMessageType.getService,
        FrameworkMessageType.ungetService,
        FrameworkMessageType.addBundleListener,
        FrameworkMessageType.removeBundleListener,
        FrameworkMessageType.addServiceListener,
        FrameworkMessageType.removeServiceListener,
        FrameworkMessageType.openTracker,
        FrameworkMessageType.closeTracker,
        FrameworkMessageType.registerPort,
        FrameworkMessageType.sendToBundle,
        FrameworkMessageType.bundleReady,
        FrameworkMessageType.stopBundle,
        FrameworkMessageType.response,
        FrameworkMessageType.event,
      ];

      expect(FrameworkMessageType.values, containsAll(expected));
      expect(FrameworkMessageType.values, hasLength(expected.length));
    });
  });

  group('FrameworkMessage', () {
    test('constructor with all fields', () {
      final rp = ReceivePort();
      addTearDown(rp.close);

      final msg = FrameworkMessage(
        type: FrameworkMessageType.registerService,
        bundleSymbolicName: 'com.test.a',
        payload: 'some-payload',
        replyPort: rp.sendPort,
        requestId: 42,
      );

      expect(msg.type, equals(FrameworkMessageType.registerService));
      expect(msg.bundleSymbolicName, equals('com.test.a'));
      expect(msg.payload, equals('some-payload'));
      expect(msg.replyPort, equals(rp.sendPort));
      expect(msg.requestId, equals(42));
    });

    test('constructor with minimal fields', () {
      final msg = FrameworkMessage(
        type: FrameworkMessageType.stopBundle,
        bundleSymbolicName: 'com.test.b',
      );

      expect(msg.type, equals(FrameworkMessageType.stopBundle));
      expect(msg.bundleSymbolicName, equals('com.test.b'));
      expect(msg.payload, isNull);
      expect(msg.replyPort, isNull);
      expect(msg.requestId, isNull);
    });
  });

  group('RegisterServicePayload', () {
    test('fields are stored correctly', () {
      final payload = RegisterServicePayload(
        className: 'MyService',
        service: 'the-service-object',
        properties: {'key': 'value'},
      );

      expect(payload.className, equals('MyService'));
      expect(payload.service, equals('the-service-object'));
      expect(payload.properties, equals({'key': 'value'}));
    });

    test('properties can be null', () {
      final payload = RegisterServicePayload(
        className: 'MyService',
        service: 42,
      );

      expect(payload.properties, isNull);
    });
  });

  group('GetServiceReferencesPayload', () {
    test('fields are stored correctly', () {
      final payload = GetServiceReferencesPayload(
        className: 'MyService',
        filter: '(version>=1.0)',
      );

      expect(payload.className, equals('MyService'));
      expect(payload.filter, equals('(version>=1.0)'));
    });

    test('filter can be null', () {
      final payload = GetServiceReferencesPayload(className: 'MyService');

      expect(payload.className, equals('MyService'));
      expect(payload.filter, isNull);
    });
  });

  group('SendToBundlePayload', () {
    test('fields are stored correctly', () {
      final payload = SendToBundlePayload(
        targetBundle: 'com.test.target',
        message: {'action': 'do-something'},
      );

      expect(payload.targetBundle, equals('com.test.target'));
      expect(payload.message, equals({'action': 'do-something'}));
    });
  });

  group('RegisterPortPayload', () {
    test('fields are stored correctly', () {
      final rp = ReceivePort();
      addTearDown(rp.close);

      final payload = RegisterPortPayload(
        bundleSymbolicName: 'com.test.a',
        sendPort: rp.sendPort,
      );

      expect(payload.bundleSymbolicName, equals('com.test.a'));
      expect(payload.sendPort, equals(rp.sendPort));
    });
  });
}
