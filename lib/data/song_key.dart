import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

/// Cross-device identity for a recording.
class SongKey {
  const SongKey._(this.value);

  final String value;

  static const _fingerprintCacheKey = 'song.fingerprints.v1';

  /// Builds a YouTube key or a cached content fingerprint for a local file.
  /// Songs without either stable source fall back to normalized metadata.
  static Future<SongKey> forSong(
    Song song, {
    SharedPreferences? preferences,
  }) async {
    final videoId = song.youtubeVideoId?.trim();
    if (videoId != null && videoId.isNotEmpty) {
      return SongKey._('yt:$videoId');
    }
    final path = song.filePath;
    if (path != null && path.isNotEmpty) {
      try {
        final file = File(path);
        if (await file.exists()) {
          final stat = await file.stat();
          final cache = preferences == null
              ? <String, dynamic>{}
              : _readFingerprintCache(preferences);
          final cacheId =
              '$path|${stat.size}|${stat.modified.microsecondsSinceEpoch}';
          final cached = cache[cacheId];
          if (cached is String) return SongKey._('fp:$cached');
          final hash = await fingerprint(file, size: stat.size);
          cache[cacheId] = hash;
          // Bound stale path metadata while retaining recent fingerprints.
          while (cache.length > 5000) {
            cache.remove(cache.keys.first);
          }
          if (preferences != null) {
            await preferences.setString(
              _fingerprintCacheKey,
              jsonEncode(cache),
            );
          }
          return SongKey._('fp:$hash');
        }
      } catch (_) {}
    }
    return SongKey._('meta:${metadataKey(song)}');
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

  /// Conservative fallback matching when files have different encodings.
  static String metadataKey(Song song) {
    String normalize(String value) => value
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    return '${normalize(song.artist)}|${normalize(song.title)}|${song.duration.inSeconds}';
  }

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) => other is SongKey && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// One-time bridge from device-local IDs to portable keys. The legacy values
/// remain available to the current UI while canonical key lists are written
/// for future synchronization.
class SongKeyMigration {
  const SongKeyMigration._();

  static const mediaIdMapPreference = 'song.keyByMediaId.v1';
  static const likedKeysPreference = 'liked.songKeys.v1';

  static Future<void> run(
    List<Song> songs,
    SharedPreferences preferences,
  ) async {
    final byId = <String, String>{};
    for (final song in songs) {
      byId[song.id.toString()] = (await SongKey.forSong(
        song,
        preferences: preferences,
      )).value;
    }
    await preferences.setString(mediaIdMapPreference, jsonEncode(byId));

    final oldLikes = preferences.getStringList('liked.songIds') ?? const [];
    final existingLikes =
        preferences.getStringList(likedKeysPreference) ?? const [];
    await preferences.setStringList(
      likedKeysPreference,
      {
        ...existingLikes,
        ...oldLikes.map((id) => byId[id]).whereType<String>(),
      }.toList(),
    );

    final rawPlaylists = preferences.getString('playlists.v1');
    if (rawPlaylists != null && rawPlaylists.isNotEmpty) {
      try {
        final playlists = jsonDecode(rawPlaylists) as List;
        final migrated = [
          for (final item in playlists)
            if (item is Map<String, dynamic>)
              {
                ...item,
                'songKeys': [
                  ...((item['songKeys'] as List? ?? const [])
                      .whereType<String>()),
                  ...(item['songIds'] as List? ?? const [])
                      .map((id) => byId[id.toString()])
                      .whereType<String>()
                      .where(
                        (key) => !(item['songKeys'] as List? ?? const [])
                            .contains(key),
                      ),
                ],
              }
            else
              item,
        ];
        await preferences.setString('playlists.v1', jsonEncode(migrated));
      } catch (_) {
        // Leave malformed user data for the existing defensive reader.
      }
    }
  }

  static String? keyForMediaId(SharedPreferences preferences, int id) {
    try {
      final map =
          jsonDecode(preferences.getString(mediaIdMapPreference) ?? '{}')
              as Map;
      return map[id.toString()] as String?;
    } catch (_) {
      return null;
    }
  }
}
