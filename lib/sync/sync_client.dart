import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'sync_discovery.dart';
import 'sync_engine.dart';
import 'sync_files.dart';
import 'sync_server.dart' show PairingPayload;
import 'sync_store.dart';
import 'usb_bridge.dart' show UsbBridge;

/// Which audio files a sync transfers on its own.
enum TransferMode {
  /// None: files move only when picked by hand.
  off,

  /// Tracks downloaded from YouTube.
  downloads,

  /// Every file missing on the other side.
  everything,
}

/// How the phone reaches the computer.
enum SyncTransport {
  /// The local network: the computer's last address, mDNS, then the QR
  /// code's addresses.
  wifi,

  /// A USB cable: the computer forwards the phone's own `127.0.0.1` to its
  /// server with `adb reverse` (Android, with USB debugging on).
  usb,
}

/// The computer this phone is paired with.
class SyncConnection {
  const SyncConnection({
    required this.serverId,
    required this.serverName,
    required this.hosts,
    required this.port,
    required this.token,
    this.lastHost,
  });

  final String serverId;
  final String serverName;

  /// Addresses from the QR code.
  final List<String> hosts;
  final int port;
  final String token;

  /// The address that answered last time, tried first.
  final String? lastHost;

  SyncConnection reachedAt(String host, int port) => SyncConnection(
    serverId: serverId,
    serverName: serverName,
    hosts: hosts,
    port: port,
    token: token,
    lastHost: host,
  );

  Map<String, dynamic> toJson() => {
    'serverId': serverId,
    'serverName': serverName,
    'hosts': hosts,
    'port': port,
    'token': token,
    if (lastHost != null) 'lastHost': lastHost,
  };

