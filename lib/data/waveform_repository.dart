import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Loudness envelope of audio files, drawn behind the lyrics editor's
/// timeline. Decoded natively by the Windows runner (Media Foundation, see
/// `windows/runner/waveform_channel.cpp`); other platforms have none yet.
class WaveformRepository {
  const WaveformRepository();

  static const _channel = MethodChannel('my_zik/waveform');

  /// Peaks computed per file: enough for a sharp timeline on a wide screen.
  static const buckets = 1600;

  /// [buckets] peaks of the file at [path], from 0 (silence) to 1 (its
  /// loudest moment), in time order. Null when the platform can't decode it
  /// (unsupported format, missing file, no native decoder).
  Future<Float32List?> peaks(String path) async {
    if (kIsWeb || !Platform.isWindows) return null;
    try {
      return await _channel.invokeMethod<Float32List>('peaks', {
        'path': path,
        'buckets': buckets,
      });
    } on PlatformException catch (e) {
      debugPrint('Waveform: cannot decode $path: ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

final waveformRepositoryProvider = Provider<WaveformRepository>(
  (ref) => const WaveformRepository(),
);

/// Peaks of the audio file at a path, decoded once per session.
final waveformProvider = FutureProvider.family<Float32List?, String>(
  (ref, path) => ref.read(waveformRepositoryProvider).peaks(path),
);

/// Shrinks [peaks] to [columns] values, each the loudest of the peaks it
/// covers, so a narrow timeline still shows every loud moment.
List<double> peaksForColumns(List<double> peaks, int columns) {
  if (peaks.isEmpty || columns <= 0) return const [];
  final result = List<double>.filled(columns, 0);
  for (var c = 0; c < columns; c++) {
    final start = c * peaks.length ~/ columns;
    final end = max(start + 1, (c + 1) * peaks.length ~/ columns);
    for (var i = start; i < end && i < peaks.length; i++) {
      if (peaks[i] > result[c]) result[c] = peaks[i];
    }
  }
  return result;
}
