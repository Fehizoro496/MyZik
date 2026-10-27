import 'package:flutter/material.dart';

import '../data/waveform_repository.dart';

/// Draws a track's loudness as mirrored bars, brighter up to [played] (0 to
/// 1, the playhead's share of the track).
class WaveformPainter extends CustomPainter {
  WaveformPainter({
    required this.peaks,
    required this.played,
    required this.color,
    required this.playedColor,
  });

  final List<double> peaks;
  final double played;
  final Color color;
  final Color playedColor;

  static const _barWidth = 2.0;
  static const _gap = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    final columns = (size.width / (_barWidth + _gap)).floor();
    if (columns <= 0 || peaks.isEmpty) return;
    final heights = peaksForColumns(peaks, columns);
    final middle = size.height / 2;
    // Keep a sliver visible in silences, and room for the marker labels.
    final reach = size.height / 2 - 6;
    final playedX = played.clamp(0.0, 1.0) * size.width;
    final paint = Paint();
    for (var c = 0; c < columns; c++) {
      final x = c * (_barWidth + _gap);
      final half = 0.5 + heights[c] * reach;
      paint.color = x < playedX ? playedColor : color;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, middle - half, _barWidth, half * 2),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(WaveformPainter old) =>
      !identical(old.peaks, peaks) ||
      old.played != played ||
      old.color != color ||
      old.playedColor != playedColor;
}
