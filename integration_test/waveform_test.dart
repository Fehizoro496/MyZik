import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:my_zik/data/waveform_repository.dart';

/// 16-bit mono WAV: [loud] seconds of a 440 Hz tone, then [quiet] seconds of
/// silence.
Uint8List _wav({required int loud, required int quiet}) {
  const rate = 44100;
  final frames = (loud + quiet) * rate;
  final data = ByteData(44 + frames * 2);
  void ascii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      data.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + frames * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, frames * 2, Endian.little);
  for (var i = 0; i < loud * rate; i++) {
    final sample = (sin(2 * pi * 440 * i / rate) * 0.8 * 32767).round();
    data.setInt16(44 + i * 2, sample, Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the Windows runner decodes a waveform', (tester) async {
    final dir = await Directory.systemTemp.createTemp('myzik_waveform_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}tone é.wav')
      ..writeAsBytesSync(_wav(loud: 1, quiet: 1));

    final peaks = await const WaveformRepository().peaks(file.path);

    expect(peaks, isNotNull);
    expect(peaks!.length, WaveformRepository.buckets);
    final half = peaks.length ~/ 2;
    final tone = peaks.sublist(10, half - 10);
    final silence = peaks.sublist(half + 10, peaks.length - 10);
    expect(tone.reduce(min), greaterThan(0.9));
    expect(silence.reduce(max), lessThan(0.01));

    // Unreadable files give no waveform rather than an error.
    expect(
      await const WaveformRepository().peaks(
        '${dir.path}${Platform.pathSeparator}missing.mp3',
      ),
      isNull,
    );
  });
}
