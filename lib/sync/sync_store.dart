import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import '../data/app_database.dart';

/// One synchronized record as exchanged between devices: its id (see
/// [SyncIds]), when and where it last changed, whether it was found
/// automatically or deleted, and its value (absent for deletions and in the
/// local journal).
class SyncRecord {
  const SyncRecord({
    required this.id,
    required this.updatedAt,
    required this.origin,
    this.deleted = false,
    this.found = false,
    this.value,
  });

  final String id;

  /// Milliseconds since the epoch on the device that made the change.
  final int updatedAt;

  /// Id of the device that made the change; breaks timestamp ties.
  final String origin;
  final bool deleted;

  /// Produced by the app rather than the user (lyrics looked up online):
  /// such a version never replaces one the user made.
  final bool found;
  final Object? value;

  /// What the user made beats what was found; then the last writer wins,
  /// a tie going to the higher origin.
  bool isNewerThan(SyncRecord other) {
    if (found != other.found) return !found;
    if (updatedAt != other.updatedAt) return updatedAt > other.updatedAt;
    return origin.compareTo(other.origin) > 0;
  }

  /// The same change, applied to another record (see `SyncData.aliases`).
  SyncRecord withId(String id) => SyncRecord(
    id: id,
    updatedAt: updatedAt,
    origin: origin,
    deleted: deleted,
    found: found,
    value: value,
  );

  SyncRecord withValue(Object? value) => SyncRecord(
    id: id,
    updatedAt: updatedAt,
    origin: origin,
    deleted: deleted,
    found: found,
    value: value,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    't': updatedAt,
    'o': origin,
    if (deleted) 'd': true,
    if (found) 'f': true,
    if (value != null) 'v': value,
  };

  static SyncRecord? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final t = json['t'];
    final o = json['o'];
    if (id is! String || t is! int || o is! String) return null;
    return SyncRecord(
      id: id,
      updatedAt: t,
      origin: o,
      deleted: json['d'] == true,
      found: json['f'] == true,
      value: json['v'],
    );
  }
}

/// Ids of synchronized records, by kind.
class SyncIds {
  const SyncIds._();

  static const like = 'like:';
  static const playlist = 'playlist:';
  static const lyrics = 'lyrics:';

  static String forLike(String songKey) => '$like$songKey';
  static String forPlaylist(String id) => '$playlist$id';
  static String forLyrics(String songKey) => '$lyrics$songKey';
}

