import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/music_repository.dart';
import '../models.dart';

/// Source of the track library for this platform. A single instance is
/// shared by every provider that needs to read it.
final musicRepositoryProvider = Provider<MusicRepository>((ref) {
  return createMusicRepository();
});

/// Cover artwork for a song id, fetched lazily and cached by Riverpod per
/// argument — replaces the old manual `Map<int, Future<Uint8List?>>` cache.
final artworkProvider = FutureProvider.family<Uint8List?, int>((ref, id) {
  return ref.watch(musicRepositoryProvider).artworkFor(id);
});

/// Loading state of the on-device library.
enum LibraryStatus { loading, ready, empty, permissionDenied, error }

class LibraryState {
  const LibraryState({required this.status, this.songs = const []});

  final LibraryStatus status;
  final List<Song> songs;

  LibraryState copyWith({LibraryStatus? status, List<Song>? songs}) {
    return LibraryState(
      status: status ?? this.status,
      songs: songs ?? this.songs,
    );
  }
}

/// Reads the on-device audio library via [MusicRepository]. Always re-scanned
/// on app start (the device's media store is the source of truth, so nothing
/// here is persisted) but callers can retry via [load] (e.g. after granting
/// permission).
class LibraryNotifier extends Notifier<LibraryState> {
  @override
  LibraryState build() {
    Future.microtask(load);
    return const LibraryState(status: LibraryStatus.loading);
  }

  Future<void> load() async {
    state = state.copyWith(status: LibraryStatus.loading);
    final repo = ref.read(musicRepositoryProvider);
    try {
      final granted = await repo.ensurePermission();
      if (!granted) {
        state = state.copyWith(status: LibraryStatus.permissionDenied);
        return;
      }
      final loaded = await repo.fetchSongs();
      state = LibraryState(
        status: loaded.isEmpty ? LibraryStatus.empty : LibraryStatus.ready,
        songs: loaded,
      );
    } catch (_) {
      state = state.copyWith(status: LibraryStatus.error);
    }
  }
}

final libraryProvider = NotifierProvider<LibraryNotifier, LibraryState>(
  LibraryNotifier.new,
);
