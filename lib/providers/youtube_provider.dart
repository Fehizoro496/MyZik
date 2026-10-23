import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/youtube_repository.dart';

final youtubeRepositoryProvider = Provider<YouTubeRepository>((ref) {
  final repository = YoutubeExplodeRepository();
  ref.onDispose(repository.close);
  return repository;
});

final youtubeSearchProvider = FutureProvider.autoDispose
    .family<List<YouTubeTrack>, String>((ref, query) {
      return ref.watch(youtubeRepositoryProvider).search(query);
    });
