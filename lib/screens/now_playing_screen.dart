import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/library_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/playback_provider.dart';
import '../theme.dart';
import '../widgets.dart';

class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackProvider);
    debugPrint(
      'DEBUG repeatMode=${playback.repeatMode} shuffle=${playback.shuffle}',
    );
    final track = playback.current;
    if (track == null) {
      return _empty(ref);
    }
    final notifier = ref.read(playbackProvider.notifier);
    final artwork = ref.watch(artworkProvider(track.id)).asData?.value;
    return Container(
      color: const Color(0xFF0A0A0C),
      child: Stack(
        children: [
          // Ambient background: a heavily blurred, cross-fading copy of the
          // current cover (or its placeholder gradient) so the whole screen
          // reflects the track that's playing, not a fixed theme color.
          Positioned.fill(child: _background(track, artwork)),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
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
                        'Now Playing',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const GlassIconButton(icon: IconlyLight.heart, size: 44),
                    ],
                  ),
                ),
                // Sticky-footer pattern: the artwork/info area fills tall
                // screens (controls pinned to the bottom via the Spacer) and
                // scrolls on shorter ones instead of overflowing.
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: IntrinsicHeight(
                            child: Column(
                              children: [
                                const SizedBox(height: 28),
                                // Circular artwork.
                                Container(
                                  width: 270,
                                  height: 270,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.5,
                                        ),
                                        blurRadius: 70,
                                        offset: const Offset(0, 30),
                                      ),
                                    ],
                                  ),
                                  child: SongArtwork(
                                    song: track,
                                    size: 270,
                                    circle: true,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  track.title,
                                  style: const TextStyle(
                                    color: AppColors.white,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  track.artist,
                                  style: TextStyle(
                                    color: AppColors.whiteAlpha(0.55),
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 22),
                                _lyrics(),
                                const Spacer(),
                                _progressAndControls(playback, notifier),
                                const SizedBox(height: 10),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Ambient, per-track background: the cover art itself, scaled up and
  /// heavily blurred so it reads as atmosphere rather than a picture, with a
  /// dark scrim on top for legibility. Falls back to the track's placeholder
  /// gradient when no embedded artwork is available yet. Cross-fades on
  /// [Song.id] so switching tracks doesn't hard-cut the mood.
  Widget _background(Song track, Uint8List? artwork) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      child: Container(
        key: ValueKey(track.id),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              track.artGradient.first.withValues(alpha: 0.65),
              const Color(0xFF0A0A0C),
            ],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (artwork != null)
              Transform.scale(
                scale: 1.3,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
                  child: Image.memory(artwork, fit: BoxFit.cover),
                ),
              ),
            // Scrim: keeps the top bar and lyrics readable over any cover,
            // regardless of how bright or busy the source image is.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.4),
                    Colors.black.withValues(alpha: 0.35),
                    const Color(0xFF0A0A0C).withValues(alpha: 0.92),
                  ],
                  stops: const [0, 0.45, 1],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shown when Now Playing is opened with no track selected yet.
  Widget _empty(WidgetRef ref) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2A2420), Color(0xFF14110E), Color(0xFF0A0A0C)],
          stops: [0, 0.4, 1],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: GlassIconButton(
                  icon: IconlyLight.arrowLeft2,
                  size: 44,
                  iconSize: 22,
                  onTap: () => ref
                      .read(navigationProvider.notifier)
                      .goTo(AppScreen.home),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Text(
                  'Nothing playing yet.\nPick a track from your library.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.whiteAlpha(0.6),
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lyrics() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Column(
        children: [
          Text(
            'Whispers in the midnight breeze,',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.whiteAlpha(0.3), fontSize: 15),
          ),
          const SizedBox(height: 8),
          const Text(
            'Carrying dreams across the seas,',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'I close my eyes, let go, and drift away.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.whiteAlpha(0.3), fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _progressAndControls(
    PlaybackState playback,
    PlaybackNotifier notifier,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
      child: Column(
        children: [
          // Scrubbable progress bar.
          ProgressBar(
            progress: playback.progress,
            onSeek: notifier.seekFraction,
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                playback.elapsed,
                style: TextStyle(
                  color: AppColors.whiteAlpha(0.55),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                playback.remaining,
                style: TextStyle(
                  color: AppColors.whiteAlpha(0.55),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          // Standard 5-slot transport row with a clear visual hierarchy:
          // play/pause is the largest and brightest (primary), prev/next
          // are mid-sized and slightly dimmed (secondary), shuffle/repeat
          // are the smallest and dim unless active (tertiary toggles).
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _toggleControl(
                icon: Icons.shuffle_rounded,
                active: playback.shuffle,
                onTap: notifier.toggleShuffle,
              ),
              _iconControl(
                Icons.skip_previous_rounded,
                notifier.previous,
                size: 30,
                color: AppColors.whiteAlpha(0.85),
              ),
              _iconControl(
                playback.playing
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                notifier.togglePlay,
                size: 48,
              ),
              _iconControl(
                Icons.skip_next_rounded,
                notifier.next,
                size: 30,
                color: AppColors.whiteAlpha(0.85),
              ),
              _toggleControl(
                // Iconly has no repeat/loop glyph, so this one stays on
                // Material to keep repeat-one distinguishable and readable.
                icon: playback.repeatMode == PlaybackRepeatMode.one
                    ? Icons.repeat_one_rounded
                    : Icons.repeat_rounded,
                active: playback.repeatMode != PlaybackRepeatMode.off,
                onTap: notifier.cycleRepeatMode,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// A dim/lit icon toggle (shuffle, repeat) with a real tap target — the
  /// bare icons they replace had none. Smallest tier of the hierarchy.
  Widget _toggleControl({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Icon(
          icon,
          size: 20,
          color: active ? AppColors.white : AppColors.whiteAlpha(0.45),
        ),
      ),
    );
  }

  /// Prev/play/next: just the icon on a real tap target, no circle chrome.
  Widget _iconControl(
    IconData icon,
    VoidCallback onTap, {
    double size = 26,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Icon(icon, size: size, color: color ?? AppColors.white),
      ),
    );
  }
}

/// The scrubbable playback progress bar.
///
/// Built from a flex-based fill + [Align]ed thumb (rather than
/// [FractionallySizedBox]/[LayoutBuilder]) so it can be laid out inside an
/// [IntrinsicHeight]. Tap/drag maps the local x offset to a 0..1 fraction by
/// reading the track's rendered width at gesture time.
class ProgressBar extends StatefulWidget {
  const ProgressBar({super.key, required this.progress, required this.onSeek});

  final double progress;
  final ValueChanged<double> onSeek;

  @override
  State<ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<ProgressBar> {
  final GlobalKey _trackKey = GlobalKey();

  void _seekTo(Offset localPosition) {
    final box = _trackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || box.size.width == 0) return;
    widget.onSeek(localPosition.dx / box.size.width);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.progress.clamp(0.0, 1.0);
    final fillFlex = (p * 1000).round();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => _seekTo(d.localPosition),
      onHorizontalDragUpdate: (d) => _seekTo(d.localPosition),
      child: SizedBox(
        key: _trackKey,
        height: 20,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            Container(
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.whiteAlpha(0.14),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Row(
              children: [
                Expanded(
                  flex: fillFlex,
                  child: Container(
                    height: 5,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: AppColors.whiteAlpha(0.55),
                      // gradient: const LinearGradient(
                      //   colors: [Color(0xFF4F8CFF), Color(0xFF6F9DFF)],
                      // ),
                    ),
                  ),
                ),
                Expanded(flex: 1000 - fillFlex, child: const SizedBox()),
              ],
            ),
            // Align(
            //   alignment: Alignment(p * 2 - 1, 0),
            //   child: Container(
            //     width: 15,
            //     height: 15,
            //     decoration: BoxDecoration(
            //       shape: BoxShape.circle,
            //       color: AppColors.white,
            //       boxShadow: [
            //         BoxShadow(
            //           color: Colors.black.withValues(alpha: 0.4),
            //           blurRadius: 8,
            //           offset: const Offset(0, 2),
            //         ),
            //       ],
            //     ),
            //   ),
            // ),
          ],
        ),
      ),
    );
  }
}
