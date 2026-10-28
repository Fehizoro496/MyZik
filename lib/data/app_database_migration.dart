import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../sync/sync_files.dart';
import 'app_database.dart';
import 'desktop_music_repository.dart';
import 'song_key.dart';

/// Moves the data of older versions (preferences and JSON files) into the
/// database once, then removes the old copies: only after the import has
/// committed, so a failed import leaves them in place for the next launch.
extension AppDatabaseLegacyMigration on AppDatabase {
  Future<void> migrateLegacy({
    required SharedPreferences preferences,
    required Directory supportDirectory,
  }) async {
    if (!await isMigrated('legacy.v1')) {
      await _importLegacy(preferences, supportDirectory);
    }
    if (!await isMigrated('legacy.cleanup.v1')) {
      await _removeLegacy(preferences, supportDirectory);
      await markDone('legacy.cleanup.v1');
    }
  }

  /// Preference keys whose data now lives in the database.
  static const _movedPreferences = [
    SongKeyMigration.likedKeysPreference,
    'sync.state.v1',
    'sync.deviceId',
    'sync.client.v1',
    'sync.pairedDevices.v1',
    'song.fingerprints.v1',
    'downloads.tracks',
    DesktopMusicRepository.foldersPreference,
  ];

  /// Removes the old copies of what the database now holds. Legacy ids
  /// still waiting for their track stay (`SongKeyMigration` moves them when
  /// it shows up), and so do the received audio files and covers.
  Future<void> _removeLegacy(
    SharedPreferences preferences,
    Directory supportDirectory,
  ) async {
    final idMap = _idMap(preferences);
    for (final key in _movedPreferences) {
      await preferences.remove(key);
    }

    final legacyLikes =
        preferences.getStringList(SongKeyMigration.legacyLikedIdsPreference) ??
        const <String>[];
    final pendingLikes = [
      for (final id in legacyLikes)
        if (!idMap.containsKey(id)) id,
    ];
    if (pendingLikes.isEmpty) {
      await preferences.remove(SongKeyMigration.legacyLikedIdsPreference);
    } else {
      await preferences.setStringList(
        SongKeyMigration.legacyLikedIdsPreference,
        pendingLikes,
      );
    }

    final pendingPlaylists = <Map<String, dynamic>>[];
    try {
      final raw = preferences.getString(SongKeyMigration.playlistsPreference);
      for (final entry in raw == null ? const [] : jsonDecode(raw) as List) {
        if (entry is! Map) continue;
        final pending = [
          for (final id in entry['songIds'] as List? ?? const [])
            if (!idMap.containsKey(id.toString())) id,
        ];
        if (pending.isEmpty) continue;
        pendingPlaylists.add({
          'id': entry['id'],
          'name': entry['name'],
          'songKeys': const <String>[],
          'songIds': pending,
        });
      }
    } catch (_) {
      // Unreadable: nothing left to migrate from it.
    }
    if (pendingPlaylists.isEmpty) {
      await preferences.remove(SongKeyMigration.playlistsPreference);
    } else {
      await preferences.setString(
        SongKeyMigration.playlistsPreference,
        jsonEncode(pendingPlaylists),
      );
    }

    final separator = Platform.pathSeparator;
    for (final entity in [
      Directory('${supportDirectory.path}${separator}lyrics'),
      File('${supportDirectory.path}${separator}library_index.json'),
      File(
        '${supportDirectory.path}${separator}received${separator}index.json',
      ),
    ]) {
      try {
        if (entity.existsSync()) await entity.delete(recursive: true);
      } catch (e) {
        // Left behind: harmless, the database is the source now.
        debugPrint('Legacy cleanup: cannot delete ${entity.path}: $e');
      }
    }
  }

  static Map<String, String> _idMap(SharedPreferences preferences) {
    try {
      return Map<String, String>.from(
        jsonDecode(
              preferences.getString(SongKeyMigration.mediaIdMapPreference) ??
                  '{}',
            )
            as Map,
      );
    } catch (_) {
      return const {};
    }
  }

