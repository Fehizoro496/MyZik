import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../models.dart';
import 'device_music_repository.dart';
import 'sample_music_repository.dart';

/// Source of the track library. Implementations map their native rows into the
/// neutral [Song] model so the controller/UI stay platform-agnostic.
///
/// Add a `DesktopMusicRepository` (folder scan + tag reading) later and wire it
/// into [createMusicRepository] — nothing else needs to change.
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

/// Picks the right repository for the current platform.
MusicRepository createMusicRepository() {
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    return DeviceMusicRepository();
  }
  // Desktop / web: real file-scanning support is planned. Until then a sample
  // library keeps the UI populated during development.
  return SampleMusicRepository();
}
