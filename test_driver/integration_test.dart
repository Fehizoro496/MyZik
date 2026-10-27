import 'package:integration_test/integration_test_driver.dart';

/// Runs `integration_test/` through `flutter drive`, e.g. in profile mode:
/// `fvm flutter drive --driver=test_driver/integration_test.dart
/// --target=integration_test/waveform_test.dart -d windows --profile`.
Future<void> main() => integrationDriver();
