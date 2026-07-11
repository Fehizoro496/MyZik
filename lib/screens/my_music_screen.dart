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
                      const GlassIconButton(
                        icon: IconlyLight.moreCircle,
                        size: 44,
                      ),
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
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 170),
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
          // Mini-player floats above the shared nav bar.
          Positioned(
            left: 22,
            right: 22,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: MiniPlayer(controller: c),
                ),
                FloatingNavBar(controller: c),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
