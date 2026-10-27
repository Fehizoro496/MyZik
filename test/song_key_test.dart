import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_zik/data/song_key.dart';
import 'package:my_zik/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}
