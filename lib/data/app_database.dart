import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The app's single SQLite database. Small in-memory snapshots keep the
/// existing synchronous Riverpod state APIs responsive; SQLite remains the
/// durable source and all queued writes are drained by [flush].
class AppDatabase {
  AppDatabase._(this._db, this.path);

  final Database _db;
  final String path;
  Future<void> _writes = Future<void>.value();

  final Set<String> _likes = {};
  final Map<String, Map<String, dynamic>> _playlists = {};
  final Map<String, Map<String, dynamic>> _lyrics = {};
  final Map<String, Map<String, Object?>> _syncRecords = {};
  final Map<String, String> _syncState = {};
  final Map<String, Map<String, dynamic>> _pairedDevices = {};
  final Map<String, String> _fingerprints = {};
  final Map<String, String> _libraryIndex = {};
  final Map<String, String> _downloads = {};
  final Map<String, String> _receivedFiles = {};
  final Map<String, String> _settings = {};

  String? deviceId;
  int syncSequence = 0;

  Set<String> get likedKeys => Set.unmodifiable(_likes);
  List<Map<String, dynamic>> get playlists => [
    for (final value in _playlists.values) Map<String, dynamic>.from(value),
  ];
  List<Map<String, dynamic>> get pairedDevices => [
    for (final value in _pairedDevices.values) Map<String, dynamic>.from(value),
  ];

