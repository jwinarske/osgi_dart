/// Flutter integration for the Dart OSGi framework.
///
/// A bundle that draws depends on this; a headless one depends only on
/// `osgi_api` and stays free of a UI binding.
library;

export 'package:osgi_api/osgi_api.dart';

export 'src/method_channel_transport.dart';
