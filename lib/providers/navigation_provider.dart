import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppScreen { home, nowPlaying, myMusic, saved, settings }

/// The screen currently shown by [PlayerShell]. Pure in-memory UI state — not
/// persisted, always starts back on [AppScreen.home].
class NavigationNotifier extends Notifier<AppScreen> {
  @override
  AppScreen build() => AppScreen.home;

  void goTo(AppScreen screen) => state = screen;
}

final navigationProvider = NotifierProvider<NavigationNotifier, AppScreen>(
  NavigationNotifier.new,
);
