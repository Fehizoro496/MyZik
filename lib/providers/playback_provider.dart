import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../data/youtube_repository.dart';
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

  /// The whole queue handed to the player, so it moves on to the next track
  /// natively. Advancing from Dart instead left a gap between tracks in which
  /// a sleeping phone could freeze the app and never start the next one.
  ConcatenatingAudioSource? _playlist;

  /// The songs of [_playlist], in play order: the queue order, or a shuffled
  /// order of it while shuffling. Songs without a uri are left out.
  List<Song> _playOrder = const [];

  /// While non-zero the player is being (re)loaded or its playlist rearranged,
  /// so its index and idle/error events are transient and ignored.
  int _busy = 0;

  /// Playlist mutations run one after the other, each against the order the
  /// previous one left.
  Future<void> _mutations = Future.value();

  /// Tracks skipped in a row because they failed to load; stops skipping once
  /// the whole queue has been tried.
  int _failedInARow = 0;

  @override
  PlaybackState build() {
    _player = AudioPlayer(
      userAgent: youtubeStreamUserAgent,
      useProxyForRequestHeaders: false,
    );
    ref.onDispose(() {
      _persistTimer?.cancel();
      _player.dispose();
    });

    // Whether sound is actually coming out: just_audio keeps `playing` on at
    // the end of the queue (state completed), when nothing plays any more.
    _player.playerStateStream.listen((_) {
      if (state.playing != _isPlaying) {
        state = state.copyWith(playing: _isPlaying);
      }
    });
    _player.positionStream.listen((pos) {
      state = state.copyWith(position: pos);
    });
    _player.durationStream.listen((d) {
      if (d != null) state = state.copyWith(duration: d);
    });
    _player.currentIndexStream.listen(_onPlayerIndex);
    _player.processingStateStream.listen((s) {
      if (s == ProcessingState.ready) _failedInARow = 0;
      // An unreadable track leaves the player idle. Reacting to the idle state
      // rather than to the error itself lets just_audio first release the
      // failed platform player, which would otherwise interrupt the reload.
      if (s == ProcessingState.idle) _skipUnplayable();
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

    ref.listen<LibraryState>(libraryProvider, (previous, next) {
      _maybeRestore(next.songs);
      _followTags(next.songs);
    });
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
    await _loadQueue(song, play: false, position: position);
  }

  /// Gives the queued songs the tags and cover [library] now shows for them
  /// (the listener edited them, here or on another device). Only what is
  /// shown changes: the player keeps going.
  void _followTags(List<Song> library) {
    if (state.queue.isEmpty) return;
    final shownByKey = <String, Song>{};
    for (final song in library) {
      if (song.hasStableKey) shownByKey.putIfAbsent(song.songKey, () => song);
    }
    final replaced = <Song, Song>{};
    Song follow(Song song) {
      if (replaced[song] case final done?) return done;
      if (!song.hasStableKey) return song;
      final shown = shownByKey[song.songKey];
      final next = shown == null || shown.sameLabels(song)
          ? song
          : song.withLabelsOf(shown);
      if (!identical(next, song)) replaced[song] = next;
      return next;
    }

    final queue = [for (final song in state.queue) follow(song)];
    final current = state.current == null ? null : follow(state.current!);
    if (replaced.isEmpty) return;
    _playOrder = [for (final song in _playOrder) replaced[song] ?? song];
    state = state.copyWith(queue: queue, current: current);
  }

  /// Takes [song], whose file is about to be deleted, out of the queue. When
  /// it is the current track, the next one takes its place (playing only if
  /// it was) and the player lets go of the file.
  Future<void> removeSong(Song song) async {
    bool isDeleted(Song s) => s.id == song.id && s.uri == song.uri;
    if (!state.queue.any(isDeleted)) return;
    final queue = [
      for (final s in state.queue)
        if (!isDeleted(s)) s,
    ];
    final current = state.current;
    if (current == null || !isDeleted(current)) {
      final order = _playOrder;
      final children = [
        for (var i = order.length - 1; i >= 0; i--)
          if (isDeleted(order[i])) i,
      ];
      _playOrder = [
        for (final s in order)
          if (!isDeleted(s)) s,
      ];
      state = state.copyWith(
        queue: queue,
        currentIndex: current == null ? null : queue.indexOf(current),
      );
      _mutate((playlist) async {
        for (final child in children) {
          await playlist.removeAt(child);
        }
      });
      return;
    }

    // The play order once loaded, else the queue itself.
    final order = _playOrder.contains(current) ? _playOrder : state.queue;
    final at = order.indexOf(current);
    final following = [
      ...order.skip(at + 1),
      ...order.take(at),
    ].where((s) => !isDeleted(s));
    final next = following.firstOrNull;
    if (next == null) {
      _playlist = null;
      _playOrder = const [];
      state = PlaybackState(
        shuffle: state.shuffle,
        repeatMode: state.repeatMode,
      );
      await _player.stop();
      return;
    }
    final play = _isPlaying;
    state = state.copyWith(queue: queue);
    _setCurrent(next, queue.indexOf(next));
    await _loadQueue(next, play: play);
  }

  /// Open [song] and start playback, setting the play queue to [context] — the
  /// list the user picked it from (e.g. the liked tracks, a playlist, the home
  /// "top songs"). Defaults to the whole library when no context is given. This
  /// is what scopes next/previous to the right set of tracks; [playQueueIndex]
  /// is used instead when jumping within the existing queue.
  Future<void> playSong(
    Song song, {
    List<Song>? context,
    bool throwOnLoadError = false,
  }) async {
    final previousState = state;
    final source = context ?? ref.read(libraryProvider).songs;
    final inSource = source.contains(song);
    final queue = inSource ? List<Song>.of(source) : <Song>[song];
    final index = inSource ? source.indexOf(song) : 0;
    state = PlaybackState(
      current: song,
      currentIndex: index,
      queue: queue,
      duration: song.duration,
      // Carried over: when a track was already playing, the player's play()
      // is a no-op that emits nothing, so nothing would set it back.
      playing: _isPlaying,
      shuffle: state.shuffle,
      repeatMode: state.repeatMode,
    );
    if (throwOnLoadError) {
      try {
        await _loadQueue(song, play: true, throwOnError: true);
      } catch (_) {
        state = previousState;
        rethrow;
      }
      // Keep the source screen visible while a remote URL is being prepared;
      // only navigate after ExoPlayer has accepted it.
      ref.read(navigationProvider.notifier).goTo(AppScreen.nowPlaying);
      _persistSongId(song.id);
      return;
    }

    ref.read(navigationProvider.notifier).goTo(AppScreen.nowPlaying);
    _persistSongId(song.id);
    await _loadQueue(song, play: true);
  }

  /// Jump to a track already in the queue by its index, preserving queue order
  /// (used by the queue sheet). Unlike [playSong] it never rebuilds the queue.
  Future<void> playQueueIndex(int index) async {
    final queue = state.queue;
    if (index < 0 || index >= queue.length) return;
    final song = queue[index];
    _setCurrent(song, index);
    ref.read(navigationProvider.notifier).goTo(AppScreen.nowPlaying);
    final child = _playOrder.indexOf(song);
    if (_playlist == null || child == -1) {
      await _loadQueue(song, play: true);
    } else {
      await _playChild(child);
    }
  }

  void _setCurrent(Song song, int index) {
    state = state.copyWith(
      current: song,
      currentIndex: index,
      duration: song.duration,
      position: Duration.zero,
    );
    _persistSongId(song.id);
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
    // While shuffling the play order is independent of the queue order.
    if (!state.shuffle) _syncPlayOrder(queue);
  }

  /// Hand the whole queue to the player and start it from [song]. Sample data
  /// has no uri, so nothing is loaded for it.
  Future<void> _loadQueue(
    Song song, {
    required bool play,
    Duration? position,
    bool throwOnError = false,
  }) async {
    if (song.uri == null) {
      _playlist = null;
      _playOrder = const [];
      return;
    }
    _playOrder = playOrderFor(state.queue, song, shuffle: state.shuffle);
    _playlist = ConcatenatingAudioSource(
      children: [
        for (final s in _playOrder) AudioSource.uri(Uri.parse(s.uri!)),
      ],
    );
    await _loadChild(
      _playOrder.indexOf(song),
      play: play,
      position: position,
      throwOnError: throwOnError,
    );
  }

  /// (Re)load [_playlist] in the player, starting at its [child]-th track.
  Future<void> _loadChild(
    int child, {
    required bool play,
    Duration? position,
    bool throwOnError = false,
  }) async {
    final playlist = _playlist;
    if (playlist == null) return;
    _busy++;
    try {
      await _player.setLoopMode(_loopModeFor(state.repeatMode));
      await _player.setAudioSource(
        playlist,
        initialIndex: child,
        initialPosition: position,
      );
      // just_audio's play() future completes when playback ends, not when it
      // starts. Do not keep UI actions pending for the duration of the track.
      if (play) unawaited(_player.play());
    } catch (error, stackTrace) {
      if (throwOnError) Error.throwWithStackTrace(error, stackTrace);
      // Superseded by another load: that one decides what plays.
      if (error is PlayerInterruptedException) return;
      if (!identical(playlist, _playlist)) return;
      // Local library entries may become unreadable after a rescan: move on
      // to the next track rather than stopping silently.
      if (play) _skipFrom(child);
    } finally {
      _busy--;
    }
  }

  /// Start the [child]-th track of the loaded playlist from its beginning.
  Future<void> _playChild(int child) async {
    if (_player.processingState == ProcessingState.idle) {
      // Nothing loaded (or a failed track): seeking alone would not play.
      return _loadChild(child, play: true);
    }
    _busy++;
    try {
      await _player.seek(Duration.zero, index: child);
    } finally {
      _busy--;
    }
    unawaited(_player.play());
  }

  /// Mirror a track the player moved to on its own (end of the previous one)
  /// into the state.
  void _onPlayerIndex(int? child) {
    if (_busy > 0 || child == null || child >= _playOrder.length) return;
    final song = _playOrder[child];
    if (identical(song, state.current)) return;
    final index = state.queue.indexOf(song);
    if (index == -1) return;
    _setCurrent(song, index);
  }

  /// The current track failed to load: go on with the next one, the way the
  /// player itself would at the end of a track.
  void _skipUnplayable() {
    if (_busy > 0 || _playlist == null) return;
    final current = state.current;
    final child = current == null ? -1 : _playOrder.indexOf(current);
    if (child != -1) _skipFrom(child);
  }

  void _skipFrom(int child) {
    if (++_failedInARow >= _playOrder.length) return; // nothing plays
    final atEnd = child == _playOrder.length - 1;
    if (atEnd && state.repeatMode == PlaybackRepeatMode.off) return;
    final next = (child + 1) % _playOrder.length;
    final song = _playOrder[next];
    _setCurrent(song, state.queue.indexOf(song));
    unawaited(_loadChild(next, play: true));
  }

  /// Rearrange the loaded playlist to follow [queue] (non-shuffled order)
  /// without interrupting the current track.
  void _syncPlayOrder(List<Song> queue) {
    _mutate((playlist) async {
      final target = playOrderFor(queue, state.current, shuffle: false);
      for (final (from, to) in movesToMatch(_playOrder, target)) {
        await playlist.move(from, to);
      }
      _playOrder = target;
    });
  }

  /// Re-deal the play order around the current track after shuffle was
  /// toggled: a fresh random order, or back to the queue order.
  void _reshuffle() {
    final queue = state.queue;
    final shuffle = state.shuffle;
    _mutate((playlist) async {
      final current = state.current;
      final child = current == null ? -1 : _playOrder.indexOf(current);
      if (child == -1) return;
      final order = playOrderFor(queue, current, shuffle: shuffle);
      final at = order.indexOf(current!);
      await playlist.removeRange(child + 1, playlist.length);
      await playlist.removeRange(0, child);
      if (at > 0) {
        await playlist.insertAll(0, [
          for (final s in order.take(at)) AudioSource.uri(Uri.parse(s.uri!)),
        ]);
      }
      await playlist.addAll([
        for (final s in order.skip(at + 1)) AudioSource.uri(Uri.parse(s.uri!)),
      ]);
      _playOrder = order;
    });
  }

  /// Run [op] on the loaded playlist once the previous mutation is done. The
  /// player's index events are ignored meanwhile (they refer to half-updated
  /// orders) and the current track is re-read at the end.
  void _mutate(Future<void> Function(ConcatenatingAudioSource) op) {
    final playlist = _playlist;
    if (playlist == null) return;
    _mutations = _mutations.then((_) async {
      if (!identical(playlist, _playlist)) return;
      _busy++;
      try {
        await op(playlist);
      } catch (_) {
        // Best-effort: the current track keeps playing either way.
      } finally {
        _busy--;
      }
      _onPlayerIndex(_player.currentIndex);
    });
  }

  /// Whether the player is making sound, as the play/pause buttons show it.
  bool get _isPlaying =>
      _player.playing && _player.processingState != ProcessingState.completed;

  Future<void> togglePlay() async {
    if (state.current == null) return;
    // Decided on what the button shows, so a tap always does what it says.
    if (_isPlaying) {
      await pause();
    } else {
      await resume();
    }
  }

  /// Resume the current track. Also the OS session's "play" action. At the
  /// end of the queue, starts it over.
  Future<void> resume() async {
    if (state.current == null) return;
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(
        Duration.zero,
        index: _player.effectiveIndices?.firstOrNull ?? 0,
      );
    }
    // play()'s future completes when playback stops, not when it starts.
    if (!_player.playing) unawaited(_player.play());
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
    final previousSong = previous?.current;
    final changed =
        song != null &&
        (song.id != previousSong?.id ||
            // Same track, edited tags or cover.
            !identical(song, previousSong) && !song.sameLabels(previousSong!));
    if (changed) {
      handler.setNowPlaying(
        id: song.id.toString(),
        title: song.title,
        artist: song.artist,
        album: song.album,
        duration: song.duration,
        artUri: song.artworkUrl == null ? null : Uri.parse(song.artworkUrl!),
      );
      // Local cover art arrives asynchronously; remote tracks already expose
      // a network artwork URI that audio_service can publish directly.
      if (song.artworkUrl == null) _publishArtwork(song);
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

  /// Skip to the next song in the play order (the shuffled one when
  /// shuffling), wrapping around.
  Future<void> next() => _step(1);

  /// Restart the current song if we're past 3s, otherwise go to the previous
  /// one in the play order.
  Future<void> previous() async {
    if (state.queue.isEmpty || state.currentIndex == null) return;
    if (state.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }
    await _step(-1);
  }

  Future<void> _step(int delta) async {
    final queue = state.queue;
    final idx = state.currentIndex;
    if (queue.isEmpty || idx == null) return;
    final current = state.current;
    final child = current == null ? -1 : _playOrder.indexOf(current);
    if (_playlist != null && child != -1) {
      final length = _playOrder.length;
      final song = _playOrder[(child + delta + length) % length];
      return playQueueIndex(queue.indexOf(song));
    }
    // No playlist loaded (sample data without files): walk the queue itself.
    final i = state.shuffle
        ? _randomIndexExcluding(queue.length, idx)
        : (idx + delta + queue.length) % queue.length;
    await playQueueIndex(i);
  }

  void toggleShuffle() {
    state = state.copyWith(shuffle: !state.shuffle);
    _reshuffle();
  }

  void cycleRepeatMode() {
    final next = switch (state.repeatMode) {
      PlaybackRepeatMode.off => PlaybackRepeatMode.all,
      PlaybackRepeatMode.all => PlaybackRepeatMode.one,
      PlaybackRepeatMode.one => PlaybackRepeatMode.off,
    };
    state = state.copyWith(repeatMode: next);
    // The player handles the end of a track itself, so it needs the mode.
    if (_playlist != null) unawaited(_player.setLoopMode(_loopModeFor(next)));
  }

  static LoopMode _loopModeFor(PlaybackRepeatMode mode) => switch (mode) {
    PlaybackRepeatMode.off => LoopMode.off,
    PlaybackRepeatMode.all => LoopMode.all,
    PlaybackRepeatMode.one => LoopMode.one,
  };

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

  /// Move the playhead to an absolute [position] (tapping a lyrics line).
  void seek(Duration position) => _player.seek(position);

  /// The player's position right now. [PlaybackState.position] only updates
  /// every ~200 ms, too coarse for timing lyrics by hand.
  Duration get livePosition => _player.position;

  /// Output volume, 0 to 1 (the desktop player bar's slider).
  double get volume => _player.volume;

  Future<void> setVolume(double volume) =>
      _player.setVolume(volume.clamp(0.0, 1.0));

  /// Playback rate, 1 being normal speed (slowed down to time lyrics).
  double get speed => _player.speed;

  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

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

/// The order the player goes through [queue]: the queue order, or with
/// [shuffle] a random order starting at [current]. Songs without a uri (sample
/// data) can't be played and are left out.
List<Song> playOrderFor(
  List<Song> queue,
  Song? current, {
  required bool shuffle,
}) {
  final playable = [
    for (final s in queue)
      if (s.uri != null) s,
  ];
  if (!shuffle) return playable;
  final rest = [
    for (final s in playable)
      if (!identical(s, current)) s,
  ]..shuffle();
  return [if (current != null && current.uri != null) current, ...rest];
}

/// The `(from, to)` moves that rearrange [order] into [target] (the same
/// songs), applied one after the other. A single reorder of the queue takes a
/// single move.
List<(int, int)> movesToMatch(List<Song> order, List<Song> target) {
  final work = List<Song>.of(order);
  final moves = <(int, int)>[];
  while (true) {
    var first = 0;
    while (first < work.length && identical(work[first], target[first])) {
      first++;
    }
    if (first == work.length) return moves;
    var last = work.length - 1;
    while (identical(work[last], target[last])) {
      last--;
    }
    // Either the first mismatch moved down to the last one, or the last one
    // moved up to the first.
    final (from, to) = identical(work[first], target[last])
        ? (first, last)
        : (work.indexOf(target[first]), first);
    work.insert(to, work.removeAt(from));
    moves.add((from, to));
  }
}

final playbackProvider = NotifierProvider<PlaybackNotifier, PlaybackState>(
  PlaybackNotifier.new,
);
