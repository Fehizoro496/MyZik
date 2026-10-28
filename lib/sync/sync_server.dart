import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/app_database.dart';

import 'sync_engine.dart';
import 'sync_files.dart';
import 'sync_store.dart';

/// A phone allowed to synchronize with this computer.
class PairedDevice {
  const PairedDevice({
    required this.id,
    required this.name,
    required this.tokenHash,
    required this.pairedAt,
    this.lastSyncAt,
  });

  final String id;
  final String name;

  /// SHA-256 of its token: the token itself is never stored here.
  final String tokenHash;
  final DateTime pairedAt;
  final DateTime? lastSyncAt;

  PairedDevice synced(DateTime at) => PairedDevice(
    id: id,
    name: name,
    tokenHash: tokenHash,
    pairedAt: pairedAt,
    lastSyncAt: at,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'token': tokenHash,
    'pairedAt': pairedAt.millisecondsSinceEpoch,
    if (lastSyncAt != null) 'lastSyncAt': lastSyncAt!.millisecondsSinceEpoch,
  };

  static PairedDevice? tryFromJson(Object? json) {
    if (json is! Map) return null;
    try {
      final last = json['lastSyncAt'] as int?;
      return PairedDevice(
        id: json['id'] as String,
        name: json['name'] as String,
        tokenHash: json['token'] as String,
        pairedAt: DateTime.fromMillisecondsSinceEpoch(json['pairedAt'] as int),
        lastSyncAt: last == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(last),
      );
    } catch (_) {
      return null;
    }
  }
}

/// A pairing window: the 6-digit [code] a phone must present (scanned from
/// the QR code or typed) before [expiresAt], within a few attempts.
class PairingOffer {
  PairingOffer(this.code, this.expiresAt);

  final String code;
  final DateTime expiresAt;
  int attemptsLeft = 5;

  bool get isOpen => attemptsLeft > 0 && DateTime.now().isBefore(expiresAt);
}

/// What the QR code holds: everything a phone needs to pair.
class PairingPayload {
  const PairingPayload({
    required this.serverId,
    required this.serverName,
    required this.hosts,
    required this.port,
    required this.code,
  });

  final String serverId;
  final String serverName;

  /// This computer's local network addresses, most likely first.
  final List<String> hosts;
  final int port;
  final String code;

  String encode() => jsonEncode({
    'app': 'myzik',
    'v': 1,
    'id': serverId,
    'name': serverName,
    'hosts': hosts,
    'port': port,
    'code': code,
  });

