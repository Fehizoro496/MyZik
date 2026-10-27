import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_zik/data/song_key.dart';
import 'package:my_zik/models.dart';
import 'package:my_zik/providers/downloads_provider.dart' show youtubeSongId;
import 'package:my_zik/providers/liked_provider.dart';
import 'package:my_zik/providers/playlists_provider.dart';
import 'package:my_zik/providers/shared_preferences_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// In-memory preferences that count writes per key.
class _CountingStore extends InMemorySharedPreferencesStore {
  _CountingStore() : super.empty();

  final writes = <String, int>{};

  /// Writes to [key] as SharedPreferences names it (without its prefix).
  int writesTo(String key) => writes['flutter.$key'] ?? 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    writes.update(key, (count) => count + 1, ifAbsent: () => 1);
    return super.setValue(valueType, key, value);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'uses YouTube video identity for streamed and downloaded tracks',
    () async {
      final prefs = await SharedPreferences.getInstance();
      const song = Song(
        id: 1,
        title: 'Title',
        artist: 'Artist',
        youtubeVideoId: 'dQw4w9WgXcQ',
      );
      expect(
        (await SongKey.forSong(song, preferences: prefs)).value,
        'yt:dQw4w9WgXcQ',
      );
    },
  );

  test(
    'fingerprints copied bytes identically and caches file metadata',
    () async {
      final dir = await Directory.systemTemp.createTemp('song_key_');
      addTearDown(() => dir.delete(recursive: true));
      final source = File('${dir.path}/a.mp3');
      final copy = File('${dir.path}/b.mp3');
      final payload = List<int>.generate(150000, (i) => i % 251);
      await source.writeAsBytes(payload);
      await copy.writeAsBytes(payload);
      final prefs = await SharedPreferences.getInstance();
      final a = await SongKey.forSong(
        Song(id: 1, title: 'A', artist: 'B', filePath: source.path),
        preferences: prefs,
      );
      final b = await SongKey.forSong(
        Song(id: 2, title: 'A', artist: 'B', filePath: copy.path),
        preferences: prefs,
      );
      expect(a.value, startsWith('fp:'));
      expect(a, b);
      expect(prefs.getString('song.fingerprints.v1'), isNotNull);
    },
  );

  test('metadata fallback normalizes artist and title with duration', () {
    const a = Song(
      id: 1,
      title: 'Hello,  WORLD!',
      artist: 'The Artist',
      duration: Duration(seconds: 185),
    );
    const b = Song(
      id: 2,
      title: 'hello world',
      artist: 'THE ARTIST',
      duration: Duration(seconds: 185),
    );
    expect(SongKey.metadataKey(a), SongKey.metadataKey(b));
  });

  test('migrates legacy likes and playlist entries to portable keys', () async {
    final dir = await Directory.systemTemp.createTemp('song_migration_');
    addTearDown(() => dir.delete(recursive: true));
    final audio = File('${dir.path}/local.mp3');
    await audio.writeAsBytes(List<int>.generate(100, (i) => i));
    SharedPreferences.setMockInitialValues({
      'liked.songIds': ['42'],
      'playlists.v1': jsonEncode([
        {
          'id': 'p1',
          'name': 'Mix',
          'songIds': [42],
        },
      ]),
    });
    final prefs = await SharedPreferences.getInstance();
    final song = Song(
      id: 42,
      title: 'Title',
      artist: 'Artist',
      filePath: audio.path,
    );
    await SongKeyMigration.run([song], prefs);

    final key = prefs
        .getStringList(SongKeyMigration.likedKeysPreference)!
        .single;
    expect(key, startsWith('fp:'));
    final playlists = jsonDecode(prefs.getString('playlists.v1')!) as List;
    expect((playlists.single as Map)['songKeys'], [key]);
    expect(SongKeyMigration.keyForMediaId(prefs, 42), key);
  });

  group('streamed YouTube tracks', () {
    const videoId = 'dQw4w9WgXcQ';

    ProviderContainer makeContainer(SharedPreferences prefs) {
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      return container;
    }

    // Streamed from Discover, these tracks are never part of the library, so
    // the migration never maps their id.
    test('liking one records its portable key, unliking removes it', () async {
      final prefs = await SharedPreferences.getInstance();
      final liked = makeContainer(prefs).read(likedProvider.notifier);

      liked.toggle(youtubeSongId(videoId));
      expect(
        prefs.getStringList(SongKeyMigration.likedKeysPreference),
        contains('yt:$videoId'),
      );

      liked.toggle(youtubeSongId(videoId));
      expect(
        prefs.getStringList(SongKeyMigration.likedKeysPreference) ?? const [],
        isNot(contains('yt:$videoId')),
      );
    });

    test('adding one to a playlist records its portable key', () async {
      final prefs = await SharedPreferences.getInstance();
      final container = makeContainer(prefs);
      final playlists = container.read(playlistsProvider.notifier);
      final playlist = playlists.create('Mix');

      playlists.addSong(playlist.id, youtubeSongId(videoId));

      expect(container.read(playlistsProvider).single.songKeys, [
        'yt:$videoId',
      ]);
    });
  });

  group('migration re-runs', () {
    test('running again duplicates no liked or playlist keys', () async {
      final dir = await Directory.systemTemp.createTemp('song_rerun_');
      addTearDown(() => dir.delete(recursive: true));
      Song songAt(int id, List<int> bytes) {
        final file = File('${dir.path}/$id.mp3')..writeAsBytesSync(bytes);
        return Song(id: id, title: 'T$id', artist: 'A', filePath: file.path);
      }

      // Songs 1 and 3 are byte-identical copies: one portable key.
      final songs = [
        songAt(1, List<int>.generate(100, (i) => i)),
        songAt(2, List<int>.generate(100, (i) => 200 - i)),
        songAt(3, List<int>.generate(100, (i) => i)),
      ];
      SharedPreferences.setMockInitialValues({
        'liked.songIds': ['1', '2'],
        'playlists.v1': jsonEncode([
          {
            'id': 'p1',
            'name': 'Mix',
            'songIds': [1, 2, 3],
          },
        ]),
      });
      final prefs = await SharedPreferences.getInstance();

      await SongKeyMigration.run(songs, prefs);
      await SongKeyMigration.run(songs, prefs);

      final first = SongKeyMigration.keyForMediaId(prefs, 1)!;
      final second = SongKeyMigration.keyForMediaId(prefs, 2)!;
      expect(SongKeyMigration.keyForMediaId(prefs, 3), first);
      expect(
        prefs.getStringList(SongKeyMigration.likedKeysPreference),
        unorderedEquals([first, second]),
      );
      final playlists = jsonDecode(prefs.getString('playlists.v1')!) as List;
      expect((playlists.single as Map)['songKeys'], [first, second]);
    });

    test('a large library writes its fingerprint cache in one batch', () async {
      final dir = await Directory.systemTemp.createTemp('song_large_');
      addTearDown(() => dir.delete(recursive: true));
      final songs = [
        for (var i = 0; i < 1000; i++)
          Song(
            id: i,
            title: 'Track $i',
            artist: 'Artist',
            filePath: (File(
              '${dir.path}/$i.mp3',
            )..writeAsBytesSync([...utf8.encode('$i'), 0, 1, 2])).path,
          ),
      ];
      final store = _CountingStore();
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = store;
      final prefs = await SharedPreferences.getInstance();
      const cacheKey = 'song.fingerprints.v1';

      await SongKeyMigration.run(songs, prefs);
      expect(store.writesTo(cacheKey), lessThanOrEqualTo(1));
      expect(SongKeyMigration.keyForMediaId(prefs, 999), startsWith('fp:'));

      // Every file is unchanged: the second launch hashes and writes nothing.
      store.writes.clear();
      await SongKeyMigration.run(songs, prefs);
      expect(store.writesTo(cacheKey), 0);
    });
  });
}
