import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/music_repository.dart';
import '../models.dart';
import 'downloads_provider.dart';

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

/// Encoded cover bytes for any song: read from MediaStore for local tracks,
/// from disk for downloaded ones, and fetched (and de-letterboxed) for
/// streamed ones. Use this rather than
/// [artworkProvider] in UI so remote tracks get the same treatment.
final coverArtProvider = FutureProvider.family<Uint8List?, CoverKey>((
  ref,
  key,
) async {
  final url = key.url;
  if (url == null) return ref.watch(artworkProvider(key.id).future);
  try {
    final uri = Uri.parse(url);
    final bytes = uri.isScheme('file')
        ? await File(uri.toFilePath()).readAsBytes()
        : (await NetworkAssetBundle(uri).load(url)).buffer.asUint8List();
    return _cropLetterbox(bytes);
  } catch (_) {
    return null;
  }
});

/// The perceived dominant colour of a song's cover, used as a per-track accent
/// (e.g. the queue sheet's glow and tint). Null when the track has no artwork —
/// callers then fall back to the placeholder gradient. Cached per cover.
final coverAccentProvider = FutureProvider.family<ui.Color?, CoverKey>((
  ref,
  key,
) async {
  final bytes = await ref.watch(coverArtProvider(key).future);
  if (bytes == null) return null;
  return _dominantColor(bytes);
});

/// YouTube's `hqdefault` thumbnails are 4:3 frames around a 16:9 video, i.e.
/// with black bands above and below. Cropped circles and the blurred player
/// background would show them, so cut the image down to its 16:9 band when
/// both bands are (near-)black. Returns [bytes] untouched otherwise.
Future<Uint8List> _cropLetterbox(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final image = (await codec.getNextFrame()).image;
  try {
    final w = image.width, h = image.height;
    final band = ((h - w * 9 / 16) / 2).floor();
    if (band < 4) return bytes;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return bytes;
    final pixels = data.buffer.asUint8List();

    bool isDark(int fromRow, int toRow) {
      var sum = 0, n = 0;
      for (var y = fromRow; y < toRow; y++) {
        for (var x = 0; x < w; x += 4) {
          final i = (y * w + x) * 4;
          sum += pixels[i] + pixels[i + 1] + pixels[i + 2];
          n += 3;
        }
      }
      return n > 0 && sum / n < 16;
    }

    // Sample just inside each band to tolerate a soft edge at the boundary.
    final probe = band - 2;
    if (!isDark(0, probe) || !isDark(h - probe, h)) return bytes;

    final recorder = ui.PictureRecorder();
    final cropH = h - 2 * band;
    ui.Canvas(recorder).drawImageRect(
      image,
      ui.Rect.fromLTWH(0, band.toDouble(), w.toDouble(), cropH.toDouble()),
      ui.Rect.fromLTWH(0, 0, w.toDouble(), cropH.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    final cropped = await recorder.endRecording().toImage(w, cropH);
    final png = await cropped.toByteData(format: ui.ImageByteFormat.png);
    cropped.dispose();
    return png?.buffer.asUint8List() ?? bytes;
  } finally {
    image.dispose();
  }
}

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
/// permission). Tracks saved by [downloadsProvider] are appended to the
/// device's songs and follow its changes.
class LibraryNotifier extends Notifier<LibraryState> {
  List<Song> _deviceSongs = const [];
  bool _disposed = false;

  @override
  LibraryState build() {
    // [load] awaits the repository; the container may be gone by then.
    ref.onDispose(() => _disposed = true);
    ref.listen(downloadsProvider.select((d) => d.saved), (_, _) {
      if (state.status == LibraryStatus.loading) return;
      final songs = _withDownloads(_deviceSongs);
      state = state.copyWith(
        songs: songs,
        status: switch (state.status) {
          LibraryStatus.ready || LibraryStatus.empty =>
            songs.isEmpty ? LibraryStatus.empty : LibraryStatus.ready,
          final status => status,
        },
      );
    });
    Future.microtask(load);
    return const LibraryState(status: LibraryStatus.loading);
  }

  List<Song> _withDownloads(List<Song> device) => [
    ...device,
    ...ref.read(downloadsProvider).songs,
  ];

  Future<void> load() async {
    state = state.copyWith(status: LibraryStatus.loading);
    final repo = ref.read(musicRepositoryProvider);
    // Wait for saved downloads so the first published library (which playback
    // resume relies on) already contains them.
    await ref.read(downloadsProvider.notifier).ready;
    try {
      final granted = await repo.ensurePermission();
      if (_disposed) return;
      if (!granted) {
        state = LibraryState(
          status: LibraryStatus.permissionDenied,
          songs: _withDownloads(const []),
        );
        return;
      }
      _deviceSongs = await repo.fetchSongs();
      if (_disposed) return;
      final loaded = _withDownloads(_deviceSongs);
      state = LibraryState(
        status: loaded.isEmpty ? LibraryStatus.empty : LibraryStatus.ready,
        songs: loaded,
      );
    } catch (_) {
      if (_disposed) return;
      state = LibraryState(
        status: LibraryStatus.error,
        songs: _withDownloads(const []),
      );
    }
  }
}

final libraryProvider = NotifierProvider<LibraryNotifier, LibraryState>(
  LibraryNotifier.new,
);
