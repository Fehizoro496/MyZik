import 'package:flutter/material.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/library_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/playback_provider.dart';
import '../theme.dart';
import '../widgets.dart';

class MyMusicScreen extends ConsumerStatefulWidget {
  const MyMusicScreen({super.key});

  @override
  ConsumerState<MyMusicScreen> createState() => _MyMusicScreenState();
}

class _MyMusicScreenState extends ConsumerState<MyMusicScreen> {
  int _category = 0;

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider);
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
                        onTap: () => ref
                            .read(navigationProvider.notifier)
                            .goTo(AppScreen.home),
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
                    categories: MusicCategories.myMusic,
                    selected: _category,
                    onSelected: (i) => setState(() => _category = i),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(child: _body(library)),
              ],
            ),
          ),
          // Mini-player floats above the shared nav bar.
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

  Widget _body(LibraryState library) {
    if (library.status == LibraryStatus.loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accentA),
      );
    }
    if (library.songs.isEmpty) {
      return _emptyState(library.status);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 170),
      physics: const BouncingScrollPhysics(),
      itemCount: library.songs.length,
      itemBuilder: (context, i) => TrackRow(
        song: library.songs[i],
        onTap: () =>
            ref.read(playbackProvider.notifier).playSong(library.songs[i]),
      ),
      separatorBuilder: (_, _) => const SizedBox(height: 20),
    );
  }

  Widget _emptyState(LibraryStatus status) {
    final denied = status == LibraryStatus.permissionDenied;
    final message = switch (status) {
      LibraryStatus.permissionDenied =>
        'MyZik needs access to your audio files to show your music.',
      LibraryStatus.error => 'Something went wrong reading your library.',
      _ => 'No music found on this device.',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 0, 40, 170),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(IconlyLight.folder, size: 48, color: AppColors.whiteAlpha(0.4)),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.whiteAlpha(0.6), fontSize: 14),
          ),
          if (denied) ...[
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => ref.read(libraryProvider.notifier).load(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  gradient: AppColors.accentGradient,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Text(
                  'Grant access',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
