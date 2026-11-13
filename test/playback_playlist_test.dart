// Verifies that the whole queue is handed to the player, which moves on to the
// next track by itself (so a sleeping phone keeps playing through the queue),
// and that the state follows it. A fake just_audio platform stands in for
// ExoPlayer / media_kit and lets the tests end tracks or make them fail.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_zik/data/music_repository.dart';
import 'package:my_zik/models.dart';
import 'package:my_zik/providers/library_provider.dart';
import 'package:my_zik/providers/playback_provider.dart';
import 'package:my_zik/providers/shared_preferences_provider.dart';

class _FakeRepo implements MusicRepository {
  @override
  bool get isSupported => true;

  @override
  Future<bool> ensurePermission() async => true;

  @override
  Future<Uint8List?> artworkFor(int id) async => null;

  @override
  Future<List<Song>> fetchSongs() async => [
    for (final (i, title) in ['A', 'B', 'C', 'D'].indexed)
      Song(id: i + 1, title: title, artist: 'x', uri: 'file:///$title.mp3'),
  ];
}

class _FakeJustAudio extends JustAudioPlatform {
  /// The live platform player: just_audio replaces it after a failure.
  _FakePlayer? player;

  /// Tracks that fail to open, whichever platform player opens them.
  final Set<String> unreadable = {};

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async =>
      player = _FakePlayer(request.id, unreadable);

  @override
  Future<DisposePlayerResponse> disposePlayer(
    DisposePlayerRequest request,
  ) async => DisposePlayerResponse();

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
    DisposeAllPlayersRequest request,
  ) async => DisposeAllPlayersResponse();
}

/// A playlist player: keeps the loaded track uris and the current index the
/// way ExoPlayer does across playlist edits.
class _FakePlayer extends AudioPlayerPlatform {
  _FakePlayer(super.id, this.unreadable);

  final _events = StreamController<PlaybackEventMessage>.broadcast();
  List<String> uris = [];
  int index = 0;
  ProcessingStateMessage processing = ProcessingStateMessage.idle;
  LoopModeMessage loopMode = LoopModeMessage.off;
  int loads = 0;

  /// Tracks that fail to open.
  final Set<String> unreadable;

  String get currentUri => uris[index];

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _events.stream;

  void _emit() => _events.add(
    PlaybackEventMessage(
      processingState: processing,
      updateTime: DateTime.now(),
      updatePosition: Duration.zero,
      bufferedPosition: Duration.zero,
      duration: const Duration(minutes: 3),
      icyMetadata: null,
      currentIndex: index,
      androidAudioSessionId: null,
    ),
  );

  static String _uri(AudioSourceMessage m) => (m as UriAudioSourceMessage).uri;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    loads++;
    final playlist =
        request.audioSourceMessage as ConcatenatingAudioSourceMessage;
    uris = playlist.children.map(_uri).toList();
    index = request.initialIndex ?? 0;
    if (unreadable.contains(currentUri)) {
      processing = ProcessingStateMessage.idle;
      _emit();
      throw PlatformException(code: '1', message: 'cannot open $currentUri');
    }
    processing = ProcessingStateMessage.ready;
    _emit();
    return LoadResponse(duration: const Duration(minutes: 3));
  }

  /// The current track plays to its end and the player moves on by itself.
  void finishTrack() {
    if (loopMode != LoopModeMessage.one) {
      if (index == uris.length - 1 && loopMode == LoopModeMessage.off) {
        processing = ProcessingStateMessage.completed;
        _emit();
        return;
      }
      index = (index + 1) % uris.length;
    }
    if (unreadable.contains(currentUri)) {
      processing = ProcessingStateMessage.idle;
      _events.addError(PlatformException(code: '1', message: 'cannot open'));
    }
    _emit();
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async => PlayResponse();

  @override
  Future<PauseResponse> pause(PauseRequest request) async => PauseResponse();

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async =>
      SetVolumeResponse();

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async =>
      SetSpeedResponse();

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async =>
      SetPitchResponse();

  @override
  Future<SetSkipSilenceResponse> setSkipSilence(
    SetSkipSilenceRequest request,
  ) async => SetSkipSilenceResponse();

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
    SetShuffleModeRequest request,
  ) async => SetShuffleModeResponse();

  @override
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse>
  setAutomaticallyWaitsToMinimizeStalling(
    SetAutomaticallyWaitsToMinimizeStallingRequest request,
  ) async => SetAutomaticallyWaitsToMinimizeStallingResponse();

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async {
    loopMode = request.loopMode;
    return SetLoopModeResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    if (request.index != null) index = request.index!;
    // Seeking back from the end makes the track playable again.
    if (processing == ProcessingStateMessage.completed) {
      processing = ProcessingStateMessage.ready;
    }
    _emit();
    return SeekResponse();
  }

  @override
  Future<ConcatenatingMoveResponse> concatenatingMove(
    ConcatenatingMoveRequest request,
  ) async {
    final current = currentUri;
    uris.insert(request.newIndex, uris.removeAt(request.currentIndex));
    index = uris.indexOf(current);
    _emit();
    return ConcatenatingMoveResponse();
  }

  @override
  Future<ConcatenatingInsertAllResponse> concatenatingInsertAll(
    ConcatenatingInsertAllRequest request,
  ) async {
    final current = currentUri;
    uris.insertAll(request.index, request.children.map(_uri));
    index = uris.indexOf(current);
    _emit();
    return ConcatenatingInsertAllResponse();
  }

  @override
  Future<ConcatenatingRemoveRangeResponse> concatenatingRemoveRange(
    ConcatenatingRemoveRangeRequest request,
  ) async {
    final current = currentUri;
    uris.removeRange(request.startIndex, request.endIndex);
    index = uris.indexOf(current);
    _emit();
    return ConcatenatingRemoveRangeResponse();
  }

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    await _events.close();
    return DisposeResponse();
  }
}

