// Verifies edited song tags: the library and the play queue show them, they
// survive a restart, the file's tags come back on reset, and edits travel
// between the phone and the computer through the sync engine.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_zik/data/app_database.dart';
import 'package:my_zik/data/music_repository.dart';
import 'package:my_zik/models.dart';
import 'package:my_zik/providers/app_database_provider.dart';
import 'package:my_zik/providers/library_provider.dart';
import 'package:my_zik/providers/playback_provider.dart';
import 'package:my_zik/providers/shared_preferences_provider.dart';
import 'package:my_zik/providers/song_tags_provider.dart';
import 'package:my_zik/providers/sync_providers.dart';
import 'package:my_zik/sync/sync_store.dart';

import 'support/test_database.dart';

class _Repo implements MusicRepository {
  @override
  bool get isSupported => true;
  @override
  Future<bool> ensurePermission() async => true;
  @override
  Future<List<Song>> fetchSongs() async => const [
    Song(id: 1, title: 'trk01', artist: 'Unknown', contentKey: 'fp:one'),
    Song(id: 2, title: 'Second', artist: 'Band', contentKey: 'fp:two'),
    // No fingerprint yet: its key depends on its tags.
    Song(id: 3, title: 'Loose', artist: 'Band'),
  ];
  @override
  Future<Uint8List?> artworkFor(int id) async => null;
}

const _edited = SongTags(title: 'Opening', artist: 'The Band', album: 'Live');

