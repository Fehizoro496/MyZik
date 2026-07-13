import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../models.dart';
import 'library_provider.dart';
import 'navigation_provider.dart';
import 'shared_preferences_provider.dart';

const _kLastSongId = 'playback.lastSongId';
const _kLastPositionMs = 'playback.lastPositionMs';

/// How playback behaves once the queue reaches its end.
enum PlaybackRepeatMode {
  /// Stop after the last track.
  off,

  /// Wrap back to the first track (the historical default behaviour).
  all,

  /// Keep replaying the current track.
  one,
}

class PlaybackState {
  const PlaybackState({
    this.current,
    this.currentIndex,
    this.queue = const [],
    this.playing = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.shuffle = false,
    this.repeatMode = PlaybackRepeatMode.all,
  });

  final Song? current;

  /// Index of [current] within [queue].
  final int? currentIndex;

  /// The ordered play queue. Defaults to library order when a song is played
  /// from a list, but the user can reorder it from the queue sheet, so it is
  /// its own list rather than a view over the library.
  final List<Song> queue;

  final bool playing;
  final Duration position;
  final Duration duration;
  final bool shuffle;
  final PlaybackRepeatMode repeatMode;

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

  PlaybackState copyWith({
    Song? current,
    int? currentIndex,
    List<Song>? queue,
    bool? playing,
    Duration? position,
    Duration? duration,
    bool? shuffle,
    PlaybackRepeatMode? repeatMode,
  }) {
    return PlaybackState(
      current: current ?? this.current,
      currentIndex: currentIndex ?? this.currentIndex,
      queue: queue ?? this.queue,
      playing: playing ?? this.playing,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      shuffle: shuffle ?? this.shuffle,
      repeatMode: repeatMode ?? this.repeatMode,
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
      if (s == ProcessingState.completed) _onTrackFinished();
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
      queue: List<Song>.of(songs),
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

  /// Open a song from a library list, jump to Now Playing and start playback.
  /// Resets the queue to library order starting context (the user picked from
  /// the library, so a fresh queue is expected); [playQueueIndex] is used
  /// instead when jumping within the existing queue.
  Future<void> playSong(Song song) async {
    final songs = ref.read(libraryProvider).songs;
    final inLibrary = songs.contains(song);
    final queue = inLibrary ? List<Song>.of(songs) : <Song>[song];
    final index = inLibrary ? songs.indexOf(song) : 0;
    state = PlaybackState(
      current: song,
      currentIndex: index,
      queue: queue,
      duration: song.duration,
      shuffle: state.shuffle,
      repeatMode: state.repeatMode,
    );
    ref.read(navigationProvider.notifier).goTo(AppScreen.nowPlaying);
    _persistSongId(song.id);
    await _load(song, play: true);
  }

  /// Jump to a track already in the queue by its index, preserving queue order
  /// (used by the queue sheet). Unlike [playSong] it never rebuilds the queue.
  Future<void> playQueueIndex(int index) async {
    final queue = state.queue;
    if (index < 0 || index >= queue.length) return;
    final song = queue[index];
    state = state.copyWith(
      current: song,
      currentIndex: index,
      duration: song.duration,
      position: Duration.zero,
    );
    ref.read(navigationProvider.notifier).goTo(AppScreen.nowPlaying);
    _persistSongId(song.id);
    await _load(song, play: true);
  }

  /// Reorder the queue (ReorderableListView indices). Keeps the currently
  /// playing track current by recomputing its index after the move.
  void reorderQueue(int oldIndex, int newIndex) {
    final queue = List<Song>.of(state.queue);
    if (oldIndex < 0 || oldIndex >= queue.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    newIndex = newIndex.clamp(0, queue.length - 1);
    if (newIndex == oldIndex) return;
    final moved = queue.removeAt(oldIndex);
    queue.insert(newIndex, moved);
    final current = state.current;
    final newCurrent = current == null ? -1 : queue.indexOf(current);
    state = state.copyWith(
      queue: queue,
      currentIndex: newCurrent == -1 ? state.currentIndex : newCurrent,
    );
  }

  /// Load [song]'s file into the player (and optionally start it). Sample /
  /// desktop data has no uri yet, so this is a no-op there.
  Future<void> _load(Song song, {required bool play}) async {
    final uri = song.uri;
    if (uri == null) return;
    try {
      await _player.setAudioSource(AudioSource.uri(Uri.parse(uri)));
      if (play) await _player.play();
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

  /// Skip to the next song: a random one when shuffling, otherwise the next
  /// in the queue order (wraps around).
  Future<void> next() async {
    final queue = state.queue;
    final idx = state.currentIndex;
    if (queue.isEmpty || idx == null) return;
    final i = state.shuffle
        ? _randomIndexExcluding(queue.length, idx)
        : (idx + 1) % queue.length;
    await playQueueIndex(i);
  }

  /// Restart the current song if we're past 3s, otherwise go to the previous
  /// (a random one when shuffling, otherwise the prior queue entry).
  Future<void> previous() async {
    final queue = state.queue;
    final idx = state.currentIndex;
    if (queue.isEmpty || idx == null) return;
    if (state.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }
    final i = state.shuffle
        ? _randomIndexExcluding(queue.length, idx)
        : (idx - 1 + queue.length) % queue.length;
    await playQueueIndex(i);
  }

  /// Called when a track finishes playing on its own (not a manual skip):
  /// honours [PlaybackRepeatMode.one] by looping and [PlaybackRepeatMode.off] by stopping at
  /// the end of the library instead of wrapping around.
  Future<void> _onTrackFinished() async {
    if (state.repeatMode == PlaybackRepeatMode.one) {
      await _player.seek(Duration.zero);
      await _player.play();
      return;
    }
    final queue = state.queue;
    final idx = state.currentIndex;
    if (queue.isEmpty || idx == null) return;
    final atLastTrack = !state.shuffle && idx == queue.length - 1;
    if (atLastTrack && state.repeatMode == PlaybackRepeatMode.off) return;
    await next();
  }

  void toggleShuffle() {
    state = state.copyWith(shuffle: !state.shuffle);
  }

  void cycleRepeatMode() {
    final next = switch (state.repeatMode) {
      PlaybackRepeatMode.off => PlaybackRepeatMode.all,
      PlaybackRepeatMode.all => PlaybackRepeatMode.one,
      PlaybackRepeatMode.one => PlaybackRepeatMode.off,
    };
    state = state.copyWith(repeatMode: next);
  }

  int _randomIndexExcluding(int length, int exclude) {
    if (length <= 1) return exclude;
    final i = Random().nextInt(length - 1);
    return i < exclude ? i : i + 1;
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
