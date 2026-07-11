import 'dart:async';

import 'package:flutter/material.dart';

import 'data/music_repository.dart';
import 'models.dart';

enum AppScreen { home, nowPlaying, myMusic, saved, settings }

/// Loading state of the on-device library.
enum LibraryState { loading, ready, empty, permissionDenied, error }

/// Holds navigation + playback state and the loaded song library.
///
/// The library is read through a [MusicRepository] so the source (device,
/// desktop, sample) is swappable. Playback position is still driven by a fake
/// ticker; the real audio engine is wired in a later pass.
class PlayerController extends ChangeNotifier {
  PlayerController({MusicRepository? repository})
    : _repo = repository ?? createMusicRepository() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_playing || _current == null) return;
      final total = durationSeconds;
      if (total <= 0) return;
      _position = _position + 1 > total ? 0 : _position + 1;
      notifyListeners();
    });
    loadLibrary();
  }

  final MusicRepository _repo;
  Timer? _timer;

  AppScreen _screen = AppScreen.home;
  AppScreen get screen => _screen;

  LibraryState _libraryState = LibraryState.loading;
  LibraryState get libraryState => _libraryState;

  List<Song> _songs = const [];
  List<Song> get songs => _songs;

  bool _playing = false;
  bool get playing => _playing;

  int _position = 0;
  int get durationSeconds => _current?.duration.inSeconds ?? 0;

  Song? _current;
  Song? get current => _current;

  double get progress {
    final total = durationSeconds;
    return total == 0 ? 0 : _position / total;
  }

  String get elapsed => _fmt(_position);
  String get remaining =>
      '-${_fmt((durationSeconds - _position).clamp(0, durationSeconds))}';

  /// Request permission and load the library. Safe to call again (e.g. from a
  /// "grant access" retry button).
  Future<void> loadLibrary() async {
    _libraryState = LibraryState.loading;
    notifyListeners();
    try {
      final granted = await _repo.ensurePermission();
      if (!granted) {
        _libraryState = LibraryState.permissionDenied;
        notifyListeners();
        return;
      }
      final loaded = await _repo.fetchSongs();
      _songs = loaded;
      _current ??= loaded.isEmpty ? null : loaded.first;
      _libraryState = loaded.isEmpty ? LibraryState.empty : LibraryState.ready;
    } catch (_) {
      _libraryState = LibraryState.error;
    }
    notifyListeners();
  }

  void goTo(AppScreen screen) {
    if (_screen == screen) return;
    _screen = screen;
    notifyListeners();
  }

  /// Open a song and jump to the Now Playing screen.
  void playSong(Song song) {
    _current = song;
    _position = 0;
    _playing = true;
    _screen = AppScreen.nowPlaying;
    notifyListeners();
  }

  void togglePlay() {
    if (_current == null) return;
    _playing = !_playing;
    notifyListeners();
  }

  /// Move the playhead from a 0..1 fraction (progress-bar scrub).
  void seekFraction(double fraction) {
    _position = (fraction.clamp(0.0, 1.0) * durationSeconds).round();
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
