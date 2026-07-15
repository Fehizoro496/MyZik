import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';

/// The song currently shown in `SongDetailScreen`. Set right before navigating
/// to [AppScreen.songDetail]. Holds the full [Song] (not just an id) so it works
/// for tracks from any source — library, search results, a playlist.
final selectedSongProvider = StateProvider<Song?>((ref) => null);
