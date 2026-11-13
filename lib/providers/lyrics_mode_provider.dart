import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether Now Playing gives its height to the lyrics, the cover and title
/// shrunk to a header row. Lives as long as the screen does, so the screen
/// always reopens on the cover.
class LyricsModeNotifier extends AutoDisposeNotifier<bool> {
  @override
  bool build() => false;

  /// Asked before closing: resolves to false to keep the lyrics open (a
  /// synchronization in progress that the user wants to keep).
  Future<bool> Function()? closeGuard;

  void open() => state = true;

  Future<void> close() async {
    if (!state) return;
    final guard = closeGuard;
    if (guard != null && !await guard()) return;
    state = false;
  }
}

final lyricsModeProvider =
    NotifierProvider.autoDispose<LyricsModeNotifier, bool>(
      LyricsModeNotifier.new,
    );
