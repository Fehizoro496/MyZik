import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'desktop_music_repository.dart';
import 'device_music_repository.dart';
import 'sample_music_repository.dart';

/// Source of the track library. Implementations map their native rows into the
/// neutral [Song] model so the controller/UI stay platform-agnostic.
abstract class MusicRepository {
  /// Whether this platform can read an on-device library at all.
  bool get isSupported;

  /// Request (and re-check) read permission. Returns true when granted.
  Future<bool> ensurePermission();

  /// Load the full library. Call only after [ensurePermission] succeeds.
  Future<List<Song>> fetchSongs();

  /// Embedded cover artwork bytes for a song, or null when there is none.
  /// Fetched lazily (per visible row) because it is not part of the song row.
  Future<Uint8List?> artworkFor(int id);
}

/// Picks the right repository for the current platform: the device's media
/// library on phones, the user's music folders on computers (listed in
/// [preferences]), sample data on the web.
MusicRepository createMusicRepository(SharedPreferences preferences) {
  if (kIsWeb) return SampleMusicRepository();
  if (Platform.isAndroid || Platform.isIOS) return DeviceMusicRepository();
  return DesktopMusicRepository(preferences: preferences);
}
