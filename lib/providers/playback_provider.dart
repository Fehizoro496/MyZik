import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../models.dart';
import 'library_provider.dart';
import 'navigation_provider.dart';
import 'shared_preferences_provider.dart';

const _kLastSongId = 'playback.lastSongId';
const _kLastPositionMs = 'playback.lastPositionMs';

class PlaybackState {
  const PlaybackState({
    this.current,
    this.currentIndex,
    this.playing = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  final Song? current;
  final int? currentIndex;
  final bool playing;
  final Duration position;
  final Duration duration;

  double get progress {
    final total = duration.inMilliseconds;
    if (total <= 0) return 0;
    return (position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  String get elapsed => _fmt(position);
  String get remaining {
    final left = duration - position;
    return '-${_fmt(left.isNegative ? Duration.zero : left)}';
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  PlaybackState copyWith({bool? playing, Duration? position, Duration? duration}) {
    return PlaybackState(
      current: current,
      currentIndex: currentIndex,
      playing: playing ?? this.playing,
      position: position ?? this.position,
      duration: duration ?? this.duration,
    );
  }
}

/// Drives playback through a real [AudioPlayer] (just_audio): position,
/// duration and playing state come from its streams.
///
/// The last played song id + position are persisted to [SharedPreferences] so
/// playback can resume where it left off next time the app is launched (the
/// track itself is loaded but left paused — the user taps play to continue).
class PlaybackNotifier extends Notifier<PlaybackState> {
  late final AudioPlayer _player;
  Timer? _persistTimer;
  bool _restoreAttempted = false;

  @override
  PlaybackState build() {
    _player = AudioPlayer();
    ref.onDispose(() {
      _persistTimer?.cancel();
      _player.dispose();
    });

    _player.playingStream.listen((playing) {
      state = state.copyWith(playing: playing);
    });
    _player.positionStream.listen((pos) {
      state = state.copyWith(position: pos);
    });
    _player.durationStream.listen((d) {
      if (d != null) state = state.copyWith(duration: d);
    });
    _player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) next();
    });

    _persistTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _persistPosition(),
    );

    ref.listen<LibraryState>(
      libraryProvider,
      (previous, next) => _maybeRestore(next.songs),
    );
    // Covers the case where the library is already loaded by the time this
    // notifier builds. Deferred so `state` is initialized before it runs (the
    // library is scanned asynchronously, so this always loses the race
    // against a genuinely fresh scan — the ref.listen above handles that).
    Future.microtask(() => _maybeRestore(ref.read(libraryProvider).songs));

    return const PlaybackState();
  }

  /// Reloads the last played track (id + position) once the library has
  /// finished its first scan. Runs at most once per app session.
  Future<void> _maybeRestore(List<Song> songs) async {
    if (_restoreAttempted || state.current != null || songs.isEmpty) return;
    _restoreAttempted = true;

    final prefs = ref.read(sharedPreferencesProvider);
    final id = prefs.getInt(_kLastSongId);
    if (id == null) return;
    final index = songs.indexWhere((s) => s.id == id);
    if (index == -1) return;

    final song = songs[index];
    final position = Duration(milliseconds: prefs.getInt(_kLastPositionMs) ?? 0);
    state = PlaybackState(
      current: song,
      currentIndex: index,
      duration: song.duration,
      position: position,
    );

    final uri = song.uri;
    if (uri == null) return;
    try {
      await _player.setAudioSource(
        AudioSource.uri(Uri.parse(uri)),
        initialPosition: position,
      );
    } catch (_) {
      // Ignore unreadable sources; keep the UI responsive.
    }
  }

  /// Open a song, jump to Now Playing and start real playback of its file.
  Future<void> playSong(Song song) async {
    final songs = ref.read(libraryProvider).songs;
    final index = songs.indexOf(song);
    state = PlaybackState(
      current: song,
      currentIndex: index == -1 ? null : index,
      duration: song.duration,
    );
    ref.read(navigationProvider.notifier).goTo(AppScreen.nowPlaying);
    _persistSongId(song.id);

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
    if (state.current == null) return;
    if (_player.playing) {
      await _player.pause();
      _persistPosition();
    } else {
      await _player.play();
    }
  }

  /// Skip to the next song (wraps around).
  Future<void> next() async {
    final songs = ref.read(libraryProvider).songs;
    final idx = state.currentIndex;
    if (songs.isEmpty || idx == null) return;
    await playSong(songs[(idx + 1) % songs.length]);
  }

  /// Restart the current song if we're past 3s, otherwise go to the previous.
  Future<void> previous() async {
    final songs = ref.read(libraryProvider).songs;
    final idx = state.currentIndex;
    if (songs.isEmpty || idx == null) return;
    if (state.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }
    final i = (idx - 1 + songs.length) % songs.length;
    await playSong(songs[i]);
  }

  /// Move the playhead from a 0..1 fraction (progress-bar scrub).
  void seekFraction(double fraction) {
    if (state.duration <= Duration.zero) return;
    _player.seek(state.duration * fraction.clamp(0.0, 1.0));
  }

  void _persistSongId(int id) {
    ref.read(sharedPreferencesProvider).setInt(_kLastSongId, id);
    ref.read(sharedPreferencesProvider).setInt(_kLastPositionMs, 0);
  }

  void _persistPosition() {
    if (state.current == null) return;
    ref
        .read(sharedPreferencesProvider)
        .setInt(_kLastPositionMs, state.position.inMilliseconds);
  }
}

final playbackProvider = NotifierProvider<PlaybackNotifier, PlaybackState>(
  PlaybackNotifier.new,
);
