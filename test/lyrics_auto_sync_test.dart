import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_zik/data/lyrics_repository.dart';
import 'package:my_zik/models.dart';

void main() {
  const lyrics = Lyrics(
    source: LyricsSource.web,
    plain: 'Hello there\n\nGood night',
  );
  late Directory directory;
  late File audio;
  late List<RequestOptions> requests;
  late LyricsRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('myzik_auto_sync_');
    audio = await File('${directory.path}/track.m4a').writeAsBytes([0, 1, 2]);
    requests = [];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'text': 'hello there good night',
                  'words': [
                    {'word': 'Hello', 'start': 1.0, 'end': 1.4},
                    {'word': 'there', 'start': 1.4, 'end': 1.8},
                    {'word': 'good', 'start': 4.0, 'end': 4.4},
                    {'word': 'night', 'start': 4.4, 'end': 4.8},
                  ],
                },
              ),
            );
          },
        ),
      );
    repository = LyricsRepository(
      dio: dio,
      apiKey: 'test-key',
      cacheDirectory: () async => directory,
    );
  });

  tearDown(() => directory.delete(recursive: true));

  test('streamed tracks are never offered auto-sync', () {
    const streamed = Song(
      id: -5,
      title: 'Song',
      artist: 'Artist',
      uri: 'https://example.org/stream',
    );
    expect(repository.canAutoSynchronize(streamed, lyrics), isFalse);
    expect(
      repository.autoSynchronize(streamed, lyrics),
      throwsA(isA<LyricsException>()),
    );
    expect(requests, isEmpty);
  });

  test('times the lyrics from Whisper word timestamps', () async {
    final song = Song(
      id: 1,
      title: 'Song',
      artist: 'Artist',
      filePath: audio.path,
    );
    expect(repository.canAutoSynchronize(song, lyrics), isTrue);

    final alignment = await repository.autoSynchronize(song, lyrics);

    expect(alignment.confidence, 1.0);
    expect(alignment.lines.map((l) => (l.time.inMilliseconds, l.text)), [
      (1000, 'Hello there'),
      (4000, 'Good night'),
    ]);
    final request = requests.single;
    expect(request.path, endsWith('/audio/transcriptions'));
    final fields = Map.fromEntries((request.data as FormData).fields);
    expect(fields['model'], 'whisper-large-v3');
    expect(fields['timestamp_granularities[]'], 'word');
  });
}
