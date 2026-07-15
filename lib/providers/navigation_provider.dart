import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppScreen {
  home,
  nowPlaying,
  myMusic,
  liked,
  search,
  discover,
  collection,
  playlist,
  songDetail,
}

/// The screen currently shown by [PlayerShell]. Pure in-memory UI state — not
/// persisted, always starts back on [AppScreen.home].
///
/// Keeps a history stack so [back] (and the system back gesture) return to the
/// screen the user came from instead of a hard-coded destination.
class NavigationNotifier extends Notifier<AppScreen> {
  final List<AppScreen> _history = [];

  @override
  AppScreen build() => AppScreen.home;

  /// Navigates to [screen], remembering the current one so [back] can return to
  /// it. A no-op when already on [screen].
  void goTo(AppScreen screen) {
    if (screen == state) return;
    _history.add(state);
    state = screen;
  }

  /// Pops back to the previous screen. Returns `false` when the history is empty
  /// (we're at the root), so callers can let the system handle the back — i.e.
  /// close the app.
  bool back() {
    if (_history.isEmpty) return false;
    state = _history.removeLast();
    return true;
  }

  /// Whether there's a previous screen to return to.
  bool get canGoBack => _history.isNotEmpty;
}

final navigationProvider = NotifierProvider<NavigationNotifier, AppScreen>(
  NavigationNotifier.new,
);
