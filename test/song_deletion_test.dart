// Verifies deleting a song's file on a computer: the file goes, the library
// and the play queue drop it, and the device remembers it was deleted so
// syncing doesn't bring it back on its own.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_zik/data/music_repository.dart';
import 'package:my_zik/models.dart';
import 'package:my_zik/providers/app_database_provider.dart';
import 'package:my_zik/providers/library_provider.dart';
import 'package:my_zik/providers/playback_provider.dart';
import 'package:my_zik/providers/shared_preferences_provider.dart';
import 'package:my_zik/providers/song_deletion_provider.dart';

import 'support/test_database.dart';

class _FolderRepo implements MusicRepository {
  _FolderRepo(this.files);

  final List<File> files;

  @override
  bool get isSupported => true;
  @override
  Future<bool> ensurePermission() async => true;
  @override
  Future<List<Song>> fetchSongs() async => [
    for (var i = 0; i < files.length; i++)
      Song(
        id: i + 1,
        title: 'Song ${i + 1}',
        artist: 'Band',
        filePath: files[i].path,
        contentKey: 'fp:${i + 1}',
      ),
  ];
  @override
  Future<Uint8List?> artworkFor(int id) async => null;
}

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  late Directory dir;
  late List<File> files;
  late ProviderContainer container;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('myzik_delete_test');
    files = [
      for (var i = 1; i <= 3; i++)
        File('${dir.path}${Platform.pathSeparator}$i.mp3')
          ..writeAsBytesSync([i]),
    ];
    SharedPreferences.setMockInitialValues({});
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        appDatabaseProvider.overrideWithValue(await testDatabase()),
        musicRepositoryProvider.overrideWithValue(_FolderRepo(files)),
      ],
    );
    await container.read(libraryProvider.notifier).load();
  });
  tearDown(() async {
    container.dispose();
    await dir.delete(recursive: true);
  });

  List<int> libraryIds() => [
    for (final s in container.read(libraryProvider).songs) s.id,
  ];

  test('the file is deleted and the song leaves the library', () async {
    final deletion = container.read(songDeletionProvider);
    final song = container.read(libraryProvider).songs[1];
    expect(deletion.canDelete(song), isTrue);

    expect(await deletion.delete(song), isTrue);

    expect(files[1].existsSync(), isFalse);
    expect(libraryIds(), [1, 3]);
    expect(deletion.removedKeys, {'fp:2'});

    await deletion.restored('fp:2');
    expect(deletion.removedKeys, isEmpty);
  });

  test('a song without a file cannot be deleted', () {
    const stream = Song(id: 9, title: 'Stream', artist: 'Band');
    expect(container.read(songDeletionProvider).canDelete(stream), isFalse);
  });

  test('deleting a queued song takes it out of the queue', () async {
    final songs = container.read(libraryProvider).songs;
    final playback = container.read(playbackProvider.notifier);
    // Songs here have no uri: the queue is set without loading the player.
    await playback.playSong(songs[0]);

    await container.read(songDeletionProvider).delete(songs[2]);

    final state = container.read(playbackProvider);
    expect([for (final s in state.queue) s.id], [1, 2]);
    expect(state.current!.id, 1);
    expect(state.currentIndex, 0);
  });

  test('deleting the current song moves on to the next one', () async {
    final songs = container.read(libraryProvider).songs;
    final playback = container.read(playbackProvider.notifier);
    await playback.playSong(songs[1]);

    await container.read(songDeletionProvider).delete(songs[1]);

    final state = container.read(playbackProvider);
    expect([for (final s in state.queue) s.id], [1, 3]);
    expect(state.current!.id, 3);
    expect(state.currentIndex, 1);
  });
}
