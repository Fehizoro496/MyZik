import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Selected tab index in `MyMusicScreen` (0 = Songs, 1 = Albums, 2 = Artists,
/// 3 = Playlists). Held in a provider so the choice survives navigating away and
/// back — the screen widget is rebuilt from scratch every time [PlayerShell]
/// switches to it, so local state would reset to the first tab.
final myMusicTabProvider = StateProvider<int>((ref) => 0);
