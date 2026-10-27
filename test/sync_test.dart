import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_zik/data/song_key.dart';
import 'package:my_zik/sync/sync_client.dart';
import 'package:my_zik/sync/sync_engine.dart';
import 'package:my_zik/sync/sync_files.dart';
import 'package:my_zik/sync/sync_server.dart';
import 'package:my_zik/sync/sync_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App data kept in a map; ids in [found] were found by the app. [songs]
/// is the device's library: song key → metadata key.
class _MemoryData implements SyncData {
  final values = <String, Object>{};
  final found = <String>{};
  final songs = <String, String>{};

  @override
  Future<List<String>> aliases(String id, Object? value) async {
    final metadata = value is Map ? value['_songMetadata'] : null;
    if (!id.startsWith(SyncIds.lyrics) || metadata is! String) return const [];
    return [
      for (final MapEntry(key: key, value: songMetadata) in songs.entries)
        if (SyncIds.forLyrics(key) != id &&
            SongKey.sameRecording(songMetadata, metadata))
          SyncIds.forLyrics(key),
    ];
  }

  @override
  Future<Map<String, bool>> existing() async => {
    for (final id in values.keys) id: found.contains(id),
  };

  @override
  Future<Object?> read(String id) async => values[id];

  @override
  Future<void> apply(String id, Object? value, {required bool deleted}) async {
    if (deleted) {
      values.remove(id);
    } else {
      values[id] = value!;
    }
  }
}

/// Audio files: some of the device's own, plus those received.
class _FolderFiles implements SyncFiles {
  _FolderFiles(Directory root)
    : received = ReceivedTracksStore(
        Directory('${root.path}${Platform.pathSeparator}received'),
      );

  final ReceivedTracksStore received;
  final own = <TrackFile>[];
  final covers = <String, List<int>>{};

  @override
  Future<List<TrackFile>> localFiles() async => [
    ...own,
    ...await received.load(),
  ];

  @override
  Future<List<int>?> coverOf(TrackFile track) async {
    if (covers[track.songKey] case final cover?) return cover;
    final path =
        track.coverPath ??
        (await received.load())
            .where((t) => t.songKey == track.songKey)
            .firstOrNull
            ?.coverPath;
    return path == null ? null : File(path).readAsBytes();
  }

  @override
  Future<File> incomingFile(TrackFile track) async =>
      received.incomingFile(track);

  @override
  Future<void> receive(TrackFile track, File file, {List<int>? cover}) async {
    await received.add(track, file, cover: cover);
  }
}

/// A device: its journal, data and files.
class _Device {
  _Device(this.prefs, String prefix, Directory root, {int Function()? clock})
    : data = _MemoryData(),
      files = _FolderFiles(root) {
    store = SyncStore(prefs, keyPrefix: prefix, clock: clock);
    engine = SyncEngine(store, data);
  }

  final SharedPreferences prefs;
  final _MemoryData data;
  final _FolderFiles files;
  late final SyncStore store;
  late final SyncEngine engine;

  /// Changes [id] locally, as the app does; [found] for lyrics looked up
  /// online rather than made by the user.
  void set(String id, Object? value, {bool found = false}) {
    if (value == null) {
      data.values.remove(id);
      store.touch(id, deleted: true);
    } else {
      data.values[id] = value;
      store.touch(id, found: found);
    }
  }

