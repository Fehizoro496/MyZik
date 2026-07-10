import 'package:flutter/material.dart';

import 'player_controller.dart';
import 'screens/home_screen.dart';
import 'screens/my_music_screen.dart';
import 'screens/now_playing_screen.dart';
import 'theme.dart';

void main() {
  runApp(const MyZikApp());
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

/// Owns the [PlayerController] and swaps between the three screens. On wide
/// viewports (desktop / web) the app is framed inside a 390×844 phone mockup;
/// on a phone it fills the screen edge to edge.
class PlayerShell extends StatefulWidget {
  const PlayerShell({super.key});

  @override
  State<PlayerShell> createState() => _PlayerShellState();
}

class _PlayerShellState extends State<PlayerShell> {
  final PlayerController _controller = PlayerController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _screenFor(AppScreen screen) {
    switch (screen) {
      case AppScreen.home:
        return HomeScreen(controller: _controller);
      case AppScreen.nowPlaying:
        return NowPlayingScreen(controller: _controller);
      case AppScreen.myMusic:
        return MyMusicScreen(controller: _controller);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: child,
          ),
          child: KeyedSubtree(
            key: ValueKey(_controller.screen),
            child: _screenFor(_controller.screen),
          ),
        );
      },
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth > 500 || constraints.maxHeight > 900;
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
    );
  }
}