/// Stands for a picture: covers are kept as they come when small.
final _cover = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  Future<ProviderContainer> device(
    AppDatabase database, {
    String id = 'phone',
  }) async {
    final covers = await Directory.systemTemp.createTemp('myzik_covers_$id');
    addTearDown(() => covers.delete(recursive: true));
    SharedPreferences.setMockInitialValues({});
    database.setSyncState('deviceId', id);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        appDatabaseProvider.overrideWithValue(database),
        musicRepositoryProvider.overrideWithValue(_Repo()),
        editedCoversDirectoryProvider.overrideWithValue(covers),
      ],
    );
    addTearDown(container.dispose);
    await container.read(libraryProvider.notifier).load();
    return container;
  }

  Song song(ProviderContainer c, int id) =>
      c.read(libraryProvider).songs.firstWhere((s) => s.id == id);

  test('the library shows edited tags, kept across restarts', () async {
    final database = await testDatabase();
    var phone = await device(database);
    phone.read(songTagsProvider.notifier).edit(song(phone, 1), _edited);

    final edited = song(phone, 1);
    expect(edited.tags, _edited);
    expect(edited.songKey, 'fp:one', reason: 'likes and playlists still match');
    expect(phone.read(hasEditedTagsProvider('fp:one')), isTrue);
    expect(song(phone, 2).title, 'Second');

    await database.flush();
    phone.dispose();
    phone = await device(database);
    expect(song(phone, 1).tags, _edited);
  });

  test('resetting brings back the file\'s tags', () async {
    final phone = await device(await testDatabase());
    final notifier = phone.read(songTagsProvider.notifier);
    notifier.edit(song(phone, 1), _edited);
    notifier.reset('fp:one');

    expect(song(phone, 1).title, 'trk01');
    expect(song(phone, 1).artist, 'Unknown');
    expect(phone.read(hasEditedTagsProvider('fp:one')), isFalse);
  });

  test('only songs whose key is not made of their tags can be edited', () {
    const loose = Song(id: 3, title: 'Loose', artist: 'Band');
    expect(loose.hasStableKey, isFalse);
    expect(
      const Song(
        id: 4,
        title: 'x',
        artist: 'y',
        youtubeVideoId: 'v',
      ).hasStableKey,
      isTrue,
    );
  });

  test('the playing track and its queue follow an edit', () async {
    final phone = await device(await testDatabase());
    final playback = phone.read(playbackProvider.notifier);
    await playback.playSong(song(phone, 1));

    phone.read(songTagsProvider.notifier).edit(song(phone, 1), _edited);

    final state = phone.read(playbackProvider);
    expect(state.current!.title, 'Opening');
    expect(state.queue.first.title, 'Opening');
    expect(state.currentIndex, 0);
    // Moving on still works on the updated queue.
    await playback.next();
    expect(phone.read(playbackProvider).current!.id, 2);
  });

  test('edits and resets travel between devices', () async {
    final phone = await device(await testDatabase());
    final computer = await device(await testDatabase(), id: 'computer');
    final phoneSync = phone.read(syncEngineProvider);
    final computerSync = computer.read(syncEngineProvider);

    Future<void> phoneToComputer() async {
      final out = await phoneSync.outgoing(0);
      await computerSync.incoming(out.records, publish: true);
    }

    phone.read(songTagsProvider.notifier).edit(song(phone, 1), _edited);
    await phoneToComputer();
    expect(song(computer, 1).tags, _edited);
    expect(
      computer.read(syncStoreProvider).recordOf(SyncIds.forTags('fp:one')),
      isNotNull,
    );

    phone.read(songTagsProvider.notifier).reset('fp:one');
    await phoneToComputer();
    expect(song(computer, 1).title, 'trk01');
    expect(computer.read(songTagsProvider), isEmpty);
  });

  test('the latest edit wins when both devices change a song', () async {
    final phone = await device(await testDatabase());
    final computer = await device(await testDatabase(), id: 'computer');

    phone.read(songTagsProvider.notifier).edit(song(phone, 2), _edited);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    const later = SongTags(title: 'Second (live)', artist: 'Band');
    computer.read(songTagsProvider.notifier).edit(song(computer, 2), later);

    final fromPhone = await phone.read(syncEngineProvider).outgoing(0);
    await computer
        .read(syncEngineProvider)
        .incoming(fromPhone.records, publish: true);
    final fromComputer = await computer.read(syncEngineProvider).outgoing(0);
    await phone
        .read(syncEngineProvider)
        .incoming(fromComputer.records, publish: false);

    expect(song(phone, 2).tags, later);
    expect(song(computer, 2).tags, later);
  });

  File? coverOf(Song song) {
    final url = song.artworkUrl;
    return url == null ? null : File(Uri.parse(url).toFilePath());
  }

  test("a picked cover replaces the file's, until reset", () async {
    final phone = await device(await testDatabase());
    final notifier = phone.read(songTagsProvider.notifier);
    expect(
      await notifier.save(
        song(phone, 1),
        title: 'Opening',
        artist: 'The Band',
        cover: _cover,
      ),
      isTrue,
    );

    final cover = coverOf(song(phone, 1))!;
    expect(cover.readAsBytesSync(), _cover);
    expect(cover.path, endsWith('.png'));

    // Editing the tags again keeps the cover.
    await notifier.save(song(phone, 1), title: 'Opening (live)', artist: 'X');
    expect(coverOf(song(phone, 1))!.path, cover.path);

    // Back to the file's cover: the picture goes.
    await notifier.save(
      song(phone, 1),
      title: 'Opening',
      artist: 'X',
      removeCover: true,
    );
    expect(song(phone, 1).artworkUrl, isNull);
    expect(cover.existsSync(), isFalse);

    await notifier.save(song(phone, 1), title: 'a', artist: 'b', cover: _cover);
    notifier.reset('fp:one');
    expect(song(phone, 1).artworkUrl, isNull);
    expect(song(phone, 1).title, 'trk01');
  });

  test('an empty title or artist is not saved', () async {
    final phone = await device(await testDatabase());
    final saved = await phone
        .read(songTagsProvider.notifier)
        .save(song(phone, 1), title: '  ', artist: 'Band');
    expect(saved, isFalse);
    expect(phone.read(songTagsProvider), isEmpty);
  });

  test('the cover travels to the other device', () async {
    final phone = await device(await testDatabase());
    final computer = await device(await testDatabase(), id: 'computer');
    await phone
        .read(songTagsProvider.notifier)
        .save(song(phone, 2), title: 'Second', artist: 'Band', cover: _cover);

    final out = await phone.read(syncEngineProvider).outgoing(0);
    await computer
        .read(syncEngineProvider)
        .incoming(out.records, publish: true);

    final cover = coverOf(song(computer, 2))!;
    expect(cover.readAsBytesSync(), _cover);
    expect(
      cover.uri.pathSegments.last,
      coverOf(song(phone, 2))!.uri.pathSegments.last,
      reason: 'named after the picture on both devices',
    );
  });

  test('the playing track shows a new cover', () async {
    final phone = await device(await testDatabase());
    await phone.read(playbackProvider.notifier).playSong(song(phone, 1));
    await phone
        .read(songTagsProvider.notifier)
        .save(song(phone, 1), title: 'trk01', artist: 'Unknown', cover: _cover);

    final current = phone.read(playbackProvider).current!;
    expect(current.artworkUrl, song(phone, 1).artworkUrl);
    expect(current.artworkUrl, isNotNull);
  });
}