  static Future<AppDatabase> open() async {
    final support = await getApplicationSupportDirectory();
    final dbPath = p.join(support.path, 'myzik.sqlite');
    final factory = _factoryForPlatform();
    final db = await factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: _configure,
        onCreate: (database, _) => _createSchema(database),
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 1) await _createSchema(database);
        },
      ),
    );
    final appDb = AppDatabase._(db, dbPath);
    await appDb._loadSnapshots();
    return appDb;
  }

  /// Uses the same FFI factory as desktop in unit tests, with a disposable
  /// in-memory SQLite database.
  static Future<AppDatabase> inMemory() async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: false,
        onConfigure: _configure,
        onCreate: (database, _) => _createSchema(database),
      ),
    );
    final appDb = AppDatabase._(db, inMemoryDatabasePath);
    await appDb._loadSnapshots();
    return appDb;
  }

  static DatabaseFactory _factoryForPlatform() {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      return databaseFactoryFfi;
    }
    return mobile.databaseFactory;
  }

  /// Foreign keys are a per-connection setting: turned on at every open.
  static Future<void> _configure(Database db) =>
      db.execute('PRAGMA foreign_keys = ON');

  static Future<void> _createSchema(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE likes (
      song_key TEXT PRIMARY KEY NOT NULL
    )''');
    await db.execute('''CREATE TABLE playlists (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL,
      updated_at INTEGER NOT NULL DEFAULT 0
    )''');
    await db.execute('''CREATE TABLE playlist_songs (
      playlist_id TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
      position INTEGER NOT NULL,
      song_key TEXT NOT NULL,
      PRIMARY KEY (playlist_id, position),
      UNIQUE (playlist_id, song_key)
    )''');
    await db.execute(
      'CREATE INDEX playlist_songs_key ON playlist_songs(song_key)',
    );
    await db.execute('''CREATE TABLE lyrics (
      song_key TEXT PRIMARY KEY NOT NULL,
      source TEXT,
      plain TEXT,
      lines_json TEXT,
      instrumental INTEGER NOT NULL DEFAULT 0,
      source_url TEXT,
      edited INTEGER NOT NULL DEFAULT 0,
      found INTEGER NOT NULL DEFAULT 0,
      metadata_key TEXT,
      metadata_artist TEXT,
      metadata_title TEXT,
      duration_seconds INTEGER NOT NULL DEFAULT 0,
      record_json TEXT NOT NULL,
      updated_at INTEGER NOT NULL DEFAULT 0
    )''');
    await db.execute(
      'CREATE INDEX lyrics_metadata ON lyrics(metadata_artist, metadata_title, duration_seconds)',
    );
    await db.execute('''CREATE TABLE sync_records (
      id TEXT PRIMARY KEY NOT NULL,
      sequence INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      origin TEXT NOT NULL,
      deleted INTEGER NOT NULL DEFAULT 0,
      found INTEGER NOT NULL DEFAULT 0
    )''');
    await db.execute(
      'CREATE INDEX sync_records_sequence ON sync_records(sequence)',
    );
    await db.execute('''CREATE TABLE sync_state (
      key TEXT PRIMARY KEY NOT NULL,
      value TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE paired_devices (
      id TEXT PRIMARY KEY NOT NULL,
      record_json TEXT NOT NULL,
      last_seen INTEGER NOT NULL DEFAULT 0
    )''');
    await db.execute('''CREATE TABLE fingerprints (
      cache_key TEXT PRIMARY KEY NOT NULL,
      song_key TEXT NOT NULL,
      file_size INTEGER NOT NULL,
      modified_ms INTEGER NOT NULL
    )''');
    await db.execute('''CREATE TABLE library_index (
      path TEXT PRIMARY KEY NOT NULL,
      file_size INTEGER NOT NULL,
      modified_ms INTEGER NOT NULL,
      record_json TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE downloads (
      video_id TEXT PRIMARY KEY NOT NULL,
      record_json TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE received_files (
      song_key TEXT PRIMARY KEY NOT NULL,
      record_json TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE app_settings (
      key TEXT PRIMARY KEY NOT NULL,
      value TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE migration_state (
      key TEXT PRIMARY KEY NOT NULL,
      completed_at INTEGER NOT NULL
    )''');
  }

  Future<void> _loadSnapshots() async {
    _likes.addAll(
      (await _db.query('likes')).map((row) => row['song_key']! as String),
    );
    for (final playlist in await _db.query('playlists')) {
      final id = playlist['id']! as String;
      final songs = await _db.query(
        'playlist_songs',
        columns: ['song_key'],
        where: 'playlist_id = ?',
        whereArgs: [id],
        orderBy: 'position',
      );
      _playlists[id] = {
        'id': id,
        'name': playlist['name'],
        'songKeys': [for (final row in songs) row['song_key']],
      };
    }
    for (final row in await _db.query('lyrics')) {
      _lyrics[row['song_key']! as String] =
          jsonDecode(row['record_json']! as String) as Map<String, dynamic>;
    }
    for (final row in await _db.query('sync_records')) {
      _syncRecords[row['id']! as String] = {
        'sequence': row['sequence'],
        'updatedAt': row['updated_at'],
        'origin': row['origin'],
        // SQLite stores booleans as 0/1.
        'deleted': row['deleted'] == 1,
        'found': row['found'] == 1,
      };
      final seq = row['sequence']! as int;
      if (seq > syncSequence) syncSequence = seq;
    }
    for (final row in await _db.query('sync_state')) {
      _syncState[row['key']! as String] = row['value']! as String;
    }
    for (final row in await _db.query('app_settings')) {
      _settings[row['key']! as String] = row['value']! as String;
    }
    deviceId = _syncState['deviceId'];
    syncSequence = int.tryParse(_syncState['sequence'] ?? '') ?? syncSequence;
    for (final row in await _db.query('paired_devices')) {
      final record =
          jsonDecode(row['record_json']! as String) as Map<String, dynamic>;
      _pairedDevices[row['id']! as String] = record;
    }
    for (final row in await _db.query('fingerprints')) {
      _fingerprints[row['cache_key']! as String] = row['song_key']! as String;
    }
    for (final row in await _db.query('library_index')) {
      _libraryIndex[row['path']! as String] = row['record_json']! as String;
    }
    for (final row in await _db.query('downloads')) {
      _downloads[row['video_id']! as String] = row['record_json']! as String;
    }
    for (final row in await _db.query('received_files')) {
      _receivedFiles[row['song_key']! as String] =
          row['record_json']! as String;
    }
  }

  /// Writes collected by [atomically], committed together.
  List<Future<void> Function(Transaction txn)>? _batch;

  /// Queues a write: writes run one after the other, in order. A failed
  /// write is logged and doesn't stop the ones after it. Inside
  /// [atomically], the write joins its transaction instead. The returned
  /// future completes once the write is on disk (at once inside
  /// [atomically], which waits for the whole transaction).
  Future<void> _enqueue(Future<void> Function(Transaction txn) action) {
    if (_batch case final batch?) {
      batch.add(action);
      return Future<void>.value();
    }
    return _writes = _writes.then((_) => _db.transaction(action)).catchError((
      Object error,
      StackTrace stack,
    ) {
      debugPrint('AppDatabase: a write failed: $error');
      debugPrintStack(stackTrace: stack);
    });
  }

  /// Runs [body] and commits every write it makes in one transaction: all
  /// of them reach the disk, or none. On failure the in-memory state is
  /// read back from the disk, so it never shows what wasn't saved, and the
  /// error is rethrown. Not reentrant: a nested call joins the outer one.
  Future<T> atomically<T>(Future<T> Function() body) async {
    if (_batch != null) return body();
    final batch = _batch = [];
    final T result;
    try {
      result = await body();
    } catch (_) {
      _batch = null;
      await reload();
      rethrow;
    }
    _batch = null;
    final committed = _writes.then(
      (_) => _db.transaction((txn) async {
        for (final action in batch) {
          await action(txn);
        }
      }),
    );
    _writes = committed.catchError((Object _) {});
    try {
      await committed;
    } catch (_) {
      await reload();
      rethrow;
    }
    return result;
  }

  /// Reads the in-memory state back from the disk.
  Future<void> reload() async {
    _likes.clear();
    _playlists.clear();
    _lyrics.clear();
    _syncRecords.clear();
    _syncState.clear();
    _pairedDevices.clear();
    _fingerprints.clear();
    _libraryIndex.clear();
    _downloads.clear();
    _receivedFiles.clear();
    _settings.clear();
    syncSequence = 0;
    await _loadSnapshots();
  }

  Future<void> flush() => _writes;

  Future<void> close() async {
    await flush();
    await _db.close();
  }

  Future<bool> isMigrated(String key) async => (await _db.query(
    'migration_state',
    where: 'key = ?',
    whereArgs: [key],
  )).isNotEmpty;

  /// Records that the one-time step [key] is done.
  Future<void> markDone(String key) =>
      _db.transaction((txn) => markMigrated(key, txn));

  Future<void> markMigrated(String key, Transaction txn) async {
    await txn.insert('migration_state', {
      'key': key,
      'completed_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> importLegacyRows({
    required Set<String> likes,
    required List<Map<String, dynamic>> playlists,
    required Map<String, Map<String, dynamic>> lyrics,
    required Map<String, Map<String, Object?>> syncRecords,
    required Map<String, String> syncState,
    required List<Map<String, dynamic>> pairedDevices,
    required Map<String, String> fingerprints,
    required Map<String, String> libraryIndex,
    required Map<String, String> downloads,
    required Map<String, String> receivedFiles,
    Map<String, String> settings = const {},
  }) async {
    await _db.transaction((txn) async {
      await _insertLikes(txn, likes);
      await _insertPlaylists(txn, playlists);
      for (final entry in lyrics.entries) {
        final record = entry.value;
        final metadata = (record['_songMetadata'] as String? ?? '').split('|');
        final isFound =
            record['edited'] != true && record['source'] != 'manual';
        await txn.insert('lyrics', {
          'song_key': entry.key,
          'source': record['source'],
          'plain': record['plain'],
          'lines_json': jsonEncode(record['lines'] ?? const []),
          'instrumental': record['instrumental'] == true ? 1 : 0,
          'source_url': record['sourceUrl'],
          'edited': record['edited'] == true ? 1 : 0,
          'found': isFound ? 1 : 0,
          'metadata_key': record['_songMetadata'],
          'metadata_artist': metadata.isNotEmpty ? metadata[0] : null,
          'metadata_title': metadata.length > 1 ? metadata[1] : null,
          'duration_seconds': metadata.length > 2
              ? int.tryParse(metadata[2]) ?? 0
              : 0,
          'record_json': jsonEncode(record),
          'updated_at': 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final entry in syncRecords.entries) {
        await _putSyncRecord(txn, entry.key, entry.value);
      }
      for (final entry in syncState.entries) {
        await txn.insert('sync_state', {
          'key': entry.key,
          'value': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final device in pairedDevices) {
        await _putPairedDevice(txn, device);
      }
      for (final entry in fingerprints.entries) {
        await txn.insert('fingerprints', {
          'cache_key': entry.key,
          'song_key': entry.value,
          'file_size': 0,
          'modified_ms': 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final entry in libraryIndex.entries) {
        final record = jsonDecode(entry.value) as Map<String, dynamic>;
        await txn.insert('library_index', {
          'path': entry.key,
          'file_size': record['size'] as int? ?? 0,
          'modified_ms': record['modifiedMs'] as int? ?? 0,
          'record_json': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final entry in downloads.entries) {
        await txn.insert('downloads', {
          'video_id': entry.key,
          'record_json': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final entry in receivedFiles.entries) {
        await txn.insert('received_files', {
          'song_key': entry.key,
          'record_json': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final entry in settings.entries) {
        await txn.insert('app_settings', {
          'key': entry.key,
          'value': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await markMigrated('legacy.v1', txn);
    });
    await _loadSnapshots();
  }

  void replaceLikes(Set<String> values) {
    _likes
      ..clear()
      ..addAll(values);
    _enqueue((txn) => _insertLikes(txn, values));
  }

  Future<void> _insertLikes(
    DatabaseExecutor executor,
    Set<String> values,
  ) async {
    await executor.delete('likes');
    for (final key in values) {
      await executor.insert('likes', {
        'song_key': key,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  void replacePlaylists(List<Map<String, dynamic>> values) {
    _playlists
      ..clear()
      ..addEntries(
        values.map((value) => MapEntry(value['id'] as String, value)),
      );
    _enqueue((txn) => _insertPlaylists(txn, values));
  }

  Future<void> _insertPlaylists(
    DatabaseExecutor executor,
    List<Map<String, dynamic>> values,
  ) async {
    await executor.delete('playlist_songs');
    await executor.delete('playlists');
    for (final playlist in values) {
      final id = playlist['id'] as String;
      await executor.insert('playlists', {
        'id': id,
        'name': playlist['name'] ?? 'Playlist',
        'updated_at': playlist['updatedAt'] as int? ?? 0,
      });
      final keys = playlist['songKeys'] as List? ?? const [];
      for (var i = 0; i < keys.length; i++) {
        await executor.insert('playlist_songs', {
          'playlist_id': id,
          'position': i,
          'song_key': keys[i] as String,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
  }

  Map<String, dynamic>? lyric(String key) =>
      _lyrics[key] == null ? null : Map.of(_lyrics[key]!);
  List<Map<String, dynamic>> get lyricRecords => [
    for (final row in _lyrics.entries) {'key': row.key, ...row.value},
  ];

  /// Lyrics stored for the same recording under another key: same
  /// normalized artist and title, durations within [durationTolerance]
  /// seconds (an unknown duration, 0, matches any). Lyrics the listener made
  /// come first, then the closest duration. "Not found" entries are skipped.
  Future<Map<String, dynamic>?> lyricByMetadata(
    String artist,
    String title,
    int durationSeconds, {
    int durationTolerance = 2,
  }) async {
    final rows = await _db.query(
      'lyrics',
      where: 'metadata_artist = ? AND metadata_title = ?',
      whereArgs: [artist, title],
    );
    int distance(Map<String, Object?> row) {
      final seconds = row['duration_seconds'] as int? ?? 0;
      return seconds == 0 || durationSeconds == 0
          ? 0
          : (seconds - durationSeconds).abs();
    }

    final candidates = [
      for (final row in rows)
        if (distance(row) <= durationTolerance)
          (row, jsonDecode(row['record_json']! as String)),
    ]..removeWhere((c) => c.$2 is! Map || (c.$2 as Map)['miss'] == true);
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final byOrigin = (a.$1['found'] as int? ?? 0).compareTo(
        b.$1['found'] as int? ?? 0,
      );
      return byOrigin != 0
          ? byOrigin
          : distance(a.$1).compareTo(distance(b.$1));
    });
    return Map<String, dynamic>.from(candidates.first.$2 as Map);
  }

  Future<void> putLyrics(
    String key,
    Map<String, dynamic> record, {
    String? metadataKey,
    String? artist,
    String? title,
    int durationSeconds = 0,
    bool found = false,
  }) async {
    _lyrics[key] = Map.of(record);
    final row = {
      'song_key': key,
      'source': record['source'],
      'plain': record['plain'],
      'lines_json': jsonEncode(record['lines'] ?? const []),
      'instrumental': record['instrumental'] == true ? 1 : 0,
      'source_url': record['sourceUrl'],
      'edited': record['edited'] == true ? 1 : 0,
      'found': found ? 1 : 0,
      'metadata_key': metadataKey,
      'metadata_artist': artist,
      'metadata_title': title,
      'duration_seconds': durationSeconds,
      'record_json': jsonEncode(record),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };
    await _enqueue(
      (txn) => txn.insert(
        'lyrics',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      ),
    );
  }

  Future<void> deleteLyrics(String key) async {
    _lyrics.remove(key);
    await _enqueue(
      (txn) => txn.delete('lyrics', where: 'song_key = ?', whereArgs: [key]),
    );
  }

  Map<String, Map<String, Object?>> get journal => {
    for (final entry in _syncRecords.entries) entry.key: Map.of(entry.value),
  };

  void putSyncRecord(
    String id,
    Map<String, Object?> record, {
    required int sequence,
  }) {
    _syncRecords[id] = Map.of(record);
    if (sequence > syncSequence) syncSequence = sequence;
    _enqueue((txn) => _putSyncRecord(txn, id, record));
  }

  Future<void> _putSyncRecord(
    DatabaseExecutor executor,
    String id,
    Map<String, Object?> record,
  ) async {
    await executor.insert('sync_records', {
      'id': id,
      'sequence': record['sequence'] as int? ?? 0,
      'updated_at': record['updatedAt'] as int? ?? 0,
      'origin': record['origin'] as String? ?? '',
      'deleted': record['deleted'] == true ? 1 : 0,
      'found': record['found'] == true ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  String? getSyncState(String key) => _syncState[key];
  void setSyncState(String key, String value) {
    _syncState[key] = value;
    if (key == 'deviceId') deviceId = value;
    _enqueue((txn) async {
      await txn.insert('sync_state', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  List<Map<String, dynamic>> get downloadRecords => [
    for (final entry in _downloads.entries)
      {
        'videoId': entry.key,
        ...jsonDecode(entry.value) as Map<String, dynamic>,
      },
  ];
  void replaceDownloads(Map<String, String> values) {
    _downloads
      ..clear()
      ..addAll(values);
    _enqueue((txn) async {
      await txn.delete('downloads');
      for (final entry in values.entries) {
        await txn.insert('downloads', {
          'video_id': entry.key,
          'record_json': entry.value,
        });
      }
    });
  }

  Map<String, String> libraryIndex() => Map.of(_libraryIndex);
  void replaceLibraryIndex(Map<String, String> values) {
    _libraryIndex
      ..clear()
      ..addAll(values);
    _enqueue((txn) async {
      await txn.delete('library_index');
      for (final entry in values.entries) {
        final record = jsonDecode(entry.value) as Map<String, dynamic>;
        await txn.insert('library_index', {
          'path': entry.key,
          'file_size': record['size'] as int? ?? 0,
          'modified_ms': record['modifiedMs'] as int? ?? 0,
          'record_json': entry.value,
        });
      }
    });
  }

  Map<String, String> fingerprintCache() => Map.of(_fingerprints);
  void setFingerprint(
    String cacheKey,
    String songKey, {
    required int size,
    required int modifiedMs,
  }) {
    _fingerprints[cacheKey] = songKey;
    _enqueue((txn) async {
      await txn.insert('fingerprints', {
        'cache_key': cacheKey,
        'song_key': songKey,
        'file_size': size,
        'modified_ms': modifiedMs,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  void replacePairedDevices(List<Map<String, dynamic>> devices) {
    _pairedDevices
      ..clear()
      ..addEntries(
        devices.map((record) => MapEntry(record['id'] as String, record)),
      );
    _enqueue((txn) async {
      await txn.delete('paired_devices');
      for (final device in devices) {
        await _putPairedDevice(txn, device);
      }
    });
  }

  Future<void> _putPairedDevice(
    DatabaseExecutor executor,
    Map<String, dynamic> device,
  ) async {
    await executor.insert('paired_devices', {
      'id': device['id'],
      'record_json': jsonEncode(device),
      'last_seen': device['lastSeen'] as int? ?? 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Map<String, String> receivedFiles() => Map.of(_receivedFiles);
  void replaceReceivedFiles(Map<String, String> values) {
    _receivedFiles
      ..clear()
      ..addAll(values);
    _enqueue((txn) async {
      await txn.delete('received_files');
      for (final entry in values.entries) {
        await txn.insert('received_files', {
          'song_key': entry.key,
          'record_json': entry.value,
        });
      }
    });
  }

  List<String> getStringListSetting(String key) {
    final value = _settings[key];
    if (value == null) return const [];
    return (jsonDecode(value) as List).cast<String>();
  }

  bool hasSetting(String key) => _settings.containsKey(key);

  Future<void> setStringListSetting(String key, List<String> value) async {
    final encoded = _settings[key] = jsonEncode(value);
    await _enqueue(
      (txn) => txn.insert('app_settings', {
        'key': key,
        'value': encoded,
      }, conflictAlgorithm: ConflictAlgorithm.replace),
    );
  }

  /// Removes a setting (it falls back to its default).
  Future<void> removeSetting(String key) async {
    _settings.remove(key);
    await _enqueue(
      (txn) => txn.delete('app_settings', where: 'key = ?', whereArgs: [key]),
    );
  }
}