  TrackFile ownFile(Directory root, String key, List<int> bytes) {
    final file = File('${root.path}${Platform.pathSeparator}$key.mp3')
      ..writeAsBytesSync(bytes);
    final track = TrackFile(
      songKey: key,
      title: 'Title $key',
      artist: 'Artist',
      size: bytes.length,
      extension: '.mp3',
      path: file.path,
    );
    files.own.add(track);
    return track;
  }
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('SyncStore', () {
    test('every change gets the next sequence number', () {
      var now = 1000;
      final store = SyncStore(prefs, clock: () => now);
      store.touch('like:a');
      store.touch('like:b');
      now = 900; // The clock went back: the change still moves forward.
      store.touch('like:a', deleted: true);

      final changes = store.changesSince(1);
      expect(changes.map((r) => r.id), ['like:b', 'like:a']);
      expect(changes.last.deleted, isTrue);
      expect(changes.last.updatedAt, 1001);
      expect(store.sequence, 3);

      // Persisted.
      final reloaded = SyncStore(prefs);
      expect(reloaded.deviceId, store.deviceId);
      expect(reloaded.recordOf('like:a')!.deleted, isTrue);
    });

    test('the last writer wins, ties broken by device', () {
      final store = SyncStore(prefs, clock: () => 500);
      store.touch('playlist:p');
      const older = SyncRecord(id: 'playlist:p', updatedAt: 400, origin: 'z');
      const newer = SyncRecord(id: 'playlist:p', updatedAt: 600, origin: 'a');
      expect(store.wins(older), isFalse);
      expect(store.wins(newer), isTrue);
      final tie = SyncRecord(
        id: 'playlist:p',
        updatedAt: 500,
        origin: '${store.deviceId}z',
      );
      expect(store.wins(tie), isTrue);
    });

    test('what the user made beats what was found, whatever the time', () {
      var now = 100;
      final store = SyncStore(prefs, clock: () => now);
      store.touch('lyrics:k');
      const laterFound = SyncRecord(
        id: 'lyrics:k',
        updatedAt: 999,
        origin: 'other',
        found: true,
      );
      expect(store.wins(laterFound), isFalse);

      now = 200;
      store.touch('lyrics:f', found: true);
      const earlierEdit = SyncRecord(id: 'lyrics:f', updatedAt: 1, origin: 'x');
      expect(store.wins(earlierEdit), isTrue);
      const laterLookup = SyncRecord(
        id: 'lyrics:f',
        updatedAt: 300,
        origin: 'x',
        found: true,
      );
      expect(store.wins(laterLookup), isTrue);
      expect(SyncStore(prefs).recordOf('lyrics:f')!.found, isTrue);
    });

    test('accepted remote changes are offered on only when published', () {
      final store = SyncStore(prefs);
      const remote = SyncRecord(id: 'like:x', updatedAt: 5, origin: 'other');
      store.accept(remote, publish: false);
      expect(store.changesSince(0), isEmpty);
      store.accept(
        const SyncRecord(id: 'like:y', updatedAt: 5, origin: 'other'),
        publish: true,
      );
      expect(store.changesSince(0).single.id, 'like:y');
    });

    test('unknown data is registered as the oldest change, known left', () {
      final store = SyncStore(prefs);
      store.touch('like:new');
      store.touch('like:gone', deleted: true);
      store.register({
        'like:new': false,
        'like:old': false,
        'like:gone': false,
      });
      expect(store.recordOf('like:old')!.updatedAt, 1);
      expect(store.recordOf('like:new')!.updatedAt, greaterThan(1));
      // A deletion stays a deletion.
      expect(store.recordOf('like:gone')!.deleted, isTrue);
      // Registering runs again later, for data stored without a record.
      store.register({'lyrics:k': true});
      expect(store.recordOf('lyrics:k')!.found, isTrue);
    });
  });

  group('desktop and phone', () {
    late Directory root;
    late _Device desktop;
    late _Device phone;
    late SyncServer server;
    late SyncClient client;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('myzik_sync_');
      final desktopDir = Directory('${root.path}/desktop')..createSync();
      final phoneDir = Directory('${root.path}/phone')..createSync();
      desktop = _Device(prefs, 'desktop.', desktopDir);
      phone = _Device(prefs, 'phone.', phoneDir);
      server = SyncServer(
        engine: desktop.engine,
        files: desktop.files,
        preferences: prefs,
        name: 'Desk',
        port: 0,
      );
      await server.start(address: InternetAddress.loopbackIPv4);
      client = SyncClient(
        engine: phone.engine,
        files: phone.files,
        preferences: prefs,
      );
    });

    tearDown(() async {
      client.close();
      await server.dispose();
      await root.delete(recursive: true);
    });

    Future<PairingPayload> openPairing() async => PairingPayload(
      serverId: server.serverId,
      serverName: server.name,
      hosts: ['127.0.0.1'],
      port: server.boundPort!,
      code: server.startPairing().code,
    );

    test('pairing needs the code, once, and can be revoked', () async {
      final payload = await openPairing();
      final wrong = PairingPayload(
        serverId: payload.serverId,
        serverName: payload.serverName,
        hosts: payload.hosts,
        port: payload.port,
        code: payload.code == '000000' ? '111111' : '000000',
      );
      await expectLater(
        client.pair(wrong, deviceName: 'Phone'),
        throwsA(isA<SyncException>()),
      );

      final connection = await client.pair(payload, deviceName: 'Phone');
      expect(connection.serverName, 'Desk');
      expect(server.devices.single.name, 'Phone');
      // The window closed with the pairing.
      await expectLater(
        SyncClient(
          engine: SyncEngine(SyncStore(prefs, keyPrefix: 'x.'), _MemoryData()),
          files: phone.files,
          preferences: prefs,
        ).pair(payload, deviceName: 'Other'),
        throwsA(isA<SyncException>()),
      );

      await client.sync();
      server.revoke(server.devices.single.id);
      await expectLater(
        client.sync(),
        throwsA(
          isA<SyncException>().having((e) => e.unpaired, 'unpaired', isTrue),
        ),
      );
    });

