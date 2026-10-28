import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../sync/sync_files.dart';
import 'app_database_provider.dart';

/// Audio files received from the user's other device, in a private folder.
/// [libraryProvider] lists them alongside the device's own music.
class ReceivedTracksNotifier extends Notifier<List<TrackFile>> {
  /// Completes once the received files are read back from disk.
  late Future<void> ready;

  Future<ReceivedTracksStore>? _store;

  @override
  List<TrackFile> build() {
    ready = _load();
    return const [];
  }

  Future<ReceivedTracksStore> get store => _store ??= () async {
    final base = await getApplicationSupportDirectory();
    return ReceivedTracksStore(
      Directory('${base.path}${Platform.pathSeparator}received'),
      database: ref.read(appDatabaseProvider),
    );
  }();

  Future<void> _load() async {
    try {
      state = await (await store).load();
    } catch (_) {
      // No storage (tests) or unreadable index: nothing received.
    }
  }

  /// Adds the complete [file] of [track], with its [cover], to the library.
  Future<void> add(TrackFile track, File file, {List<int>? cover}) async {
    final stored = await (await store).add(track, file, cover: cover);
    state = [
      for (final t in state)
        if (t.songKey != stored.songKey) t,
      stored,
    ];
  }
}

final receivedTracksProvider =
    NotifierProvider<ReceivedTracksNotifier, List<TrackFile>>(
      ReceivedTracksNotifier.new,
    );
