import 'dart:io' show Platform;

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