    test('changes flow both ways and the latest one wins', () async {
      desktop.data.values['like:old-desktop'] = {};
      phone.data.values['like:old-phone'] = {};
      await client.pair(await openPairing(), deviceName: 'Phone');

      desktop.set('playlist:p', {
        'name': 'Desk mix',
        'songKeys': ['fp:1'],
      });
      phone.set('lyrics:fp:9', {'plain': 'Words'});
      var report = await client.sync();
      // Data from before synchronization merged on both sides.
      for (final device in [desktop, phone]) {
        expect(
          device.data.values.keys,
          containsAll([
            'like:old-desktop',
            'like:old-phone',
            'playlist:p',
            'lyrics:fp:9',
          ]),
        );
      }
      expect(report.received, 2);

      // Nothing changed: nothing moves.
      report = await client.sync();
      expect((report.sent, report.received), (0, 0));

      // The phone renames later than the desktop: the phone's name wins.
      desktop.set('playlist:p', {'name': 'Desk rename', 'songKeys': []});
      await Future<void>.delayed(const Duration(milliseconds: 5));
      phone.set('playlist:p', {'name': 'Phone rename', 'songKeys': []});
      phone.set('like:old-desktop', null);
      await client.sync();
      expect(
        (desktop.data.values['playlist:p'] as Map)['name'],
        'Phone rename',
      );
      expect((phone.data.values['playlist:p'] as Map)['name'], 'Phone rename');
      expect(desktop.data.values.containsKey('like:old-desktop'), isFalse);
    });

    test('lyrics found online never replace lyrics timed by hand', () async {
      await client.pair(await openPairing(), deviceName: 'Phone');
      final timed = {
        'source': 'manual',
        'edited': true,
        'lines': [
          {'t': 1000, 'x': 'Hand-timed line'},
        ],
      };
      phone.set('lyrics:fp:1', timed);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      // Later, the desktop looks the same song up online.
      desktop.set('lyrics:fp:1', {
        'source': 'lrclib',
        'plain': 'Found',
      }, found: true);
      desktop.set('lyrics:fp:2', {
        'source': 'lrclib',
        'plain': 'Other',
      }, found: true);

      await client.sync();

      expect(desktop.data.values['lyrics:fp:1'], timed);
      expect(phone.data.values['lyrics:fp:1'], timed);
      // Found lyrics still travel when there is nothing better.
      expect((phone.data.values['lyrics:fp:2'] as Map)['plain'], 'Other');
    });

    test('lyrics stored without a record still travel', () async {
      await client.pair(await openPairing(), deviceName: 'Phone');
      await client.sync();
      // Cached by a version of the app that didn't record lyrics.
      desktop.data.values['lyrics:fp:old'] = {'plain': 'Old cache'};
      desktop.data.found.add('lyrics:fp:old');

      await client.sync();

      expect(phone.data.values['lyrics:fp:old'], {'plain': 'Old cache'});
    });

    test('lyrics reach the same recording under another key', () async {
      await client.pair(await openPairing(), deviceName: 'Phone');
      const metadata = 'artist|song|200';
      desktop.data.songs['fp:desk'] = metadata;
      // The phone's copy has other tags: another fingerprint, and lyrics
      // found online (or nothing) under its own key.
      phone.data.songs['fp:phone'] = 'artist|song|201';
      phone.set('lyrics:fp:phone', {
        'plain': 'Found',
        '_songMetadata': 'artist|song|201',
      }, found: true);
      final timed = {
        'source': 'manual',
        'lines': [
          {'t': 1500, 'x': 'Timed'},
        ],
        '_songMetadata': metadata,
      };
      desktop.set('lyrics:fp:desk', timed);

      await client.sync();

      // Shown on the phone under its own key: hand-timed beats found.
      expect(phone.data.values['lyrics:fp:phone'], timed);
      expect(phone.data.values['lyrics:fp:desk'], timed);
      // And the phone's found lyrics don't overwrite the desktop's timing.
      expect(desktop.data.values['lyrics:fp:desk'], timed);
    });

