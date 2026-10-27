import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';

/// Top-level destinations listed in the desktop sidebar.
enum DesktopSection { home, songs, albums, artists, liked, playlists, discover }

/// A page of the desktop shell: a sidebar [section], optionally narrowed to
/// one album/artist ([collection]), one playlist ([playlistId]) or library
/// search results ([query]).
class DesktopRoute {
  const DesktopRoute(
    this.section, {
    this.collection,
    this.playlistId,
    this.query,
  });

  const DesktopRoute.search(String this.query)
    : section = DesktopSection.songs,
      collection = null,
      playlistId = null;

  final DesktopSection section;
  final MusicCollection? collection;
  final String? playlistId;
  final String? query;

  bool get isSearch => query != null;
}

/// The page shown by the desktop shell, with browser-like back/forward
/// history. Independent from the mobile [navigationProvider], which playback
/// still drives (it opens Now Playing) without affecting the desktop layout.
class DesktopNavigator extends Notifier<DesktopRoute> {
  final _back = <DesktopRoute>[];
  final _forward = <DesktopRoute>[];

  @override
  DesktopRoute build() => const DesktopRoute(DesktopSection.home);

  void open(DesktopRoute route) {
    _back.add(state);
    _forward.clear();
    state = route;
  }

  /// Opens a sidebar section, unless it is already shown as is.
  void openSection(DesktopSection section) {
    if (state.section == section &&
        state.collection == null &&
        state.playlistId == null &&
        !state.isSearch) {
      return;
    }
    open(DesktopRoute(section));
  }

  /// Shows library results for [query], replacing previous results rather
  /// than stacking one history entry per keystroke.
  void search(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      if (state.isSearch) back();
      return;
    }
    if (state.isSearch) {
      state = DesktopRoute.search(trimmed);
    } else {
      open(DesktopRoute.search(trimmed));
    }
  }

  bool get canGoBack => _back.isNotEmpty;
  bool get canGoForward => _forward.isNotEmpty;

  void back() {
    if (_back.isEmpty) return;
    _forward.add(state);
    state = _back.removeLast();
  }

  void forward() {
    if (_forward.isEmpty) return;
    _back.add(state);
    state = _forward.removeLast();
  }
}

final desktopNavigatorProvider =
    NotifierProvider<DesktopNavigator, DesktopRoute>(DesktopNavigator.new);

/// What the right-hand panel shows, or null when it is closed.
enum DesktopPanel { lyrics, queue }

final desktopPanelProvider = StateProvider<DesktopPanel?>(
  (ref) => DesktopPanel.lyrics,
);

/// Whether Now Playing fills the window instead of the library layout.
final desktopFullscreenProvider = StateProvider<bool>((ref) => false);