/// Lets the player's events and the notifier's async work run.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

Future<(ProviderContainer, PlaybackNotifier, _FakeJustAudio, List<Song>)>
_bootstrap() async {
  final platform = _FakeJustAudio();
  JustAudioPlatform.instance = platform;
  SharedPreferences.setMockInitialValues({});
  final store = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(store),
      musicRepositoryProvider.overrideWithValue(_FakeRepo()),
    ],
  );
  addTearDown(container.dispose);
  await container.read(libraryProvider.notifier).load();
  final songs = container.read(libraryProvider).songs;
  return (
    container,
    container.read(playbackProvider.notifier),
    platform,
    songs,
  );
}

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);
  setUp(() {
    // just_audio activates the OS audio session before playing.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.audio_session'),
          (_) async => null,
        );
  });

  String titleOf(ProviderContainer c) =>
      c.read(playbackProvider).current!.title;

  test(
    'the whole queue is loaded and the player advances on its own',
    () async {
      final (container, notifier, platform, songs) = await _bootstrap();
      await notifier.playSong(songs[1]);
      await _settle();

      final player = platform.player!;
      expect(player.loads, 1);
      expect(player.uris, songs.map((s) => s.uri).toList());
      expect(player.currentUri, songs[1].uri);
      expect(player.loopMode, LoopModeMessage.all);

      // The track ends with no Dart involvement: the state follows the player.
      player.finishTrack();
      await _settle();
      expect(titleOf(container), 'C');
      expect(container.read(playbackProvider).currentIndex, 2);
      expect(player.loads, 1); // no reload between tracks
    },
  );

  test('next and previous jump within the loaded playlist', () async {
    final (container, notifier, platform, songs) = await _bootstrap();
    await notifier.playSong(songs[3]);
    await _settle();

    await notifier.next();
    await _settle();
    expect(titleOf(container), 'A'); // wraps around
    expect(platform.player!.currentUri, songs[0].uri);

    await notifier.previous();
    await _settle();
    expect(titleOf(container), 'D');
    expect(platform.player!.loads, 1);
  });

  test('repeat modes are handed to the player', () async {
    final (container, notifier, platform, songs) = await _bootstrap();
    await notifier.playSong(songs[3]);
    await _settle();
    final player = platform.player!;

    notifier.cycleRepeatMode(); // all -> one
    await _settle();
    expect(player.loopMode, LoopModeMessage.one);
    player.finishTrack();
    await _settle();
    expect(titleOf(container), 'D');

    notifier.cycleRepeatMode(); // one -> off
    await _settle();
    expect(player.loopMode, LoopModeMessage.off);
    player.finishTrack(); // last track: playback stops there
    await _settle();
    expect(titleOf(container), 'D');
  });

  test('an unreadable track is skipped instead of stopping', () async {
    final (container, notifier, platform, songs) = await _bootstrap();
    await notifier.playSong(songs[0]);
    await _settle();
    platform.unreadable.add(songs[1].uri!);

    platform.player!.finishTrack(); // moves on to B, which fails to open
    await _settle();
    expect(titleOf(container), 'C');
    expect(platform.player!.currentUri, songs[2].uri);
  });

  test('a track that fails to load when picked moves on to the next', () async {
    final (container, notifier, platform, songs) = await _bootstrap();
    await notifier.playSong(songs[0]);
    await _settle();
    platform.unreadable.add(songs[2].uri!);

    await notifier.playSong(songs[2]);
    await _settle();
    expect(titleOf(container), 'D');
    expect(platform.player!.currentUri, songs[3].uri);
  });

  test('reordering the queue rearranges the loaded playlist', () async {
    final (container, notifier, platform, songs) = await _bootstrap();
    await notifier.playSong(songs[0]);
    await _settle();

    notifier.reorderQueue(3, 1); // D right after A
    await _settle();
    final player = platform.player!;
    expect(player.uris, ['A', 'D', 'B', 'C'].map((t) => 'file:///$t.mp3'));
    expect(player.currentUri, songs[0].uri); // still playing A

    player.finishTrack();
    await _settle();
    expect(titleOf(container), 'D');
  });

  test('shuffle re-deals the playlist around the current track', () async {
    final (container, notifier, platform, songs) = await _bootstrap();
    await notifier.playSong(songs[2]);
    await _settle();
    final player = platform.player!;

    notifier.toggleShuffle();
    await _settle();
    expect(player.uris.first, songs[2].uri); // current track first
    expect(player.uris.toSet(), songs.map((s) => s.uri).toSet());
    expect(player.currentUri, songs[2].uri);
    expect(titleOf(container), 'C');
    // The visible queue keeps its order.
    expect(container.read(playbackProvider).queue, songs);

    // The player follows the shuffled order, and so does the state.
    player.finishTrack();
    await _settle();
    expect(container.read(playbackProvider).current!.uri, player.uris[1]);

    notifier.toggleShuffle();
    await _settle();
    expect(player.uris, songs.map((s) => s.uri).toList());
    expect(player.loads, 1);
  });

  test('a track started over another one shows as playing', () async {
    final (container, notifier, _, songs) = await _bootstrap();
    await notifier.playSong(songs[0]);
    await _settle();
    expect(container.read(playbackProvider).playing, isTrue);

    // The player is already playing: its play() emits nothing new.
    await notifier.playSong(songs[2]);
    await _settle();
    expect(titleOf(container), 'C');
    expect(container.read(playbackProvider).playing, isTrue);
  });

  test('the end of the queue shows play, which starts it over', () async {
    final (container, notifier, platform, songs) = await _bootstrap();
    notifier
      ..cycleRepeatMode() // all -> one
      ..cycleRepeatMode(); // one -> off
    await notifier.playSong(songs[3]);
    await _settle();

    platform.player!.finishTrack(); // the last track ends: nothing plays
    await _settle();
    expect(container.read(playbackProvider).playing, isFalse);

    await notifier.togglePlay();
    await _settle();
    expect(container.read(playbackProvider).playing, isTrue);
    expect(platform.player!.currentUri, songs[0].uri);
    expect(titleOf(container), 'A');
  });

  test('play/pause follows the player', () async {
    final (container, notifier, _, songs) = await _bootstrap();
    await notifier.playSong(songs[0]);
    await _settle();
    await notifier.togglePlay();
    await _settle();
    expect(container.read(playbackProvider).playing, isFalse);
    await notifier.togglePlay();
    await _settle();
    expect(container.read(playbackProvider).playing, isTrue);
  });

  group('movesToMatch', () {
    final a = Song(id: 1, title: 'A', artist: 'x');
    final b = Song(id: 2, title: 'B', artist: 'x');
    final c = Song(id: 3, title: 'C', artist: 'x');
    final d = Song(id: 4, title: 'D', artist: 'x');

    List<Song> apply(List<Song> order, List<(int, int)> moves) {
      final work = List<Song>.of(order);
      for (final (from, to) in moves) {
        work.insert(to, work.removeAt(from));
      }
      return work;
    }

    test('a single reorder takes a single move', () {
      expect(movesToMatch([a, b, c, d], [b, c, d, a]), [(0, 3)]);
      expect(movesToMatch([a, b, c, d], [d, a, b, c]), [(3, 0)]);
      expect(movesToMatch([a, b, c, d], [a, b, c, d]), isEmpty);
    });

    test('any permutation is reached', () {
      final target = [d, b, a, c];
      expect(apply([a, b, c, d], movesToMatch([a, b, c, d], target)), target);
    });
  });
}
