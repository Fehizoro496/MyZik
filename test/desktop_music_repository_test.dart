import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_zik/data/desktop_music_repository.dart';
import 'package:my_zik/data/sample_music_repository.dart';
import 'package:my_zik/providers/library_folders_provider.dart';
import 'package:my_zik/providers/library_provider.dart';
import 'package:my_zik/providers/shared_preferences_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [seconds] of silent 16-bit mono WAV, tagged with a RIFF INFO chunk when
/// [title] is given.
Uint8List _wav(int seconds, {String? title, String? artist}) {
  const rate = 8000;
  final bytes = BytesBuilder();
  void ascii(String text) => bytes.add(text.codeUnits);
  void u32(int value) => bytes.add(
    (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List(),
  );
  void u16(int value) => bytes.add(
    (ByteData(2)..setUint16(0, value, Endian.little)).buffer.asUint8List(),
  );

  final info = BytesBuilder();
  void field(String id, String value) {
    final text = [...value.codeUnits, 0];
    info.add(id.codeUnits);
    info.add(
      (ByteData(
        4,
      )..setUint32(0, text.length, Endian.little)).buffer.asUint8List(),
    );
    info.add([...text, if (text.length.isOdd) 0]);
  }

  if (title != null) {
    field('INAM', title);
    field('IART', artist ?? '');
    field('IPRD', 'Album');
    field('ITRK', '2');
  }
  final tags = info.toBytes();
  final pcm = seconds * rate * 2;
  ascii('RIFF');
  u32(4 + 24 + 8 + pcm + (tags.isEmpty ? 0 : 12 + tags.length));
  ascii('WAVE');
  ascii('fmt ');
  u32(16);
  u16(1); // PCM
  u16(1); // mono
  u32(rate);
  u32(rate * 2);
  u16(2);
  u16(16);
  ascii('data');
  u32(pcm);
  bytes.add(Uint8List(pcm));
  if (tags.isNotEmpty) {
    ascii('LIST');
    u32(4 + tags.length);
    ascii('INFO');
    bytes.add(tags);
  }
  return bytes.toBytes();
}

File _audio(
  Directory dir,
  String name, {
  int seconds = 1,
  String? title,
  String? artist,
}) {
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  file.parent.createSync(recursive: true);
  return file..writeAsBytesSync(_wav(seconds, title: title, artist: artist));
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('myzik_library_');
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => root.delete(recursive: true));

  String sub(String name) => '${root.path}${Platform.pathSeparator}$name';

  test('scans folders recursively, reads tags, falls back to file names', () {
    _audio(
      root,
      'a${Platform.pathSeparator}one.wav',
      title: 'Tagged title',
      artist: 'Some artist',
    );
    _audio(
      root,
      'a${Platform.pathSeparator}deep${Platform.pathSeparator}'
      'Untagged Song.wav',
    );
    File(sub('notes.txt')).writeAsStringSync('not audio');

    // Overlapping folders still list each file once.
    final scan = scanLibrary([root.path, sub('a')], const {});

    expect(scan.changed, isTrue);
    expect(scan.tracks, hasLength(2));
    final byTitle = {for (final t in scan.tracks) t.title: t};
    final song = byTitle['Tagged title']!;
    expect(song.artist, 'Some artist');
    expect(song.album, 'Album');
    expect(song.trackNumber, 2);
    expect(song.duration, const Duration(seconds: 1));
    final untagged = byTitle['Untagged Song']!;
    expect(untagged.artist, 'Unknown artist');
    expect(untagged.album, isNull);
    // Sorted by artist: "Some artist" before "Unknown artist".
    expect(scan.tracks.first.title, 'Tagged title');
  });

  test('unreadable folders are skipped', () {
    _audio(root, 'song.wav');
    final scan = scanLibrary([sub('missing'), root.path], const {});
    expect(scan.tracks.single.title, 'song');
  });

  group('DesktopMusicRepository', () {
    late Directory support;

    setUp(() async {
      support = await Directory.systemTemp.createTemp('myzik_support_');
    });
    tearDown(() => support.delete(recursive: true));

    Future<DesktopMusicRepository> repository(List<String> folders) async {
      SharedPreferences.setMockInitialValues({
        DesktopMusicRepository.foldersPreference: folders,
      });
      return DesktopMusicRepository(
        preferences: await SharedPreferences.getInstance(),
        indexDirectory: () async => support,
      );
    }

    File index() =>
        File('${support.path}${Platform.pathSeparator}library_index.json');

    test('without a folder, the library is empty', () async {
      final repo = await repository(const []);
      expect(await repo.ensurePermission(), isTrue);
      expect(await repo.fetchSongs(), isEmpty);
      expect(index().existsSync(), isFalse);
    });

    test('songs are playable files with stable ids', () async {
      final file = _audio(root, 'track.wav');
      final repo = await repository([root.path]);

      final song = (await repo.fetchSongs()).single;

      expect(song.filePath, file.path);
      expect(song.uri, Uri.file(file.path).toString());
      expect(song.id, songIdForPath(file.path));
      expect(song.id, greaterThan(0));
      expect(await repo.artworkFor(song.id), isNull);
      expect(await repo.artworkFor(-1), isNull);
    });

    test('a rescan reuses the index and rereads only changed files', () async {
      final kept = _audio(root, 'kept.wav');
      final changed = _audio(root, 'changed.wav');
      final gone = _audio(root, 'gone.wav');
      final repo = await repository([root.path]);
      expect(await repo.fetchSongs(), hasLength(3));
      expect(index().existsSync(), isTrue);

      // Mark the indexed entries: an unchanged file keeps its entry.
      final entries = jsonDecode(index().readAsStringSync()) as List;
      for (final entry in entries.cast<Map<String, dynamic>>()) {
        entry['title'] = 'From the index';
      }
      index().writeAsStringSync(jsonEncode(entries));
      changed.writeAsBytesSync(_wav(2));
      gone.deleteSync();

      final titles = {
        for (final song in await repo.fetchSongs()) song.filePath: song.title,
      };

      expect(titles, {kept.path: 'From the index', changed.path: 'changed'});
    });
  });

  test('music folders persist, skip nested ones and rescan', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        musicRepositoryProvider.overrideWithValue(SampleMusicRepository()),
      ],
    );
    addTearDown(container.dispose);
    final folders = container.read(libraryFoldersProvider.notifier);

    await folders.add(root.path);
    await folders.add(sub('inside'));
    expect(container.read(libraryFoldersProvider), [root.path]);
    expect(prefs.getStringList(DesktopMusicRepository.foldersPreference), [
      root.path,
    ]);
    expect(container.read(libraryProvider).status, LibraryStatus.ready);

    await folders.remove(root.path);
    expect(container.read(libraryFoldersProvider), isEmpty);
  });
}