/// The local journal of synchronized records: for each, its last change
/// (timestamp, origin, deletion) and a sequence number. Every accepted change
/// gets the next sequence number, so "what changed since N" is the records
/// above N: that is the cursor devices exchange. Values are not kept here;
/// they live in the app's own stores (see `SyncData`).
///
/// Persisted in [SharedPreferences] so local changes are recorded
/// synchronously, the moment they happen.
class SyncStore {
  SyncStore(
    this._prefs, {
    int Function()? clock,
    this.keyPrefix = '',
    this.database,
  }) : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch) {
    _load();
  }

  final SharedPreferences _prefs;
  final AppDatabase? database;
  final int Function() _clock;

  /// Prepended to the preference keys, so two devices can share one
  /// [SharedPreferences] in tests.
  final String keyPrefix;

  String get _stateKey => '${keyPrefix}sync.state.v1';
  String get _deviceKey => '${keyPrefix}sync.deviceId';

  late final String deviceId =
      database?.deviceId ?? _prefs.getString(_deviceKey) ?? _newDeviceId();
  int _sequence = 0;
  final _entries = <String, _Entry>{};

  /// The highest sequence number given so far.
  int get sequence => _sequence;

  /// The last known change of [id], or null if it never changed.
  SyncRecord? recordOf(String id) => _entries[id]?.toRecord(id);

  /// Records a local change of [id] (a deletion when [deleted]; produced by
  /// the app rather than the user when [found]), stamped now and with this
  /// device as origin.
  void touch(String id, {bool deleted = false, bool found = false}) {
    final previous = _entries[id];
    // Never go back in time, even if the clock does.
    final now = max(_clock(), (previous?.updatedAt ?? 0) + 1);
    _entries[id] = _Entry(++_sequence, now, deviceId, deleted, found);
    _save([id]);
  }

  /// Registers the [existing] records (id → whether it was found rather
  /// than made by the user) that the journal doesn't know yet: data from
  /// before synchronization, or stored without being recorded. They count
  /// as changes older than any real one (timestamp 1), so both sides merge
  /// instead of one erasing the other. Known records are left alone.
  void register(Map<String, bool> existing) {
    var added = false;
    final addedIds = <String>[];
    for (final MapEntry(key: id, value: found) in existing.entries) {
      if (_entries.containsKey(id)) continue;
      _entries[id] = _Entry(++_sequence, 1, deviceId, false, found);
      added = true;
      addedIds.add(id);
    }
    if (added) _save(addedIds);
  }

  /// The records changed after [since], oldest change first, without values.
  List<SyncRecord> changesSince(int since) {
    final changed = [
      for (final entry in _entries.entries)
        if (entry.value.sequence > since) entry,
    ]..sort((a, b) => a.value.sequence.compareTo(b.value.sequence));
    return [for (final e in changed) e.value.toRecord(e.key)];
  }

  /// Whether [remote] beats what this device knows of its record.
  bool wins(SyncRecord remote) {
    final local = recordOf(remote.id);
    return local == null || remote.isNewerThan(local);
  }

  /// Takes [remote] as the record's latest change, once its value has been
  /// applied. With [publish] (on the server) it gets a new sequence number,
  /// so other devices pull it; without (on a client) it isn't sent back.
  void accept(SyncRecord remote, {required bool publish}) {
    _entries[remote.id] = _Entry(
      publish ? ++_sequence : 0,
      remote.updatedAt,
      remote.origin,
      remote.deleted,
      remote.found,
    );
    _save([remote.id]);
  }

  String _newDeviceId() {
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    _prefs.setString(_deviceKey, id);
    return id;
  }

  void _load() {
    if (database case final db?) {
      _sequence = db.syncSequence;
      for (final entry in db.journal.entries) {
        final row = entry.value;
        _entries[entry.key] = _Entry(
          row['sequence'] as int? ?? 0,
          row['updatedAt'] as int? ?? 0,
          row['origin'] as String? ?? '',
          row['deleted'] == true,
          row['found'] == true,
        );
      }
      return;
    }
    final raw = _prefs.getString(_stateKey);
    if (raw == null) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _sequence = json['seq'] as int? ?? 0;
      final entries = json['records'] as Map<String, dynamic>? ?? const {};
      for (final entry in entries.entries) {
        final e = _Entry.tryFromJson(entry.value);
        if (e != null) _entries[entry.key] = e;
      }
    } catch (_) {
      // Unreadable journal: start over; the next exchange re-merges.
    }
  }

  void _save([Iterable<String>? changedIds]) {
    if (database case final db?) {
      final ids = changedIds ?? _entries.keys;
      for (final id in ids) {
        final entry = _entries[id];
        if (entry == null) continue;
        db.putSyncRecord(id, {
          'sequence': entry.sequence,
          'updatedAt': entry.updatedAt,
          'origin': entry.origin,
          'deleted': entry.deleted,
          'found': entry.found,
        }, sequence: entry.sequence);
      }
      db.setSyncState('deviceId', deviceId);
      db.setSyncState('sequence', '$_sequence');
      return;
    }
    _prefs.setString(
      _stateKey,
      jsonEncode({
        'seq': _sequence,
        'records': {
          for (final entry in _entries.entries) entry.key: entry.value.toJson(),
        },
      }),
    );
  }
}

class _Entry {
  const _Entry(
    this.sequence,
    this.updatedAt,
    this.origin,
    this.deleted, [
    this.found = false,
  ]);

  final int sequence;
  final int updatedAt;
  final String origin;
  final bool deleted;
  final bool found;

  SyncRecord toRecord(String id) => SyncRecord(
    id: id,
    updatedAt: updatedAt,
    origin: origin,
    deleted: deleted,
    found: found,
  );

  /// `[sequence, updatedAt, origin, flags]`, flags: 1 deleted, 2 found.
  List<Object> toJson() => [
    sequence,
    updatedAt,
    origin,
    if (deleted || found) (deleted ? 1 : 0) | (found ? 2 : 0),
  ];

  static _Entry? tryFromJson(Object? json) {
    if (json is! List || json.length < 3) return null;
    final [sequence, updatedAt, origin, ...rest] = json;
    if (sequence is! int || updatedAt is! int || origin is! String) {
      return null;
    }
    final flags = rest.isEmpty ? 0 : rest.first as int? ?? 0;
    return _Entry(sequence, updatedAt, origin, flags & 1 != 0, flags & 2 != 0);
  }
}
