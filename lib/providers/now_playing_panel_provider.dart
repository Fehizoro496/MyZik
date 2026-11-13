import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What can take Now Playing's stage from the cover.
enum NowPlayingPanel { lyrics, queue }

/// The panel holding Now Playing's stage, the cover shrunk to a header row
/// above it; null while the cover has it. Lives as long as the screen does,
/// so the screen always reopens on the cover.
class NowPlayingPanelNotifier extends AutoDisposeNotifier<NowPlayingPanel?> {
  @override
  NowPlayingPanel? build() => null;

  /// The panel shown last, kept on screen while the stage goes back to the
  /// cover.
  NowPlayingPanel lastShown = NowPlayingPanel.lyrics;

  /// Asked before leaving the lyrics: resolves to false to stay (a
  /// synchronization in progress that the user wants to keep).
  Future<bool> Function()? leaveLyricsGuard;

  /// Gives the stage to [panel], or back to the cover when null.
  Future<void> show(NowPlayingPanel? panel) async {
    if (panel == state) return;
    final guard = leaveLyricsGuard;
    if (state == NowPlayingPanel.lyrics && guard != null && !await guard()) {
      return;
    }
    if (panel != null) lastShown = panel;
    state = panel;
  }

  /// Shows [panel], or the cover again when it is already shown.
  Future<void> toggle(NowPlayingPanel panel) =>
      show(state == panel ? null : panel);

  Future<void> close() => show(null);
}

final nowPlayingPanelProvider =
    NotifierProvider.autoDispose<NowPlayingPanelNotifier, NowPlayingPanel?>(
      NowPlayingPanelNotifier.new,
    );
