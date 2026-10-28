import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_zik/data/app_database.dart';
import 'package:my_zik/data/app_database_migration.dart';
import 'package:my_zik/data/lyrics_repository.dart';
import 'package:my_zik/data/song_key.dart';
import 'package:my_zik/models.dart';
import 'package:my_zik/sync/sync_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'memory database stores likes, ordered playlists and journal rows',
    () async {
      final database = await AppDatabase.inMemory();
      addTearDown(database.close);

      database.replaceLikes({'fp:one'});
      database.replacePlaylists([
        {
          'id': 'mix',
          'name': 'Mix',
          'songKeys': ['yt:first', 'fp:one'],
        },
      ]);
      database.putSyncRecord('like:fp:one', {
        'sequence': 1,
        'updatedAt': 10,
        'origin': 'device',
        'deleted': false,
        'found': false,
      }, sequence: 1);
      await database.flush();

      expect(database.likedKeys, {'fp:one'});
      expect(database.playlists.single['songKeys'], ['yt:first', 'fp:one']);
      expect(database.journal['like:fp:one']?['sequence'], 1);
    },
  );

  test('legacy data moves into the database, then the old copies go', () async {
    SharedPreferences.setMockInitialValues({
      'liked.songKeys.v1': ['yt:abc'],
      // Id 9 has no track yet: it must stay pending.
      'liked.songIds': ['5', '9'],
      'song.keyByMediaId.v1': jsonEncode({'5': 'fp:five'}),
      'playlists.v1': jsonEncode([
        {
          'id': 'mix',
          'name': 'Mix',
          'songKeys': ['yt:abc'],
          'songIds': [5, 9],
        },
        {
          'id': 'done',
          'name': 'Done',
          'songKeys': ['fp:five'],
        },
      ]),
      'sync.deviceId': 'device-1',
      'downloads.tracks': <String>[],
    });
    final preferences = await SharedPreferences.getInstance();
    final support = await Directory.systemTemp.createTemp('myzik-sqlite-');
    addTearDown(() => support.delete(recursive: true));
    final separator = Platform.pathSeparator;
    final lyrics = Directory('${support.path}${separator}lyrics');
    await lyrics.create();
    await File('${lyrics.path}${separator}yt_abc.json').writeAsString(
      jsonEncode({'_songKey': 'yt:abc', 'source': 'lrclib', 'lines': []}),
    );
    final libraryIndex = File('${support.path}${separator}library_index.json')
      ..writeAsStringSync('[]');
    final received = Directory('${support.path}${separator}received')
      ..createSync();
    final receivedIndex = File('${received.path}${separator}index.json')
      ..writeAsStringSync('[]');
    final receivedAudio = File('${received.path}${separator}fp_x.mp3')
      ..writeAsBytesSync([1, 2, 3]);
    final database = await AppDatabase.inMemory();
    addTearDown(database.close);

    await database.migrateLegacy(
      preferences: preferences,
      supportDirectory: support,
    );

    expect(database.likedKeys, {'yt:abc', 'fp:five'});
    expect(database.playlists.first['songKeys'], ['yt:abc', 'fp:five']);
    expect(database.lyric('yt:abc'), isNotNull);
    expect(database.deviceId, 'device-1');
    expect(await database.isMigrated('legacy.v1'), isTrue);
    expect(await database.isMigrated('legacy.cleanup.v1'), isTrue);

    // The old copies are gone...
    expect(lyrics.existsSync(), isFalse);
    expect(libraryIndex.existsSync(), isFalse);
    expect(receivedIndex.existsSync(), isFalse);
    for (final key in [
      'liked.songKeys.v1',
      'sync.deviceId',
      'downloads.tracks',
    ]) {
      expect(preferences.containsKey(key), isFalse, reason: key);
    }
    // ...but not the received audio, nor the ids still waiting.
    expect(receivedAudio.existsSync(), isTrue);
    expect(preferences.getStringList('liked.songIds'), ['9']);
    final pending = jsonDecode(preferences.getString('playlists.v1')!) as List;
    expect(pending, [
      {
        'id': 'mix',
        'name': 'Mix',
        'songKeys': <String>[],
        'songIds': [9],
      },
    ]);
  });

  test('an install migrated by an older build is cleaned up once', () async {
    SharedPreferences.setMockInitialValues({
      'liked.songKeys.v1': ['yt:abc'],
    });
    final preferences = await SharedPreferences.getInstance();
    final support = await Directory.systemTemp.createTemp('myzik-sqlite-');
    addTearDown(() => support.delete(recursive: true));
    final database = await AppDatabase.inMemory();
    addTearDown(database.close);
    // Imported earlier, old copies kept.
    await database.markDone('legacy.v1');

    await database.migrateLegacy(
      preferences: preferences,
      supportDirectory: support,
    );

    // Not imported again (the database stays as it was)...
    expect(database.likedKeys, isEmpty);
    // ...but the old copy is removed.
    expect(preferences.containsKey('liked.songKeys.v1'), isFalse);
    expect(await database.isMigrated('legacy.cleanup.v1'), isTrue);
  });

  group('atomically', () {
    late AppDatabase database;

    setUp(() async => database = await AppDatabase.inMemory());
    tearDown(() => database.close());

    test('commits every write together', () async {
      await database.atomically(() async {
        database.replaceLikes({'fp:a'});
        await database.putLyrics('fp:a', {'plain': 'Words'});
        database.putSyncRecord('like:fp:a', {
          'sequence': 1,
          'updatedAt': 5,
          'origin': 'me',
          'deleted': false,
          'found': false,
        }, sequence: 1);
      });

      // Read back from the disk.
      await database.reload();
      expect(database.likedKeys, {'fp:a'});
      expect(database.lyric('fp:a')?['plain'], 'Words');
      expect(database.journal['like:fp:a']?['updatedAt'], 5);
    });

    test('writes nothing when the change fails half way', () async {
      database.replaceLikes({'fp:before'});
      await database.flush();

      await expectLater(
        database.atomically(() async {
          database.replaceLikes({'fp:before', 'fp:half'});
          throw StateError('the journal could not be updated');
        }),
        throwsStateError,
      );

      // Memory shows the disk again, which never got the half change.
      expect(database.likedKeys, {'fp:before'});
      await database.reload();
      expect(database.likedKeys, {'fp:before'});
    });
  });

  test('deleted and found flags survive a reload of the journal', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final database = await AppDatabase.inMemory();
    addTearDown(database.close);
    // Rows read back from SQLite, where booleans are 0 and 1.
    await database.importLegacyRows(
      likes: const {},
      playlists: const [],
      lyrics: const {},
      syncRecords: {
        'like:gone': {
          'sequence': 1,
          'updatedAt': 10,
          'origin': 'a',
          'deleted': true,
          'found': false,
        },
        'lyrics:fp:x': {
          'sequence': 2,
          'updatedAt': 20,
          'origin': 'a',
          'deleted': false,
          'found': true,
        },
      },
      syncState: const {'sequence': '2'},
      pairedDevices: const [],
      fingerprints: const {},
      libraryIndex: const {},
      downloads: const {},
      receivedFiles: const {},
    );

    final store = SyncStore(preferences, database: database);

    expect(store.recordOf('like:gone')!.deleted, isTrue);
    expect(store.recordOf('lyrics:fp:x')!.found, isTrue);
    expect(store.recordOf('lyrics:fp:x')!.deleted, isFalse);
  });

  test(
    'migrating late legacy ids keeps changes made in the database',
    () async {
      final dir = await Directory.systemTemp.createTemp('myzik-late-ids-');
      addTearDown(() => dir.delete(recursive: true));
      final audio = File('${dir.path}${Platform.pathSeparator}late.mp3')
        ..writeAsBytesSync(List<int>.generate(100, (i) => i));
      // Preferences as an older version left them: stale, with ids pending.
      SharedPreferences.setMockInitialValues({
        'liked.songKeys.v1': ['fp:unliked-since'],
        'liked.songIds': ['7'],
        'playlists.v1': jsonEncode([
          {
            'id': 'mix',
            'name': 'Old name',
            'songKeys': <String>[],
            'songIds': [7],
          },
        ]),
      });
      final preferences = await SharedPreferences.getInstance();
      final database = await AppDatabase.inMemory();
      addTearDown(database.close);
      // What the database holds since: renamed, filled, other likes.
      database.replaceLikes({'fp:kept'});
      database.replacePlaylists([
        {
          'id': 'mix',
          'name': 'New name',
          'songKeys': ['fp:kept'],
        },
        {'id': 'new', 'name': 'Made since', 'songKeys': <String>[]},
      ]);

      final result = await SongKeyMigration.run(
        [Song(id: 7, title: 'Late', artist: 'A', filePath: audio.path)],
        preferences,
        database: database,
      );

      final key = result.songs.single.songKey;
      expect(key, startsWith('fp:'));
      expect(result.migrated, isTrue);
      expect(database.likedKeys, {'fp:kept', key});
      final playlists = {for (final p in database.playlists) p['id']: p};
      expect(playlists['mix']!['name'], 'New name');
      expect(playlists['mix']!['songKeys'], ['fp:kept', key]);
      expect(playlists.keys, containsAll(['mix', 'new']));
    },
  );

  group('lyrics of the same recording under another key', () {
    late AppDatabase database;
    late LyricsRepository repository;

    setUp(() async {
      database = await AppDatabase.inMemory();
      // LRCLIB answers "not found": only stored lyrics can show.
      final offline = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) => handler.reject(
              DioException(
                requestOptions: options,
                response: Response(requestOptions: options, statusCode: 404),
              ),
            ),
          ),
        );
      repository = LyricsRepository(
        dio: offline,
        apiKey: '',
        database: database,
      );
    });
    tearDown(() => database.close());

    test('lyrics from the other device are found by metadata', () async {
      await repository.writeSyncedLyrics('fp:desktop', {
        ...const Lyrics(
          source: LyricsSource.lrclib,
          plain: 'From the computer',
        ).toJson(),
        '_songMetadata': 'an artist|a song|200',
      });

      const phoneCopy = Song(
        id: 1,
        title: 'A Song',
        artist: 'An Artist',
        duration: Duration(seconds: 201),
        contentKey: 'fp:phone',
      );
      expect((await repository.find(phoneCopy))?.plain, 'From the computer');
      expect(await repository.storedLyrics(), {'fp:desktop': true});
    });

    test(
      'found lyrics match too, hand-made first; unknown duration matches',
      () async {
        await database.putLyrics(
          'fp:found',
          const Lyrics(source: LyricsSource.lrclib, plain: 'Found').toJson(),
          artist: 'an artist',
          title: 'a song',
          durationSeconds: 0,
          found: true,
        );
        expect(
          (await database.lyricByMetadata(
            'an artist',
            'a song',
            180,
          ))?['plain'],
          'Found',
        );

        await database.putLyrics(
          'fp:mine',
          const Lyrics(source: LyricsSource.manual, plain: 'Mine').toJson(),
          artist: 'an artist',
          title: 'a song',
          durationSeconds: 181,
        );
        expect(
          (await database.lyricByMetadata(
            'an artist',
            'a song',
            180,
          ))?['plain'],
          'Mine',
        );
        // Too far apart: another recording.
        expect(await database.lyricByMetadata('an artist', 'a song', 260), {
          ...const Lyrics(source: LyricsSource.lrclib, plain: 'Found').toJson(),
        });
        expect(await database.lyricByMetadata('other', 'a song', 180), isNull);
      },
    );
  });
}