  static SyncConnection? tryFromJson(Object? json) {
    if (json is! Map) return null;
    try {
      return SyncConnection(
        serverId: json['serverId'] as String,
        serverName: json['serverName'] as String,
        hosts: [for (final h in json['hosts'] as List) h as String],
        port: json['port'] as int,
        token: json['token'] as String,
        lastHost: json['lastHost'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Why a sync or a pairing failed, worded for the user.
class SyncException implements Exception {
  const SyncException(this.message, {this.unpaired = false});

  final String message;

  /// The computer no longer knows this phone (it was revoked).
  final bool unpaired;

  @override
  String toString() => message;
}

/// Where a sync is at, for a progress indicator.
class SyncProgress {
  const SyncProgress(this.stage, {this.done = 0, this.total = 0, this.track});

  final String stage;
  final int done;
  final int total;
  final TrackFile? track;
}

/// What a sync did.
class SyncReport {
  const SyncReport({
    this.sent = 0,
    this.received = 0,
    this.downloaded = 0,
    this.uploaded = 0,
    this.failedFiles = 0,
  });

  /// Records sent and applied from the computer.
  final int sent;
  final int received;

  /// Files received from and sent to the computer.
  final int downloaded;
  final int uploaded;
  final int failedFiles;

  SyncReport plus(SyncReport other) => SyncReport(
    sent: sent + other.sent,
    received: received + other.received,
    downloaded: downloaded + other.downloaded,
    uploaded: uploaded + other.uploaded,
    failedFiles: failedFiles + other.failedFiles,
  );
}

/// Files only one side has.
class FileDifferences {
  const FileDifferences({required this.toDownload, required this.toUpload});

  /// On the computer, not on this phone.
  final List<TrackFile> toDownload;

  /// On this phone, not on the computer.
  final List<TrackFile> toUpload;

  FileDifferences only(TransferMode mode) => switch (mode) {
    TransferMode.off => const FileDifferences(toDownload: [], toUpload: []),
    TransferMode.everything => this,
    TransferMode.downloads => FileDifferences(
      toDownload: [
        for (final f in toDownload)
          if (f.isDownload) f,
      ],
      toUpload: [
        for (final f in toUpload)
          if (f.isDownload) f,
      ],
    ),
  };
}

/// The phone's side of synchronization: pairs with a computer running
/// [SyncServer], then exchanges records and audio files with it.
class SyncClient {
  SyncClient({
    required this.engine,
    required this.files,
    required SharedPreferences preferences,
    this.discovery,
    HttpClient? http,
  }) : _prefs = preferences,
       _http = http ?? HttpClient()
         ..connectionTimeout = const Duration(seconds: 4);

  final SyncEngine engine;
  final SyncFiles files;
  final SharedPreferences _prefs;
  final SyncDiscovery? discovery;
  final HttpClient _http;

  /// How the computer is reached, for pairing and every sync.
  SyncTransport transport = SyncTransport.wifi;

  String get _stateKey => '${store.keyPrefix}sync.client.v1';

  SyncStore get store => engine.store;

  /// The paired computer, or null.
  SyncConnection? get connection =>
      SyncConnection.tryFromJson(_state['connection']);

  DateTime? get lastSyncAt => switch (_state['lastSyncAt']) {
    final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
    _ => null,
  };

  int get _pullCursor => _state['pull'] as int? ?? 0;
  int get _pushCursor => _state['push'] as int? ?? 0;

  Map<String, dynamic> get _state {
    try {
      return jsonDecode(_prefs.getString(_stateKey) ?? '{}')
          as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  void _update(Map<String, dynamic> changes) =>
      _prefs.setString(_stateKey, jsonEncode({..._state, ...changes}));

  /// Pairs with the computer described by [payload] (from its QR code).
  Future<SyncConnection> pair(
    PairingPayload payload, {
    required String deviceName,
  }) async {
    SyncException? failure;
    final hosts = transport == SyncTransport.usb
        ? const [UsbBridge.phoneHost]
        : payload.hosts;
    for (final host in hosts) {
      final base = Uri(scheme: 'http', host: host, port: payload.port);
      try {
        final reply = await _request(
          'POST',
          base.resolve('/api/pair'),
          body: {
            'code': payload.code,
            'deviceId': store.deviceId,
            'name': deviceName,
          },
        );
        final connection = SyncConnection(
          serverId: reply['serverId'] as String,
          serverName: reply['serverName'] as String,
          hosts: payload.hosts,
          port: payload.port,
          token: reply['token'] as String,
          lastHost: transport == SyncTransport.usb ? null : host,
        );
        // A new computer: start its exchange from scratch.
        _prefs.setString(
          _stateKey,
          jsonEncode({'connection': connection.toJson()}),
        );
        return connection;
      } on SyncException catch (e) {
        failure = e;
        // Refused by the computer: other addresses won't do better.
        if (!e.message.startsWith('Could not reach')) rethrow;
      }
    }
    if (transport == SyncTransport.usb && failure != null) {
      throw const SyncException(_usbUnreachable);
    }
    throw failure ??
        const SyncException('The pairing code has no address to reach.');
  }

  /// Forgets the paired computer on this phone.
  void unpair() => _prefs.remove(_stateKey);

  /// Exchanges records with the computer, then transfers the files [mode]
  /// asks for.
  Future<SyncReport> sync({
    TransferMode mode = TransferMode.off,
    void Function(SyncProgress progress)? onProgress,
  }) async {
    onProgress?.call(const SyncProgress('Looking for your computer…'));
    final base = await _resolve();
    onProgress?.call(const SyncProgress('Syncing likes, playlists, lyrics…'));
    final out = await engine.outgoing(_pushCursor);
    final reply = await _request(
      'POST',
      base.resolve('/api/sync'),
      body: {
        'since': _pullCursor,
        'changes': [for (final r in out.records) r.toJson()],
      },
    );
    final incoming = [
      for (final json in reply['changes'] as List? ?? const [])
        ?SyncRecord.tryFromJson(json),
    ];
    final applied = await engine.incoming(incoming, publish: false);
    _update({
      'pull': reply['cursor'] as int? ?? _pullCursor,
      'push': out.cursor,
      'lastSyncAt': DateTime.now().millisecondsSinceEpoch,
    });
    var report = SyncReport(sent: out.records.length, received: applied.length);
    if (mode != TransferMode.off) {
      final missing = (await _differences(base)).only(mode);
      report = report.plus(
        await _transfer(base, missing, onProgress: onProgress),
      );
    }
    return report;
  }

  /// Files only one side has, to pick from by hand.
  Future<FileDifferences> differences() async => _differences(await _resolve());

  /// Transfers the picked files.
  Future<SyncReport> transfer(
    FileDifferences picked, {
    void Function(SyncProgress progress)? onProgress,
  }) async => _transfer(await _resolve(), picked, onProgress: onProgress);

  Future<FileDifferences> _differences(Uri base) async {
    final reply = await _request('GET', base.resolve('/api/files'));
    final remote = [
      for (final json in reply['files'] as List? ?? const [])
        ?TrackFile.tryFromJson(json),
    ];
    final local = await files.localFiles();
    final localKeys = {for (final f in local) f.songKey};
    final remoteKeys = {for (final f in remote) f.songKey};
    return FileDifferences(
      toDownload: [
        for (final f in remote)
          if (!localKeys.contains(f.songKey)) f,
      ],
      toUpload: [
        for (final f in local)
          if (!remoteKeys.contains(f.songKey)) f,
      ],
    );
  }

  Future<SyncReport> _transfer(
    Uri base,
    FileDifferences picked, {
    void Function(SyncProgress progress)? onProgress,
  }) async {
    final total = picked.toDownload.length + picked.toUpload.length;
    var done = 0, downloaded = 0, uploaded = 0, failed = 0;
    for (final track in picked.toDownload) {
      onProgress?.call(
        SyncProgress('Receiving', done: done, total: total, track: track),
      );
      try {
        await _download(base, track);
        downloaded++;
      } on SyncException catch (e) {
        if (e.unpaired) rethrow;
        failed++;
      } catch (_) {
        failed++;
      }
      done++;
    }
    for (final track in picked.toUpload) {
      onProgress?.call(
        SyncProgress('Sending', done: done, total: total, track: track),
      );
      try {
        await _upload(base, track);
        uploaded++;
      } on SyncException catch (e) {
        if (e.unpaired) rethrow;
        failed++;
      } catch (_) {
        failed++;
      }
      done++;
    }
    return SyncReport(
      downloaded: downloaded,
      uploaded: uploaded,
      failedFiles: failed,
    );
  }

  /// Fetches [track] into its partial file, resuming where a previous
  /// attempt stopped, and adds it to the library once complete.
  Future<void> _download(Uri base, TrackFile track) async {
    final part = await files.incomingFile(track);
    await part.parent.create(recursive: true);
    var offset = part.existsSync() ? await part.length() : 0;
    if (offset > track.size) {
      await part.delete();
      offset = 0;
    }
    if (offset < track.size) {
      final request = await _open(
        'GET',
        base.resolve('/api/files/${Uri.encodeComponent(track.songKey)}'),
      );
      if (offset > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
      }
      final response = await request.close();
      _check(response);
      if (response.statusCode >= 300) {
        await response.drain<void>();
        throw SyncException('Could not receive ${track.title}.');
      }
      // A full answer to a range request: start over.
      final append = response.statusCode == HttpStatus.partialContent;
      final sink = part.openWrite(
        mode: append ? FileMode.append : FileMode.write,
      );
      try {
        await sink.addStream(response);
      } finally {
        await sink.close();
      }
    }
    if (await part.length() != track.size) {
      throw SyncException('${track.title} arrived incomplete.');
    }
    await files.receive(track, part, cover: await _fetchCover(base, track));
  }

  /// [track]'s cover on the computer, or null (none, or unreachable: the
  /// file is worth keeping without it).
  Future<List<int>?> _fetchCover(Uri base, TrackFile track) async {
    try {
      final request = await _open(
        'GET',
        base.resolve('/api/covers/${Uri.encodeComponent(track.songKey)}'),
      );
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    } catch (_) {
      return null;
    }
  }

  /// Sends [track], resuming from what the computer already has.
  Future<void> _upload(Uri base, TrackFile track) async {
    final source = File(track.path!);
    final announced = await _request(
      'POST',
      base.resolve('/api/uploads'),
      body: {'track': track.toJson()},
    );
    var offset = announced['received'] as int? ?? 0;
    final cover = await files.coverOf(track);
    if (cover != null && cover.isNotEmpty) {
      final request = await _open(
        'PUT',
        base.resolve(
          '/api/uploads/cover?key=${Uri.encodeQueryComponent(track.songKey)}',
        ),
      );
      request.headers.contentType = ContentType.binary;
      request.contentLength = cover.length;
      request.add(cover);
      final response = await request.close();
      _check(response);
      await response.drain<void>();
    }
    for (var attempt = 0; attempt < 2 && offset < track.size; attempt++) {
      final request = await _open(
        'PUT',
        base.resolve(
          '/api/uploads?key=${Uri.encodeQueryComponent(track.songKey)}'
          '&offset=$offset',
        ),
      );
      request.headers.contentType = ContentType.binary;
      request.contentLength = track.size - offset;
      await request.addStream(source.openRead(offset));
      final response = await request.close();
      _check(response);
      final reply = await _decode(response);
      offset = reply['received'] as int? ?? offset;
      if (response.statusCode == HttpStatus.conflict) continue;
      if (response.statusCode >= 300) {
        throw SyncException('Could not send ${track.title}.');
      }
    }
    if (offset != track.size) {
      throw SyncException('${track.title} could not be sent completely.');
    }
  }

  static const _usbUnreachable =
      'Could not reach the computer over USB. Check the cable, that USB '
      'debugging is on and that “Sync by USB cable” is on in My Zik on the '
      'computer.';

  /// The computer's address. Over USB, the phone's own forwarded port;
  /// over Wi-Fi, the last one that worked, then what network discovery
  /// finds, then the QR code's.
  Future<Uri> _resolve() async {
    final connection = this.connection;
    if (connection == null) {
      throw const SyncException('This phone is not paired with a computer.');
    }
    Future<bool> answers(String host, int port) async {
      try {
        final reply = await _request(
          'GET',
          Uri(scheme: 'http', host: host, port: port, path: '/api/hello'),
          timeout: const Duration(seconds: 3),
        );
        return reply['id'] == connection.serverId;
      } catch (_) {
        return false;
      }
    }

    if (transport == SyncTransport.usb) {
      const host = UsbBridge.phoneHost;
      if (await answers(host, connection.port)) {
        return Uri(scheme: 'http', host: host, port: connection.port);
      }
      throw const SyncException(_usbUnreachable);
    }

    final tried = <String>{};
    Future<Uri?> attempt(String host, int port) async {
      if (!tried.add('$host:$port') || !await answers(host, port)) return null;
      _update({'connection': connection.reachedAt(host, port).toJson()});
      return Uri(scheme: 'http', host: host, port: port);
    }

    if (connection.lastHost case final host?) {
      if (await attempt(host, connection.port) case final uri?) return uri;
    }
    for (final found
        in await discovery?.find(connection.serverId) ??
            const <DiscoveredServer>[]) {
      if (await attempt(found.host, found.port) case final uri?) return uri;
    }
    for (final host in connection.hosts) {
      if (await attempt(host, connection.port) case final uri?) return uri;
    }
    throw SyncException(
      'Could not reach ${connection.serverName}. Check that My Zik is open '
      'on it and that both are on the same Wi-Fi.',
    );
  }

  Future<HttpClientRequest> _open(String method, Uri uri) async {
    try {
      final request = await _http.openUrl(method, uri);
      final token = connection?.token;
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      return request;
    } on SocketException {
      throw SyncException('Could not reach ${uri.host}.');
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    Uri uri, {
    Object? body,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final request = await _open(method, uri);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(timeout);
      _check(response);
      final reply = await _decode(response).timeout(timeout);
      if (response.statusCode >= 300) {
        throw SyncException(
          reply['error'] as String? ?? 'The computer refused the request.',
        );
      }
      return reply;
    } on SocketException {
      throw SyncException('Could not reach ${uri.host}.');
    } on TimeoutException {
      throw SyncException('Could not reach ${uri.host} (no answer).');
    } on HttpException {
      throw SyncException('Could not reach ${uri.host}.');
    }
  }

  void _check(HttpClientResponse response) {
    if (response.statusCode == HttpStatus.unauthorized) {
      throw const SyncException(
        'The computer no longer recognises this phone: pair it again.',
        unpaired: true,
      );
    }
  }

  static Future<Map<String, dynamic>> _decode(
    HttpClientResponse response,
  ) async {
    final text = await utf8.decoder.bind(response).join();
    try {
      final json = jsonDecode(text);
      return json is Map<String, dynamic> ? json : const {};
    } catch (_) {
      return const {};
    }
  }

  void close() => _http.close(force: true);
}
