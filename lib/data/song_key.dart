import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

/// Cross-device identity for a recording: the value of [Song.songKey] once
/// the file fingerprint is known.
class SongKey {
  const SongKey._(this.value);

  final String value;

  static const _fingerprintCacheKey = 'song.fingerprints.v1';

  /// Bounds the fingerprint cache; entries for the current library are kept
  /// first.
  static const _maxCachedFingerprints = 5000;

  /// Files hashed (or stat'ed) at the same time.
  static const _batchSize = 16;

  /// The key of one song; see [resolveAll].
  static Future<SongKey> forSong(
    Song song, {
    SharedPreferences? preferences,
  }) async {
    final keys = await resolveAll([song], preferences: preferences);
    return SongKey._(keys.single);
  }

  /// [Song.songKey] for each of [songs], in order, with local files
  /// fingerprinted. Fingerprints are cached in [preferences] by path, size
  /// and modification time: the cache is read once and written once, and
  /// only when a file had to be hashed, so an unchanged library writes
  /// nothing.
  static Future<List<String>> resolveAll(
    List<Song> songs, {
    SharedPreferences? preferences,
  }) async {
    final cache = preferences == null
        ? <String, dynamic>{}
        : _readFingerprintCache(preferences);
    final used = <String, String>{};
    var hashed = false;

    Future<String> resolve(Song song) async {
      final videoId = song.youtubeVideoId?.trim();
      final path = song.filePath;
      if ((videoId != null && videoId.isNotEmpty) ||
          path == null ||
          path.isEmpty) {
        return song.songKey;
      }
      try {
        final file = File(path);
        final stat = await file.stat();
        if (stat.type == FileSystemEntityType.notFound) return song.songKey;
        final cacheId =
            '$path|${stat.size}|${stat.modified.microsecondsSinceEpoch}';
        var hash = cache[cacheId];
        if (hash is! String) {
          hash = await fingerprint(file, size: stat.size);
          hashed = true;
        }
        used[cacheId] = hash;
        return 'fp:$hash';
      } catch (_) {
        return song.songKey;
      }
    }

    final keys = <String>[];
    for (var i = 0; i < songs.length; i += _batchSize) {
      final batch = songs.skip(i).take(_batchSize);
      keys.addAll(await Future.wait(batch.map(resolve)));
    }

    if (preferences != null && hashed) {
      final next = <String, dynamic>{...used};
      for (final entry in cache.entries) {
        if (next.length >= _maxCachedFingerprints) break;
        next.putIfAbsent(entry.key, () => entry.value);
      }
      await preferences.setString(_fingerprintCacheKey, jsonEncode(next));
    }
    return keys;
  }

  /// SHA-1 over file size and the first/last 64 KiB, with overlap avoided for
  /// small files. This is fast and stable for byte-identical copies.
  static Future<String> fingerprint(File file, {int? size}) async {
    final length = size ?? await file.length();
    const window = 64 * 1024;
    final handle = await file.open();
    try {
      final first = await handle.read(length < window ? length : window);
      final last = length <= window
          ? const <int>[]
          : await handle
                .setPosition(length - window)
                .then((_) => handle.read(window));
      final bytes = <int>[...utf8.encode('$length:'), ...first, ...last];
      return sha1.convert(bytes).toString();
    } finally {
      await handle.close();
    }
  }

  static Map<String, dynamic> _readFingerprintCache(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_fingerprintCacheKey);
      if (raw == null) return {};
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  /// See [Song.metadataKey].
  static String metadataKey(Song song) => song.metadataKey;

  /// How far apart two durations of the same recording may be: MediaStore
  /// and tag readers often disagree by a second.
  static const durationTolerance = Duration(seconds: 2);

  /// Whether two [metadataKey]s describe the same recording: same artist and
  /// title, durations within [durationTolerance] (an unknown duration
  /// matches any).
  static bool sameRecording(String a, String b) {
    (String, int?) split(String key) {
      final cut = key.lastIndexOf('|');
      return cut < 0
          ? (key, null)
          : (key.substring(0, cut), int.tryParse(key.substring(cut + 1)));
    }

    final (nameA, secondsA) = split(a);
    final (nameB, secondsB) = split(b);
    if (nameA != nameB) return false;
    if (secondsA == null || secondsB == null) return true;
    if (secondsA == 0 || secondsB == 0) return true;
    return (secondsA - secondsB).abs() <= durationTolerance.inSeconds;
  }

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) => other is SongKey && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Moves likes and playlists saved under device-local [Song.id]s onto
/// portable [Song.songKey]s, and remembers each id's key so the next launch
/// can show the right likes before fingerprints are checked again.
///
/// Legacy ids whose track isn't in [songs] stay pending and migrate on a
/// later run, once their track shows up.
class SongKeyMigration {
  const SongKeyMigration._();

