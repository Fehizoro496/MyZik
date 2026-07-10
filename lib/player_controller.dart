import 'dart:async';

import 'package:flutter/material.dart';

import 'models.dart';

enum AppScreen { home, nowPlaying, myMusic }

/// Holds navigation + playback state and drives the progress ticker.
///
/// Mirrors the design's `Component` logic: a 1s timer advances the current
/// position while playing and wraps back to 0 at the end of the track.
class PlayerController extends ChangeNotifier {
  PlayerController() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_playing) return;
      _position = _position + 1 > _duration ? 0 : _position + 1;
      notifyListeners();
    });
  }

  Timer? _timer;

  AppScreen _screen = AppScreen.home;
  AppScreen get screen => _screen;

  bool _playing = true;
  bool get playing => _playing;

  // Position/duration in seconds (design starts at 0:28 of 2:43).
  int _position = 28;
  final int _duration = 163;

  Track _current = MusicData.topPlaylists.first;
  Track get current => _current;

  double get progress => _duration == 0 ? 0 : _position / _duration;
  String get elapsed => _fmt(_position);
  String get remaining => '-${_fmt(_duration - _position)}';

  void goTo(AppScreen screen) {
    if (_screen == screen) return;
    _screen = screen;
    notifyListeners();
  }

  /// Open a track and jump to the Now Playing screen.
  void playTrack(Track track) {
    _current = track;
    _position = 0;
    _playing = true;
    _screen = AppScreen.nowPlaying;
    notifyListeners();
  }

  void togglePlay() {
    _playing = !_playing;
    notifyListeners();
  }

  /// Move the playhead from a 0..1 fraction (progress-bar scrub).
  void seekFraction(double fraction) {
    _position = (fraction.clamp(0.0, 1.0) * _duration).round();
    notifyListeners();
  }

  static String _fmt(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