  Future<void> _importLegacy(
    SharedPreferences preferences,
    Directory supportDirectory,
  ) async {
    final likes =
        (preferences.getStringList(SongKeyMigration.likedKeysPreference) ??
                const <String>[])
            .toSet();
    final idMap = <String, String>{};
    try {
      idMap.addAll(
        Map<String, String>.from(
          jsonDecode(
                preferences.getString(SongKeyMigration.mediaIdMapPreference) ??
                    '{}',
              )
              as Map,
        ),
      );
    } catch (_) {}
    for (final id
        in preferences.getStringList(
              SongKeyMigration.legacyLikedIdsPreference,
            ) ??
            const []) {
      if (idMap[id] case final key?) likes.add(key);
    }

    final playlists = <Map<String, dynamic>>[];
    try {
      final raw = preferences.getString(SongKeyMigration.playlistsPreference);
      if (raw != null) {
        for (final entry in jsonDecode(raw) as List) {
          if (entry is! Map) continue;
          final keys = <String>[
            for (final key in entry['songKeys'] as List? ?? const [])
              if (key is String) key,
          ];
          for (final id in entry['songIds'] as List? ?? const []) {
            if (idMap[id.toString()] case final key? when !keys.contains(key)) {
              keys.add(key);
            }
          }
          playlists.add({
            'id': entry['id'] as String,
            'name': entry['name'] as String? ?? 'Playlist',
            'songKeys': keys,
          });
        }
      }
    } catch (_) {}

    final lyrics = <String, Map<String, dynamic>>{};
    final lyricsDir = Directory(
      '${supportDirectory.path}${Platform.pathSeparator}lyrics',
    );
    if (lyricsDir.existsSync()) {
      await for (final entity in lyricsDir.list(followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        try {
          final record = jsonDecode(await entity.readAsString());
          if (record is! Map) continue;
          final filename = entity.uri.pathSegments.last.replaceFirst(
            RegExp(r'\.json$'),
            '',
          );
          final key =
              record['_songKey'] as String? ??
              _keyFromFilename(filename) ??
              idMap[filename];
          if (key != null) lyrics[key] = Map<String, dynamic>.from(record);
        } catch (_) {}
      }
    }

    final syncState = <String, String>{};
    final syncRecords = <String, Map<String, Object?>>{};
    try {
      final state =
          jsonDecode(preferences.getString('sync.state.v1') ?? '{}')
              as Map<String, dynamic>;
      final records = state['records'] as Map<String, dynamic>? ?? const {};
      for (final entry in records.entries) {
        final row = entry.value;
        if (row is! List || row.length < 3) continue;
        final flags = row.length > 3 ? row[3] as int? ?? 0 : 0;
        syncRecords[entry.key] = {
          'sequence': row[0],
          'updatedAt': row[1],
          'origin': row[2],
          'deleted': flags & 1 != 0,
          'found': flags & 2 != 0,
        };
      }
      syncState['sequence'] = (state['seq'] as int? ?? 0).toString();
    } catch (_) {}
    if (preferences.getString('sync.deviceId') case final deviceId?) {
      syncState['deviceId'] = deviceId;
    }
    if (preferences.getString('sync.client.v1') case final clientState?) {
      syncState['sync.client.v1'] = clientState;
    }

    final paired = <Map<String, dynamic>>[];
    try {
      for (final row
          in jsonDecode(preferences.getString('sync.pairedDevices.v1') ?? '[]')
              as List) {
        if (row is Map<String, dynamic>) paired.add(row);
      }
    } catch (_) {}

    final fingerprints = <String, String>{};
    try {
      final old =
          jsonDecode(preferences.getString('song.fingerprints.v1') ?? '{}')
              as Map;
      for (final entry in old.entries) {
        if (entry.key is String && entry.value is String) {
          fingerprints[entry.key as String] = 'fp:${entry.value}';
        }
      }
    } catch (_) {}

    final libraryIndex = <String, String>{};
    final oldLibraryIndex = File(
      '${supportDirectory.path}${Platform.pathSeparator}library_index.json',
    );
    try {
      if (oldLibraryIndex.existsSync()) {
        for (final raw
            in jsonDecode(await oldLibraryIndex.readAsString()) as List) {
          final item = IndexedTrack.tryFromJson(raw);
          if (item != null) libraryIndex[item.path] = jsonEncode(item.toJson());
        }
      }
    } catch (_) {}

    final downloads = <String, String>{};
    for (final raw
        in preferences.getStringList('downloads.tracks') ?? const []) {
      try {
        final item = jsonDecode(raw) as Map<String, dynamic>;
        downloads[item['videoId'] as String] = jsonEncode(item);
      } catch (_) {}
    }

    final receivedFiles = <String, String>{};
    final receivedIndex = File(
      '${supportDirectory.path}${Platform.pathSeparator}received${Platform.pathSeparator}index.json',
    );
    try {
      if (receivedIndex.existsSync()) {
        for (final raw
            in jsonDecode(await receivedIndex.readAsString()) as List) {
          final track = TrackFile.tryFromJson(raw);
          if (track != null) {
            receivedFiles[track.songKey] = jsonEncode(
              track.toJson(withPath: true),
            );
          }
        }
      }
    } catch (_) {}

    final folders = preferences.getStringList(
      DesktopMusicRepository.foldersPreference,
    );
    await importLegacyRows(
      likes: likes,
      playlists: playlists,
      lyrics: lyrics,
      syncRecords: syncRecords,
      syncState: syncState,
      pairedDevices: paired,
      fingerprints: fingerprints,
      libraryIndex: libraryIndex,
      downloads: downloads,
      receivedFiles: receivedFiles,
      settings: {
        if (folders != null)
          DesktopMusicRepository.foldersPreference: jsonEncode(folders),
      },
    );
  }

  static String? _keyFromFilename(String filename) {
    final match = RegExp(r'^(fp|yt)_(.+)$').firstMatch(filename);
    return match == null ? null : '${match[1]}:${match[2]}';
  }
}