  static const mediaIdMapPreference = 'song.keyByMediaId.v1';
  static const likedKeysPreference = 'liked.songKeys.v1';
  static const legacyLikedIdsPreference = 'liked.songIds';
  static const playlistsPreference = 'playlists.v1';

  /// Resolves the keys of [songs] (see [SongKey.resolveAll]) and migrates
  /// pending legacy likes and playlist entries. Returns [songs] with their
  /// [Song.contentKey] set, and whether likes or playlists changed.
  static Future<({List<Song> songs, bool migrated})> run(
    List<Song> songs,
    SharedPreferences preferences,
  ) async {
    final keys = await SongKey.resolveAll(songs, preferences: preferences);
    final keyed = [
      for (var i = 0; i < songs.length; i++)
        keys[i].startsWith('fp:') && songs[i].contentKey != keys[i]
            ? songs[i].withContentKey(keys[i])
            : songs[i],
    ];
    final byId = {
      for (var i = 0; i < songs.length; i++) songs[i].id.toString(): keys[i],
    };
    final encodedMap = jsonEncode(byId);
    if (preferences.getString(mediaIdMapPreference) != encodedMap) {
      await preferences.setString(mediaIdMapPreference, encodedMap);
    }

    final likesMoved = await _migrateLikes(preferences, byId);
    final playlistsMoved = await _migratePlaylists(preferences, byId);
    return (songs: keyed, migrated: likesMoved || playlistsMoved);
  }

  static Future<bool> _migrateLikes(
    SharedPreferences preferences,
    Map<String, String> byId,
  ) async {
    final legacy = preferences.getStringList(legacyLikedIdsPreference);
    if (legacy == null || legacy.isEmpty) return false;
    final liked = {...?preferences.getStringList(likedKeysPreference)};
    final pending = <String>[];
    for (final id in legacy) {
      final key = byId[id];
      if (key == null) {
        pending.add(id);
      } else {
        liked.add(key);
      }
    }
    if (pending.length == legacy.length) return false;
    await preferences.setStringList(likedKeysPreference, liked.toList());
    if (pending.isEmpty) {
      await preferences.remove(legacyLikedIdsPreference);
    } else {
      await preferences.setStringList(legacyLikedIdsPreference, pending);
    }
    return true;
  }

  static Future<bool> _migratePlaylists(
    SharedPreferences preferences,
    Map<String, String> byId,
  ) async {
    final raw = preferences.getString(playlistsPreference);
    if (raw == null || raw.isEmpty) return false;
    final List<Playlist> playlists;
    try {
      playlists = [
        for (final item in jsonDecode(raw) as List)
          Playlist.fromJson(item as Map<String, dynamic>),
      ];
    } catch (_) {
      // Leave malformed user data for the playlists reader.
      return false;
    }
    var changed = false;
    final migrated = <Playlist>[];
    for (final playlist in playlists) {
      final next = _migratePlaylist(playlist, byId);
      if (next != null) changed = true;
      migrated.add(next ?? playlist);
    }
    if (!changed) return false;
    await preferences.setString(
      playlistsPreference,
      jsonEncode([for (final p in migrated) p.toJson()]),
    );
    return true;
  }

  /// [playlist] with its legacy ids that [byId] knows moved to keys, or null
  /// when none could be.
  static Playlist? _migratePlaylist(
    Playlist playlist,
    Map<String, String> byId,
  ) {
    if (playlist.songIds.isEmpty) return null;
    final keys = <String>{...playlist.songKeys};
    final pending = <int>[];
    for (final id in playlist.songIds) {
      final key = byId[id.toString()];
      if (key == null) {
        pending.add(id);
      } else {
        keys.add(key);
      }
    }
    if (pending.length == playlist.songIds.length) return null;
    return playlist.copyWith(songKeys: keys.toList(), songIds: pending);
  }

  /// The key last resolved for the device-local [id], if any.
  static String? keyForMediaId(SharedPreferences preferences, int id) =>
      keysByMediaId(preferences)[id.toString()];

  /// Every id → key mapping from the last run.
  static Map<String, String> keysByMediaId(SharedPreferences preferences) {
    try {
      return Map<String, String>.from(
        jsonDecode(preferences.getString(mediaIdMapPreference) ?? '{}') as Map,
      );
    } catch (_) {
      return const {};
    }
  }
}
