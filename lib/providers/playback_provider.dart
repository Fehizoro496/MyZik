import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../models.dart';
import 'audio_handler.dart';
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

    // Route OS media-session buttons (headset/Bluetooth, lock screen,
    // notification) to the same controller methods the in-app UI uses.
    ref.read(audioHandlerProvider)
      ..onPlay = resume
      ..onPause = pause
      ..onNext = next
      ..onPrevious = previous
      ..onSeekTo = _player.seek;

    // Mirror playback state out to the OS session on every change.
    listenSelf((previous, next) => _broadcast(previous, next));

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
    final position = Duration(
      milliseconds: prefs.getInt(_kLastPositionMs) ?? 0,
    );
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

  /// Open [song] and start playback, setting the play queue to [context] — the
  /// list the user picked it from (e.g. the liked tracks, a playlist, the home
  /// "top songs"). Defaults to the whole library when no context is given. This
  /// is what scopes next/previous to the right set of tracks; [playQueueIndex]
  /// is used instead when jumping within the existing queue.
  Future<void> playSong(Song song, {List<Song>? context}) async {
    final source = context ?? ref.read(libraryProvider).songs;
    final inSource = source.contains(song);
    final queue = inSource ? List<Song>.of(source) : <Song>[song];
    final index = inSource ? source.indexOf(song) : 0;
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
      await pause();
    } else {
      await resume();
    }
  }

  /// Resume the current track. Also the OS session's "play" action.
  Future<void> resume() async {
    if (state.current == null) return;
    await _player.play();
  }

  /// Pause the current track. Also the OS session's "pause" action.
  Future<void> pause() async {
    await _player.pause();
    _persistPosition();
  }

  /// Mirror a state change out to the OS media session: transport state every
  /// time, now-playing metadata only when the track actually changes.
  void _broadcast(PlaybackState? previous, PlaybackState next) {
    final handler = ref.read(audioHandlerProvider);
    handler.broadcast(
      playing: next.playing,
      position: next.position,
      bufferedPosition: next.position,
    );
    final song = next.current;
    if (song != null && song.id != previous?.current?.id) {
      handler.setNowPlaying(
        id: song.id.toString(),
        title: song.title,
        artist: song.artist,
        album: song.album,
        duration: song.duration,
      );
      // Cover art arrives asynchronously; re-publish the item with it once ready.
      _publishArtwork(song);
    }
  }

  /// Stage the current track's cover art to a temp file and re-publish the
  /// now-playing item with its `file://` URI, so it shows on the lock screen
  /// and notification (the session can't render the raw bytes on_audio_query
  /// returns). No-op when the track has no embedded artwork.
  Future<void> _publishArtwork(Song song) async {
    try {
      final bytes = await ref.read(artworkProvider(song.id).future);
      if (bytes == null || state.current?.id != song.id) return;
      final file = File(
        '${Directory.systemTemp.path}/myzik_art_${song.id}.jpg',
      );
      if (!file.existsSync()) await file.writeAsBytes(bytes, flush: true);
      if (state.current?.id != song.id) return; // track changed while writing
      ref
          .read(audioHandlerProvider)
          .setNowPlaying(
            id: song.id.toString(),
            title: song.title,
            artist: song.artist,
            album: song.album,
            duration: song.duration,
            artUri: Uri.file(file.path),
          );
    } catch (_) {
      // Best-effort: keep playing without cover art on the lock screen.
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
