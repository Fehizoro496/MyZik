import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// User agent of [_visionOsClient]. The player sends it when fetching the
/// resolved stream so requests look like they come from the same client.
const youtubeStreamUserAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/26.0 Safari/605.1.15';

// YouTube now requires a PO token for the ANDROID/IOS clients that
// youtube_explode_dart 3.1.0 uses by default: their audio URLs only serve the
// first few bytes and answer 403 afterwards, so playback dies right after it
// starts. The visionOS client still returns fully readable streams without a
// PO token (see Hexer10/youtube_explode_dart#389). Drop this once upstream
// ships an equivalent client.
const _visionOsClient = YoutubeApiClient({
  'context': {
    'client': {
      'clientName': 'VISIONOS',
      'clientVersion': '1.02',
      'deviceMake': 'Apple',
      'deviceModel': 'RealityDevice17,1',
      'userAgent': youtubeStreamUserAgent,
      'osName': 'visionOS',
      'osVersion': '26.5.23O471',
      'hl': 'en',
      'timeZone': 'UTC',
      'utcOffsetMinutes': 0,
    },
  },
}, 'https://www.youtube.com/youtubei/v1/player?prettyPrint=false');

/// Lightweight metadata kept by the app before a playable URL is resolved.
/// YouTube stream URLs are deliberately not stored here because they expire.
class YouTubeTrack {
  const YouTubeTrack({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.duration,
    required this.thumbnailUrl,
  });

  final String videoId;
  final String title;
  final String artist;
  final Duration duration;
  final String thumbnailUrl;
}

abstract class YouTubeRepository {
  Future<List<YouTubeTrack>> search(String query, {int limit = 20});

  /// Resolves a fresh, short-lived URL for the best audio-only stream.
  Future<Uri> resolveAudio(String videoId);

  void close();
}

class YoutubeExplodeRepository implements YouTubeRepository {
  YoutubeExplodeRepository({YoutubeExplode? client})
    : _client = client ?? YoutubeExplode();

  final YoutubeExplode _client;

  @override
  Future<List<YouTubeTrack>> search(String query, {int limit = 20}) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return const [];

    final videos = await _client.search.search(normalized);
    return videos
        .take(limit)
        .map(
          (video) => YouTubeTrack(
            videoId: video.id.value,
            title: video.title,
            artist: video.author,
            duration: video.duration ?? Duration.zero,
            thumbnailUrl: video.thumbnails.highResUrl,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<Uri> resolveAudio(String videoId) async {
    StreamManifest manifest;
    try {
      manifest = await _client.videos.streams.getManifest(
        videoId,
        ytClients: [_visionOsClient],
      );
      if (manifest.audioOnly.isEmpty) throw StateError('no audio stream');
    } catch (_) {
      // Fall back to the library's own client selection.
      manifest = await _client.videos.streams.getManifest(videoId);
    }
    return manifest.audioOnly.withHighestBitrate().url;
  }

  @override
  void close() => _client.close();
}