  static PairingPayload? tryDecode(String text) {
    try {
      final json = jsonDecode(text);
      if (json is! Map || json['app'] != 'myzik') return null;
      return PairingPayload(
        serverId: json['id'] as String,
        serverName: json['name'] as String,
        hosts: [for (final h in json['hosts'] as List) h as String],
        port: json['port'] as int,
        code: json['code'] as String,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Something that happened on the server, for the Sync screen.
sealed class SyncServerEvent {
  const SyncServerEvent(this.device);

  final PairedDevice device;
}

class DevicePaired extends SyncServerEvent {
  const DevicePaired(super.device);
}

class DeviceSynced extends SyncServerEvent {
  const DeviceSynced(super.device, {required this.received});

  /// Records the phone sent that were applied here.
  final int received;
}

class FileReceived extends SyncServerEvent {
  const FileReceived(super.device, this.track);

  final TrackFile track;
}

/// The computer's side of synchronization: an HTTP server on the local
/// network that paired phones exchange records and audio files with.
///
/// Endpoints (JSON unless noted; all but `hello` and `pair` need the
/// device's `Authorization: Bearer <token>`):
/// - `GET /api/hello`: this server's id and name.
/// - `POST /api/pair {code, deviceId, name}`: trades the pairing code for a
///   device token.
/// - `POST /api/sync {since, changes}`: applies the phone's changes, returns
///   the server's changes after `since` and the new cursor.
/// - `GET /api/files`: the audio files this computer can send.
/// - `GET /api/files/<key>`: one file's bytes (honours `Range`, to resume).
/// - `GET /api/covers/<key>`: one file's cover image, 404 when it has none.
/// - `POST /api/uploads {track}`: announces a file the phone will send;
///   returns how many bytes already arrived.
/// - `PUT /api/uploads/cover?key=..`: the announced file's cover image.
/// - `PUT /api/uploads?key=..&offset=..`: appends bytes; the file joins the
///   library once complete, with its cover.
class SyncServer {
  SyncServer({
    required this.engine,
    required this.files,
    required SharedPreferences preferences,
    this.database,
    required this.name,
    this.port = defaultPort,
  }) : _prefs = preferences {
    _devices = _loadDevices();
  }

  final SyncEngine engine;
  final SyncFiles files;
  final SharedPreferences _prefs;
  final AppDatabase? database;
  final String name;

  /// The port tried first; another free one is used when it is taken.
  final int port;

  static const defaultPort = 47815;

  String get _devicesKey => '${engine.store.keyPrefix}sync.pairedDevices.v1';

  HttpServer? _server;
  PairingOffer? _offer;
  late List<PairedDevice> _devices;
  final _uploads = <String, TrackFile>{};
  final _uploadCovers = <String, List<int>>{};

  /// Covers larger than this are refused (they are thumbnails).
  static const _maxCoverBytes = 10 * 1024 * 1024;
  final _events = StreamController<SyncServerEvent>.broadcast();

  String get serverId => engine.store.deviceId;
  bool get isRunning => _server != null;

  /// The port actually listened on.
  int? get boundPort => _server?.port;

  List<PairedDevice> get devices => List.unmodifiable(_devices);
  Stream<SyncServerEvent> get events => _events.stream;
  PairingOffer? get offer => _offer?.isOpen ?? false ? _offer : null;

  /// Starts listening on every network interface. [address] narrows it
  /// (tests use the loopback).
  Future<void> start({InternetAddress? address}) async {
    if (_server != null) return;
    final host = address ?? InternetAddress.anyIPv4;
    HttpServer server;
    try {
      server = await HttpServer.bind(host, port);
    } on SocketException {
      server = await HttpServer.bind(host, 0);
    }
    _server = server;
    server.listen(_handle);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> dispose() async {
    await stop();
    await _events.close();
  }

  /// Opens a pairing window and returns its offer.
  PairingOffer startPairing({Duration ttl = const Duration(minutes: 10)}) {
    final code = Random.secure().nextInt(1000000).toString().padLeft(6, '0');
    return _offer = PairingOffer(code, DateTime.now().add(ttl));
  }

  void cancelPairing() => _offer = null;

  /// The QR code contents for [offer].
  Future<PairingPayload> payloadFor(PairingOffer offer) async => PairingPayload(
    serverId: serverId,
    serverName: name,
    hosts: await localAddresses(),
    port: boundPort ?? port,
    code: offer.code,
  );

  /// Forgets [deviceId]: its token stops working.
  void revoke(String deviceId) {
    _devices = [
      for (final d in _devices)
        if (d.id != deviceId) d,
    ];
    _saveDevices();
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final segments = request.uri.pathSegments;
      if (segments.length < 2 || segments[0] != 'api') {
        return _json(response, {'error': 'not found'}, status: 404);
      }
      final route = segments[1];
      final method = request.method;
      if (route == 'hello' && method == 'GET') {
        return _json(response, {'id': serverId, 'name': name, 'v': 1});
      }
      if (route == 'pair' && method == 'POST') {
        return _pair(request);
      }
      final device = _authenticate(request);
      if (device == null) {
        return _json(response, {'error': 'unauthorized'}, status: 401);
      }
      switch ((route, method, segments.length)) {
        case ('sync', 'POST', 2):
          return _sync(request, device);
        case ('files', 'GET', 2):
          final local = await files.localFiles();
          return _json(response, {
            'files': [for (final f in local) f.toJson()],
          });
        case ('files', 'GET', 3):
          return _sendFile(request, segments[2]);
        case ('covers', 'GET', 3):
          return _sendCover(request, segments[2]);
        case ('uploads', 'POST', 2):
          return _announceUpload(request);
        case ('uploads', 'PUT', 3) when segments[2] == 'cover':
          return _receiveCover(request);
        case ('uploads', 'PUT', 2):
          return _receiveUpload(request, device);
      }
      return _json(response, {'error': 'not found'}, status: 404);
    } catch (e) {
      try {
        await _json(response, {'error': '$e'}, status: 500);
      } catch (_) {
        // The response was already under way.
      }
    }
  }

  Future<void> _pair(HttpRequest request) async {
    final body = await _readJson(request);
    final offer = _offer;
    if (offer == null || !offer.isOpen) {
      return _json(request.response, {
        'error': 'Pairing is not open on the computer.',
      }, status: 410);
    }
    if (body['code'] != offer.code) {
      offer.attemptsLeft--;
      return _json(request.response, {
        'error': 'Wrong pairing code.',
      }, status: 403);
    }
    final deviceId = body['deviceId'];
    final deviceName = body['name'];
    if (deviceId is! String || deviceName is! String) {
      return _json(request.response, {'error': 'bad request'}, status: 400);
    }
    _offer = null;
    final token = _randomToken();
    final device = PairedDevice(
      id: deviceId,
      name: deviceName,
      tokenHash: _hash(token),
      pairedAt: DateTime.now(),
    );
    _devices = [
      for (final d in _devices)
        if (d.id != deviceId) d,
      device,
    ];
    _saveDevices();
    _events.add(DevicePaired(device));
    return _json(request.response, {
      'token': token,
      'serverId': serverId,
      'serverName': name,
    });
  }

  Future<void> _sync(HttpRequest request, PairedDevice device) async {
    final body = await _readJson(request);
    final since = body['since'] is int ? body['since'] as int : 0;
    final changes = [
      for (final json in body['changes'] as List? ?? const [])
        ?SyncRecord.tryFromJson(json),
    ];
    final applied = await engine.incoming(changes, publish: true);
    final out = await engine.outgoing(since);
    final synced = device.synced(DateTime.now());
    _devices = [for (final d in _devices) d.id == device.id ? synced : d];
    _saveDevices();
    _events.add(DeviceSynced(synced, received: applied.length));
    return _json(request.response, {
      'cursor': out.cursor,
      'changes': [for (final r in out.records) r.toJson()],
    });
  }

  Future<void> _sendFile(HttpRequest request, String key) async {
    final response = request.response;
    final track = (await files.localFiles())
        .where((f) => f.songKey == key)
        .firstOrNull;
    final file = track?.path == null ? null : File(track!.path!);
    if (file == null || !file.existsSync()) {
      return _json(response, {'error': 'not found'}, status: 404);
    }
    final length = await file.length();
    var start = 0;
    final range = RegExp(
      r'^bytes=(\d+)-',
    ).firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
    if (range != null) {
      start = int.parse(range[1]!);
      if (start >= length) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
        return response.close();
      }
      response.statusCode = HttpStatus.partialContent;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-${length - 1}/$length',
      );
    }
    response.headers
      ..contentType = ContentType.binary
      ..contentLength = length - start
      ..set(HttpHeaders.acceptRangesHeader, 'bytes');
    await response.addStream(file.openRead(start));
    await response.close();
  }

  Future<void> _sendCover(HttpRequest request, String key) async {
    final response = request.response;
    final track = (await files.localFiles())
        .where((f) => f.songKey == key)
        .firstOrNull;
    final cover = track == null ? null : await files.coverOf(track);
    if (cover == null || cover.isEmpty) {
      return _json(response, {'error': 'no cover'}, status: 404);
    }
    response.headers
      ..contentType = ContentType.binary
      ..contentLength = cover.length;
    response.add(cover);
    await response.close();
  }

  Future<void> _receiveCover(HttpRequest request) async {
    final key = request.uri.queryParameters['key'];
    if (key == null || !_uploads.containsKey(key)) {
      return _json(request.response, {'error': 'announce first'}, status: 409);
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in request) {
      bytes.add(chunk);
      if (bytes.length > _maxCoverBytes) {
        return _json(request.response, {'error': 'too large'}, status: 413);
      }
    }
    _uploadCovers[key] = bytes.takeBytes();
    return _json(request.response, {'ok': true});
  }

  Future<void> _announceUpload(HttpRequest request) async {
    final body = await _readJson(request);
    final track = TrackFile.tryFromJson(body['track']);
    if (track == null) {
      return _json(request.response, {'error': 'bad request'}, status: 400);
    }
    _uploads[track.songKey] = track;
    final part = await files.incomingFile(track);
    final received = part.existsSync() ? await part.length() : 0;
    return _json(request.response, {
      'received': received > track.size ? 0 : received,
    });
  }

  Future<void> _receiveUpload(HttpRequest request, PairedDevice device) async {
    final key = request.uri.queryParameters['key'];
    final offset = int.tryParse(request.uri.queryParameters['offset'] ?? '');
    final track = key == null ? null : _uploads[key];
    if (track == null || offset == null) {
      return _json(request.response, {'error': 'announce first'}, status: 409);
    }
    final part = await files.incomingFile(track);
    await part.parent.create(recursive: true);
    final existing = part.existsSync() ? await part.length() : 0;
    if (offset != existing) {
      // Out of step: tell the phone where to resume from.
      return _json(request.response, {'received': existing}, status: 409);
    }
    final sink = part.openWrite(mode: FileMode.append);
    try {
      await sink.addStream(request);
    } finally {
      await sink.close();
    }
    final received = await part.length();
    if (received > track.size) {
      await part.delete();
      return _json(request.response, {'error': 'too long'}, status: 400);
    }
    if (received == track.size) {
      _uploads.remove(key);
      await files.receive(track, part, cover: _uploadCovers.remove(key));
      _events.add(FileReceived(device, track));
    }
    return _json(request.response, {'received': received});
  }

  PairedDevice? _authenticate(HttpRequest request) {
    final header = request.headers.value(HttpHeaders.authorizationHeader);
    if (header == null || !header.startsWith('Bearer ')) return null;
    final hash = _hash(header.substring(7));
    return _devices.where((d) => d.tokenHash == hash).firstOrNull;
  }

  List<PairedDevice> _loadDevices() {
    try {
      if (database case final db?) {
        return [
          for (final row in db.pairedDevices) ?PairedDevice.tryFromJson(row),
        ];
      }
      return [
        for (final json
            in jsonDecode(_prefs.getString(_devicesKey) ?? '[]') as List)
          ?PairedDevice.tryFromJson(json),
      ];
    } catch (_) {
      return [];
    }
  }

  void _saveDevices() {
    if (database case final db?) {
      db.replacePairedDevices([for (final device in _devices) device.toJson()]);
    } else {
      _prefs.setString(
        _devicesKey,
        jsonEncode([for (final d in _devices) d.toJson()]),
      );
    }
  }

  static Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
    final text = await utf8.decoder.bind(request).join();
    final json = text.isEmpty ? null : jsonDecode(text);
    return json is Map<String, dynamic> ? json : const {};
  }

  static Future<void> _json(
    HttpResponse response,
    Object body, {
    int status = 200,
  }) {
    response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    return response.close();
  }

  static String _randomToken() {
    final random = Random.secure();
    return base64Url.encode(List.generate(32, (_) => random.nextInt(256)));
  }

  static String _hash(String token) =>
      sha256.convert(utf8.encode(token)).toString();
}

/// This computer's IPv4 addresses on the local network, private ranges
/// (home Wi-Fi) first.
Future<List<String>> localAddresses() async {
  final List<NetworkInterface> interfaces;
  try {
    interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
  } catch (_) {
    return const [];
  }
  bool isPrivate(String a) =>
      a.startsWith('192.168.') ||
      a.startsWith('10.') ||
      RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(a);
  final addresses = [
    for (final i in interfaces)
      for (final a in i.addresses)
        if (!a.isLoopback && !a.isLinkLocal) a.address,
  ];
  return [
    ...addresses.where(isPrivate),
    ...addresses.where((a) => !isPrivate(a)),
  ];
}
