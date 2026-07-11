import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'data/music_repository.dart';
import 'models.dart';

enum AppScreen { home, nowPlaying, myMusic, saved, settings }

/// Loading state of the on-device library.
enum LibraryState { loading, ready, empty, permissionDenied, error }

/// Holds navigation + playback state and the loaded song library.
///
/// Playback is driven by a real [AudioPlayer] (just_audio): position, duration
/// and playing state come from its streams. The library is read through a
/// [MusicRepository] so the source (device, desktop, sample) is swappable.
class PlayerController extends ChangeNotifier {
  PlayerController({MusicRepository? repository})
    : _repo = repository ?? createMusicRepository() {
    _player.playingStream.listen((playing) {
      _playing = playing;
      notifyListeners();
    });
    _player.positionStream.listen((pos) {
      _position = pos;
      notifyListeners();
    });
    _player.durationStream.listen((d) {
      if (d != null) {
        _duration = d;
        notifyListeners();
      }
    });
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) next();
    });
    loadLibrary();
  }

  final MusicRepository _repo;
  final AudioPlayer _player = AudioPlayer();

  AppScreen _screen = AppScreen.home;
  AppScreen get screen => _screen;

  LibraryState _libraryState = LibraryState.loading;
  LibraryState get libraryState => _libraryState;

  List<Song> _songs = const [];
  List<Song> get songs => _songs;

  bool _playing = false;
  bool get playing => _playing;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  Song? _current;
  Song? get current => _current;
  int? _currentIndex;

  double get progress {
    final total = _duration.inMilliseconds;
    if (total <= 0) return 0;
    return (_position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  String get elapsed => _fmt(_position);
  String get remaining {
    final left = _duration - _position;
    return '-${_fmt(left.isNegative ? Duration.zero : left)}';
  }

  final Map<int, Future<Uint8List?>> _artworkCache = {};

  /// Cover artwork for a song, fetched lazily and cached so scrolling doesn't
  /// re-query. Returns the same Future per song id, keeping FutureBuilders
  /// stable across rebuilds.
  Future<Uint8List?> artworkFor(Song song) {
    return _artworkCache.putIfAbsent(song.id, () => _repo.artworkFor(song.id));
  }

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
      _currentIndex = _current == null ? null : loaded.indexOf(_current!);
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

  /// Open a song, jump to Now Playing and start real playback of its file.
  Future<void> playSong(Song song) async {
    _current = song;
    _currentIndex = _songs.indexOf(song);
    _position = Duration.zero;
    _duration = song.duration;
    _screen = AppScreen.nowPlaying;
    notifyListeners();

    final uri = song.uri;
    if (uri == null) return; // sample/desktop data has no playable file yet.
    try {
      await _player.setAudioSource(AudioSource.uri(Uri.parse(uri)));
      await _player.play();
    } catch (_) {
      // Ignore unsupported/unreadable sources; keep the UI responsive.
    }
  }

  Future<void> togglePlay() async {
    if (_current == null) return;
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  /// Skip to the next song (wraps around).
  Future<void> next() async {
    if (_songs.isEmpty || _currentIndex == null) return;
    await playSong(_songs[(_currentIndex! + 1) % _songs.length]);
  }

  /// Restart the current song if we're past 3s, otherwise go to the previous.
  Future<void> previous() async {
    if (_songs.isEmpty || _currentIndex == null) return;
    if (_position.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }
    final i = (_currentIndex! - 1 + _songs.length) % _songs.length;
    await playSong(_songs[i]);
  }

  /// Move the playhead from a 0..1 fraction (progress-bar scrub).
  void seekFraction(double fraction) {
    if (_duration <= Duration.zero) return;
    _player.seek(_duration * fraction.clamp(0.0, 1.0));
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
