import 'package:flutter/material.dart';
import 'package:flutter_iconly/flutter_iconly.dart';

import '../player_controller.dart';
import '../theme.dart';
import '../widgets.dart';

class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key, required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final track = c.current;
    if (track == null) {
      return _empty(c);
    }
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2A2420), Color(0xFF14110E), Color(0xFF0A0A0C)],
          stops: [0, 0.4, 1],
        ),
      ),
      child: Stack(
        children: [
          // Warm halo behind the artwork.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 340,
            child: IgnorePointer(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topCenter,
                    radius: 0.9,
                    colors: [Color(0x59D2AA8C), Color(0x00D2AA8C)],
                  ),
                ),
              ),
            ),
          ),
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
                        onTap: () => c.goTo(AppScreen.home),
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
                                    controller: c,
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
                                _progressAndControls(c),
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

  /// Shown when Now Playing is opened with no track selected yet.
  Widget _empty(PlayerController c) {
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
                  onTap: () => c.goTo(AppScreen.home),
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

  Widget _progressAndControls(PlayerController c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
      child: Column(
        children: [
          // Scrubbable progress bar.
          ProgressBar(progress: c.progress, onSeek: c.seekFraction),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                c.elapsed,
                style: TextStyle(
                  color: AppColors.whiteAlpha(0.55),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                c.remaining,
                style: TextStyle(
                  color: AppColors.whiteAlpha(0.55),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(
                Icons.shuffle_rounded,
                size: 22,
                color: AppColors.whiteAlpha(0.85),
              ),
              _circleControl(Icons.skip_previous_rounded, 56),
              // Play / pause.
              GestureDetector(
                onTap: c.togglePlay,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.accentGradient,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4F8CFF).withValues(alpha: 0.55),
                        blurRadius: 30,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Icon(
                    c.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 32,
                    color: AppColors.white,
                  ),
                ),
              ),
              _circleControl(Icons.skip_next_rounded, 56),
              Icon(
                Icons.queue_music_rounded,
                size: 24,
                color: AppColors.whiteAlpha(0.85),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _circleControl(IconData icon, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.whiteAlpha(0.08),
        border: Border.all(color: AppColors.whiteAlpha(0.1)),
      ),
      child: Icon(icon, size: 26, color: AppColors.white),
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
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4F8CFF), Color(0xFF6F9DFF)],
                      ),
                    ),
                  ),
                ),
                Expanded(flex: 1000 - fillFlex, child: const SizedBox()),
              ],
            ),
            Align(
              alignment: Alignment(p * 2 - 1, 0),
              child: Container(
                width: 15,
                height: 15,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
