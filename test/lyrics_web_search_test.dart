import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_zik/data/lyrics_repository.dart';
import 'package:my_zik/models.dart';

void main() {
  const song = Song(
    id: 42,
    title: 'Artist - Example (Official Video) feat. Guest',
    artist: 'UploaderVEVO',
  );
  late Directory directory;
  late LyricsRepository repository;
  late Map<String, dynamic> response;
  late List<RequestOptions> requests;

  Map<String, dynamic> completion(
    Object answer, {
    String finish = 'stop',
    bool searched = true,
  }) => {
    'choices': [
      {
        'finish_reason': finish,
        'message': {
          'content': answer is String ? answer : jsonEncode(answer),
          if (searched)
            'executed_tools': [
              {'type': 'browser_search'},
            ],
        },
      },
    ],
  };

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('myzik_lyrics_test_');
    requests = [];
    response = completion({
      'found': true,
      'status': 'found',
      'lyrics': 'A fictional test line',
      'source': 'https://example.org/song',
    });
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: options.method == 'POST' ? response : <dynamic>[],
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

  tearDown(() async => directory.delete(recursive: true));

  test(
    'search uses clean hints and preserves original recording metadata',
    () async {
      final result = await repository.find(song);
      expect(result?.sourceUrl, 'https://example.org/song');
      final request = requests.singleWhere((r) => r.method == 'POST');
      final body = request.data as Map;
      final messages = body['messages'] as List;
      final context = jsonDecode(messages.last['content'] as String) as Map;
      expect(context['normalized'], {'title': 'Example', 'artist': 'Artist'});
      expect(context['original']['title'], song.title);
      expect(context['suggested_queries'].first, '"Example" "Artist" lyrics');
      expect(body['tool_choice'], 'auto');
      await repository.find(song);
      expect(requests.where((r) => r.method == 'POST'), hasLength(1));
    },
  );

  test(
    'only explicit not_found results suppress subsequent web searches',
    () async {
      response = completion({
        'found': false,
        'status': 'not_found',
        'lyrics': '',
        'source': '',
      });
      expect(await repository.find(song), isNull);
      expect(await repository.find(song), isNull);
      expect(requests.where((r) => r.method == 'POST'), hasLength(1));
      await repository.find(song, refresh: true);
      expect(requests.where((r) => r.method == 'POST'), hasLength(2));
    },
  );

  for (final entry in <String, Object>{
    'malformed JSON': 'not JSON',
    'blocked page': {
      'found': false,
      'status': 'unavailable',
      'lyrics': '',
      'source': '',
    },
    'invalid source': {
      'found': true,
      'status': 'found',
      'lyrics': 'test',
      'source': 'javascript:alert(1)',
    },
    'wrong field type': {
      'found': true,
      'status': 'found',
      'lyrics': 42,
      'source': 'https://example.org',
    },
    'missing status': {'found': false, 'lyrics': '', 'source': ''},
  }.entries) {
    test('${entry.key} remains retryable without repeating LRCLIB', () async {
      response = completion(entry.value);
      await expectLater(repository.find(song), throwsA(isA<LyricsException>()));
      final getCount = requests.where((r) => r.method == 'GET').length;
      await expectLater(repository.find(song), throwsA(isA<LyricsException>()));
      expect(requests.where((r) => r.method == 'GET'), hasLength(getCount));
      expect(requests.where((r) => r.method == 'POST'), hasLength(2));
    });
  }

  test('answers given without searching are not trusted', () async {
    response = completion({
      'found': false,
      'status': 'not_found',
      'lyrics': '',
      'source': '',
    }, searched: false);
    await expectLater(repository.find(song), throwsA(isA<LyricsException>()));
    await expectLater(repository.find(song), throwsA(isA<LyricsException>()));
    expect(requests.where((r) => r.method == 'POST'), hasLength(2));
  });

  test('truncated completion is not cached as a miss', () async {
    response = completion({
      'found': false,
      'status': 'not_found',
      'lyrics': '',
      'source': '',
    }, finish: 'length');
    await expectLater(repository.find(song), throwsA(isA<LyricsException>()));
  });

  test('legacy web misses retry with the new search strategy', () async {
    final cache = Directory('${directory.path}/lyrics');
    await cache.create();
    await File('${cache.path}/42.json').writeAsString(
      jsonEncode({
        'miss': true,
        'web': true,
        'at': DateTime.now().millisecondsSinceEpoch,
      }),
    );
    expect(await repository.find(song), isNotNull);
    expect(requests, hasLength(1));
    expect(requests.single.method, 'POST');
  });
}
