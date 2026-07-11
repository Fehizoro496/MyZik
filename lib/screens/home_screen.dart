import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_iconly/flutter_iconly.dart';

import '../models.dart';
import '../player_controller.dart';
import '../theme.dart';
import '../widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final PlayerController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _category = 0;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
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
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 120),
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
                      // Category chips bleed to the screen edges.
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 0),
                        child: SizedBox(
                          height: 44,
                          child: OverflowBox(
                            maxWidth: MediaQuery.of(context).size.width,
                            alignment: Alignment.centerLeft,
                            child: CategoryChips(
                              categories: MusicData.homeCategories,
                              selected: _category,
                              onSelected: (i) => setState(() => _category = i),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 26),
                      _sectionTitle('Curated & trending'),
                      const SizedBox(height: 16),
                      _discoverCard(c),
                      const SizedBox(height: 30),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(child: _sectionTitle('Top daily playlists')),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () => c.goTo(AppScreen.myMusic),
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
                      for (
                        var i = 0;
                        i < MusicData.topPlaylists.length;
                        i++
                      ) ...[
                        TrackRow(
                          track: MusicData.topPlaylists[i],
                          onTap: () => c.playTrack(MusicData.topPlaylists[i]),
                        ),
                        if (i != MusicData.topPlaylists.length - 1)
                          const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          _bottomNav(c),
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
          Row(
            children: [
              const GlassIconButton(icon: IconlyLight.search),
              const SizedBox(width: 12),
              const GlassIconButton(icon: IconlyLight.heart),
            ],
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

  Widget _discoverCard(PlayerController c) {
    return GestureDetector(
      onTap: () => c.playTrack(MusicData.topPlaylists.first),
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

  Widget _bottomNav(PlayerController c) {
    return Positioned(
      left: 22,
      right: 22,
      bottom: 0,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xB816161E),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border(
                top: BorderSide(color: AppColors.whiteAlpha(0.08)),
              ),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 64,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: AppColors.accentGradient,
                        ),
                        child: const Icon(
                          IconlyBold.home,
                          size: 22,
                          color: AppColors.white,
                        ),
                      ),
                      _navIcon(
                        IconlyLight.category,
                        () => c.goTo(AppScreen.myMusic),
                      ),
                      _navIcon(
                        IconlyLight.swap,
                        () => c.goTo(AppScreen.nowPlaying),
                      ),
                      _navIcon(IconlyLight.bookmark, null),
                      _navIcon(IconlyLight.setting, null),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navIcon(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Icon(icon, size: 24, color: AppColors.whiteAlpha(0.55)),
      ),
    );
  }
}