    test('covers travel with the files, both ways', () async {
      final desktopDir = Directory('${root.path}/desktop');
      final phoneDir = Directory('${root.path}/phone');
      desktop.ownFile(desktopDir, 'yt:video', [1, 2, 3]);
      desktop.files.covers['yt:video'] = [0xFF, 0xD8, 9, 9];
      phone.ownFile(phoneDir, 'fp:phone', [4, 5, 6]);
      phone.files.covers['fp:phone'] = [0x89, 0x50, 7];
      desktop.ownFile(desktopDir, 'fp:bare', [8]);
      await client.pair(await openPairing(), deviceName: 'Phone');

      await client.sync(mode: TransferMode.everything);

      final onPhone = {
        for (final t in await phone.files.received.load()) t.songKey: t,
      };
      final cover = onPhone['yt:video']!.coverPath!;
      expect(File(cover).readAsBytesSync(), [0xFF, 0xD8, 9, 9]);
      expect(
        onPhone['yt:video']!.toSong().artworkUrl,
        Uri.file(cover).toString(),
      );
      expect(onPhone['fp:bare']!.coverPath, isNull);
      final onDesktop = (await desktop.files.received.load()).single;
      expect(File(onDesktop.coverPath!).readAsBytesSync(), [0x89, 0x50, 7]);
    });

    test('audio files transfer both ways, keep their key and resume', () async {
      final desktopDir = Directory('${root.path}/desktop');
      final phoneDir = Directory('${root.path}/phone');
      final song = List<int>.generate(300000, (i) => i % 251);
      desktop.ownFile(desktopDir, 'fp:desk', song);
      desktop.ownFile(desktopDir, 'yt:video', [1, 2, 3]);
      final phoneSong = phone.ownFile(phoneDir, 'fp:phone', [4, 5, 6, 7]);
      await client.pair(await openPairing(), deviceName: 'Phone');

      final missing = await client.differences();
      expect(missing.toDownload.map((f) => f.songKey), ['fp:desk', 'yt:video']);
      expect(missing.toUpload.map((f) => f.songKey), ['fp:phone']);
      expect(
        missing.only(TransferMode.downloads).toDownload.single.songKey,
        'yt:video',
      );

      // An interrupted download left half of the file behind.
      final desk = missing.toDownload.first;
      final part = await phone.files.incomingFile(desk);
      part
        ..createSync(recursive: true)
        ..writeAsBytesSync(song.sublist(0, 120000));

      final report = await client.sync(mode: TransferMode.everything);
      expect(
        (report.downloaded, report.uploaded, report.failedFiles),
        (2, 1, 0),
      );

      final received = {
        for (final t in await phone.files.received.load()) t.songKey: t,
      };
      expect(File(received['fp:desk']!.path!).readAsBytesSync(), song);
      expect(received['yt:video']!.toSong().songKey, 'yt:video');
      final onDesktop = (await desktop.files.received.load()).single;
      expect(onDesktop.songKey, 'fp:phone');
      expect(
        File(onDesktop.path!).readAsBytesSync(),
        File(phoneSong.path!).readAsBytesSync(),
      );

      // Everything is on both sides now.
      final after = await client.differences();
      expect(after.toDownload, isEmpty);
      expect(after.toUpload, isEmpty);
    });

    test(
      'over USB the phone reaches the computer at its own address',
      () async {
        // The QR code's Wi-Fi address is unreachable: only the cable works,
        // as `adb reverse` makes the phone's 127.0.0.1 lead to the computer.
        final payload = await openPairing();
        final overCable = PairingPayload(
          serverId: payload.serverId,
          serverName: payload.serverName,
          hosts: ['192.0.2.1'],
          port: payload.port,
          code: payload.code,
        );
        client.transport = SyncTransport.usb;
        final connection = await client.pair(overCable, deviceName: 'Phone');
        expect(connection.hosts, ['192.0.2.1']);
        expect(connection.lastHost, isNull);

        phone.set('like:fp:1', {});
        final report = await client.sync();
        expect(report.sent, greaterThan(0));
        expect(desktop.data.values.keys, contains('like:fp:1'));

        await server.stop();
        await expectLater(
          client.sync(),
          throwsA(
            isA<SyncException>().having(
              (e) => e.message,
              'message',
              contains('USB'),
            ),
          ),
        );
      },
    );

    test('the payload round-trips through the QR code text', () async {
      final payload = await openPairing();
      final decoded = PairingPayload.tryDecode(payload.encode())!;
      expect(decoded.code, payload.code);
      expect(decoded.hosts, payload.hosts);
      expect(PairingPayload.tryDecode(jsonEncode({'app': 'other'})), isNull);
      expect(PairingPayload.tryDecode('not json'), isNull);
    });
  });
}
