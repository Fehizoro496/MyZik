import 'package:flutter/material.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/library_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/playback_provider.dart';
import '../theme.dart';
import '../widgets.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _category = 0;

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider);
    final topSongs = library.songs.take(4).toList();
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.homeBackground),
      child: Stack(
        children: [
          // Ambient glows top-left / top-right.
          _glow(
            top: -60,
            left: -40,
            w: 280,
            h: 240,
            color: const Color(0x8C785AFF),
          ),
          _glow(
            top: -40,
            right: -40,
            w: 220,
            h: 200,
            color: const Color(0x734F8CFF),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 170),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      _header(),
                      const SizedBox(height: 22),
                      const Text(
                        'Hi, Fehizoro',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _discoverCard(library),
                      const SizedBox(height: 30),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(child: _sectionTitle('Top daily playlists')),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () => ref
                                .read(navigationProvider.notifier)
                                .goTo(AppScreen.myMusic),
                            child: const Text(
                              'See all',
                              style: TextStyle(
                                color: Color(0xFF6F9DFF),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (topSongs.isEmpty)
                        _emptyHint(library.status)
                      else
                        for (var i = 0; i < topSongs.length; i++) ...[
                          TrackRow(
                            song: topSongs[i],
                            onTap: () => ref
                                .read(playbackProvider.notifier)
                                .playSong(topSongs[i], context: topSongs),
                          ),
                          if (i != topSongs.length - 1)
                            const SizedBox(height: 16),
                        ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Positioned(
            left: 22,
            right: 22,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: MiniPlayer(),
                ),
                NavBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _glow({
    double? top,
    double? left,
    double? right,
    required double w,
    required double h,
    required Color color,
  }) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      child: IgnorePointer(
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [color, color.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const CircleAvatar(
            radius: 22,
            backgroundColor: Color(0xFF1A1730),
            backgroundImage: AssetImage('assets/images/avatar.png'),
          ),
          GlassIconButton(
            icon: IconlyLight.search,
            onTap: () =>
                ref.read(navigationProvider.notifier).goTo(AppScreen.search),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.white,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    );
  }

  Widget _emptyHint(LibraryStatus status) {
    final text = switch (status) {
      LibraryStatus.loading => 'Loading your library…',
      LibraryStatus.permissionDenied =>
        'Grant storage access to see your music.',
      LibraryStatus.empty => 'No music found on this device.',
      LibraryStatus.error => 'Could not read your library.',
      LibraryStatus.ready => 'No tracks yet.',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: TextStyle(color: AppColors.whiteAlpha(0.5), fontSize: 14),
      ),
    );
  }

  Widget _discoverCard(LibraryState library) {
    return GestureDetector(
      onTap: () => library.songs.isEmpty
          ? null
          : ref.read(playbackProvider.notifier).playSong(library.songs.first),
      child: Container(
        constraints: const BoxConstraints(minHeight: 172),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4F8CFF), Color(0xFF3B6FE0), Color(0xFF6F5CFF)],
            stops: [0, 0.55, 1],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4F8CFF).withValues(alpha: 0.35),
              blurRadius: 40,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Discover weekly',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 200,
                  child: Text(
                    'The original slow instrumental best playlists.',
                    style: TextStyle(
                      color: AppColors.whiteAlpha(0.85),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF0B1220),
                      ),
                      child: const Icon(
                        IconlyBold.play,
                        size: 20,
                        color: AppColors.white,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      IconlyLight.heart,
                      size: 20,
                      color: AppColors.whiteAlpha(0.9),
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      IconlyLight.download,
                      size: 20,
                      color: AppColors.whiteAlpha(0.9),
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      IconlyLight.moreCircle,
                      size: 22,
                      color: AppColors.whiteAlpha(0.9),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
