import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_iconly/flutter_iconly.dart';

import '../models.dart';
import '../player_controller.dart';
import '../theme.dart';
import '../widgets.dart';

class MyMusicScreen extends StatefulWidget {
  const MyMusicScreen({super.key, required this.controller});

  final PlayerController controller;

  @override
  State<MyMusicScreen> createState() => _MyMusicScreenState();
}

class _MyMusicScreenState extends State<MyMusicScreen> {
  int _category = 0;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.musicBackground),
      child: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                const StatusBar(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GlassIconButton(
                        icon: IconlyLight.arrowLeft2,
                        size: 44,
                        iconSize: 22,
                        onTap: () => c.goTo(AppScreen.home),
                      ),
                      const Text(
                        'My Music',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const GlassIconButton(icon: IconlyLight.moreCircle, size: 44),
                    ],
                  ),
                ),
                SizedBox(
                  height: 44,
                  child: CategoryChips(
                    categories: MusicData.musicCategories,
                    selected: _category,
                    onSelected: (i) => setState(() => _category = i),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 120),
                    physics: const BouncingScrollPhysics(),
                    itemCount: MusicData.songs.length,
                    itemBuilder: (context, i) => TrackRow(
                      track: MusicData.songs[i],
                      onTap: () => c.playTrack(MusicData.songs[i]),
                    ),
                    separatorBuilder: (_, _) => const SizedBox(height: 20),
                  ),
                ),
              ],
            ),
          ),
          _miniPlayer(c),
        ],
      ),
    );
  }

  Widget _miniPlayer(PlayerController c) {
    return Positioned(
      bottom: 30,
      left: 0,
      right: 0,
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: GestureDetector(
              onTap: () => c.goTo(AppScreen.nowPlaying),
              child: Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: const Color(0xBF16161E),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: AppColors.whiteAlpha(0.1)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () => c.goTo(AppScreen.nowPlaying),
                      child: const SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(IconlyBold.play,
                            size: 22, color: AppColors.white),
                      ),
                    ),
                    Container(width: 1, height: 24, color: AppColors.whiteAlpha(0.15)),
                    const SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(IconlyLight.swap,
                          size: 20, color: Color(0xFF4F8CFF)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
