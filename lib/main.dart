import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/audio_handler.dart';
import 'providers/navigation_provider.dart';
import 'providers/shared_preferences_provider.dart';
import 'screens/collection_screen.dart';
import 'screens/home_screen.dart';
import 'screens/my_music_screen.dart';
import 'screens/now_playing_screen.dart';
import 'screens/liked_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  // Start the OS media session so headset/Bluetooth, lock-screen and
  // notification transport controls are wired up before the UI builds.
  final audioHandler = await AudioService.init(
    builder: MyZikAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.my_zik.audio',
      androidNotificationChannelName: 'Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        audioHandlerProvider.overrideWithValue(audioHandler),
      ],
      child: const MyZikApp(),
    ),
  );
}

class MyZikApp extends StatelessWidget {
  const MyZikApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Zik',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const PlayerShell(),
    );
  }
}

/// Swaps between the app's screens based on [navigationProvider]. On wide
/// viewports (desktop / web) the app is framed inside a 390×844 phone mockup;
/// on a phone it fills the screen edge to edge.
class PlayerShell extends ConsumerWidget {
  const PlayerShell({super.key});

  Widget _screenFor(AppScreen screen) {
    switch (screen) {
      case AppScreen.home:
        return const HomeScreen();
      case AppScreen.nowPlaying:
        return const NowPlayingScreen();
      case AppScreen.myMusic:
        return const MyMusicScreen();
      case AppScreen.liked:
        return const LikedScreen();
      case AppScreen.search:
        return const SearchScreen();
      case AppScreen.settings:
        return const SettingsScreen();
      case AppScreen.collection:
        return const CollectionScreen();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screen = ref.watch(navigationProvider);
    final canGoBack = ref.read(navigationProvider.notifier).canGoBack;
    final app = AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: KeyedSubtree(key: ValueKey(screen), child: _screenFor(screen)),
    );

    // Route the system/hardware back gesture through the in-app history stack:
    // pop to the previous screen while there is one, and only let the pop reach
    // the OS (closing the app) once we're back at the root.
    return PopScope(
      canPop: !canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        ref.read(navigationProvider.notifier).back();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final wide =
                constraints.maxWidth > 500 || constraints.maxHeight > 900;
            if (!wide) return app;
            // Phone-frame presentation for desktop / web.
            return Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-0.6, -1),
                  radius: 1.4,
                  colors: [Color(0xFF1A1730), Color(0xFF08080C)],
                ),
              ),
              alignment: Alignment.center,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(46),
                child: SizedBox(
                  width: 390,
                  height: 844,
                  child: MediaQuery(
                    // Give the framed app a realistic notch inset.
                    data: MediaQuery.of(context).copyWith(
                      padding: const EdgeInsets.only(top: 0, bottom: 0),
                    ),
                    child: app,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
