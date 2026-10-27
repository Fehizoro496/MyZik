import 'package:flutter_test/flutter_test.dart';
import 'package:my_zik/data/waveform_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('peaksForColumns keeps the loudest peak of each column', () {
    expect(peaksForColumns([0.1, 0.9, 0.2, 0.3, 0.8, 0.0], 3), [0.9, 0.3, 0.8]);
    // More columns than peaks: each column repeats its peak.
    expect(peaksForColumns([0.2, 0.6], 4), [0.2, 0.2, 0.6, 0.6]);
    expect(peaksForColumns(const [], 4), isEmpty);
    expect(peaksForColumns([0.5], 0), isEmpty);
  });

  test('peaks is null without a native decoder', () async {
    // No Windows runner in unit tests: the channel has no handler.
    expect(await const WaveformRepository().peaks('missing.mp3'), isNull);
  });
}
