import 'package:flutter/material.dart';
import 'package:flutter_iconly/flutter_iconly.dart';

import '../models.dart';
import '../player_controller.dart';
import '../theme.dart';
import '../widgets.dart';

/// The "Saved" library: liked-songs hero card + the list of saved tracks.
class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key, required this.controller});

  final PlayerController controller;

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
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
                        'Saved',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const GlassIconButton(icon: IconlyLight.search, size: 44),
                    ],
                  ),
                ),
                SizedBox(
                  height: 44,
                  child: CategoryChips(
                    categories: MusicCategories.saved,
                    selected: _category,
                    onSelected: (i) => setState(() => _category = i),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 120),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      _likedCard(c),
                      const SizedBox(height: 26),
                      for (var i = 0; i < c.songs.length; i++) ...[
                        TrackRow(
                          controller: c,
                          song: c.songs[i],
                          onTap: () => c.playSong(c.songs[i]),
                        ),
                        if (i != c.songs.length - 1) const SizedBox(height: 20),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 22,
            right: 22,
            bottom: 0,
            child: FloatingNavBar(controller: c),
          ),
        ],
      ),
    );
  }

  Widget _likedCard(PlayerController c) {
    return GestureDetector(
      onTap: () => c.songs.isEmpty ? null : c.playSong(c.songs.first),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF6F91), Color(0xFF8A4FFF)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8A4FFF).withValues(alpha: 0.3),
              blurRadius: 36,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.whiteAlpha(0.18),
              ),
              child: const Icon(
                IconlyBold.heart,
                size: 26,
                color: AppColors.white,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Liked Songs',
                    style: TextStyle(
                      color: AppColors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${c.songs.length} songs · Auto playlist',
                    style: TextStyle(
                      color: AppColors.whiteAlpha(0.85),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 44,
              height: 44,
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
          ],
        ),
      ),
    );
  }
}
