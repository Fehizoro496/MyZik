import 'dart:typed_data';
import 'dart:ui' as ui;

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

/// The perceived dominant colour of a song's cover, used as a per-track accent
/// (e.g. the queue sheet's glow and tint). Null when the track has no embedded
/// artwork — callers then fall back to the placeholder gradient. Cached per id.
final coverAccentProvider = FutureProvider.family<ui.Color?, int>((
  ref,
  id,
) async {
  final bytes = await ref.watch(artworkProvider(id).future);
  if (bytes == null) return null;
  return _dominantColor(bytes);
});

/// Extracts the dominant colour from encoded image [bytes]. Downscales to a
/// 32×32 thumbnail, buckets pixels by a coarse quantisation, and returns the
/// fullest bucket's average — but near-black, near-white and greyish buckets
/// are down-weighted so the accent is a real hue from the cover rather than a
/// muddy background wash. Returns null if the image can't be read.
Future<ui.Color?> _dominantColor(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: 32,
    targetHeight: 32,
  );
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  if (data == null) return null;

  final pixels = data.buffer.asUint8List();
  final counts = <int, int>{};
  final sums = <int, List<int>>{}; // bucket key -> [rSum, gSum, bSum, n]

  for (var i = 0; i + 3 < pixels.length; i += 4) {
    if (pixels[i + 3] < 128) continue; // skip (near-)transparent pixels
    final r = pixels[i], g = pixels[i + 1], b = pixels[i + 2];
    final key = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4); // 4 bits/channel
    counts[key] = (counts[key] ?? 0) + 1;
    final s = sums.putIfAbsent(key, () => [0, 0, 0, 0]);
    s[0] += r;
    s[1] += g;
    s[2] += b;
    s[3] += 1;
  }
  if (counts.isEmpty) return null;

  var bestKey = -1;
  var bestScore = -1.0;
  counts.forEach((key, n) {
    final s = sums[key]!;
    final r = s[0] / s[3], g = s[1] / s[3], b = s[2] / s[3];
    final maxc = [r, g, b].reduce((a, c) => a > c ? a : c);
    final minc = [r, g, b].reduce((a, c) => a < c ? a : c);
    final sat = maxc <= 0 ? 0.0 : (maxc - minc) / maxc;
    final lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0;
    final lumWeight = 1.0 - (2 * lum - 1).abs(); // peaks at mid luminance
    final score = n * (0.35 + 0.65 * sat) * (0.4 + 0.6 * lumWeight);
    if (score > bestScore) {
      bestScore = score;
      bestKey = key;
    }
  });

  final s = sums[bestKey]!;
  return ui.Color.fromARGB(
    255,
    (s[0] / s[3]).round(),
    (s[1] / s[3]).round(),
    (s[2] / s[3]).round(),
  );
}

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
