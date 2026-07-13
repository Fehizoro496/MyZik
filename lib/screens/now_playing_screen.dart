import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/library_provider.dart';
import '../providers/liked_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/playback_provider.dart';
import '../theme.dart';
import '../widgets.dart';

class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackProvider);
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
                  // Stack so the title stays centred regardless of how wide the
                  // right-hand action group grows.
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Text(
                        'Now Playing',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Row(
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
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GlassIconButton(
                                icon: Icons.queue_music_rounded,
                                size: 44,
                                iconSize: 22,
                                onTap: () => _showQueue(context, ref),
                              ),
                              const SizedBox(width: 10),
                              GlassIconButton(
                                icon: ref.watch(isLikedProvider(track.id))
                                    ? IconlyBold.heart
                                    : IconlyLight.heart,
                                iconColor: ref.watch(isLikedProvider(track.id))
                                    ? AppColors.liked
                                    : AppColors.white,
                                size: 44,
                                onTap: () => ref
                                    .read(likedProvider.notifier)
                                    .toggle(track.id),
                              ),
                            ],
                          ),
                        ],
                      ),
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

  /// Opens the playback queue (the library in play order) as a bottom sheet,
  /// with the current track highlighted. Tapping a row jumps to that track.
  void _showQueue(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _QueueSheet(),
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

/// The playback queue as a frosted bottom sheet: a "Now Playing" hero on top,
/// then the upcoming tracks in real play order (rotated to start after the
/// current one) strung along a numbered spine.
class _QueueSheet extends ConsumerWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(playbackProvider.select((p) => p.queue));
    final current = ref.watch(playbackProvider.select((p) => p.current));
    final currentIndex = ref.watch(
      playbackProvider.select((p) => p.currentIndex),
    );
    final maxHeight = MediaQuery.of(context).size.height * 0.8;

    // The hero is the current track; "up next" is everything after it in the
    // queue, in queue order (no wrap — reorder indices must map 1:1 to the
    // queue). `base` is where that slice starts in the full queue.
    final hero = current;
    final base = (currentIndex != null && currentIndex >= 0)
        ? currentIndex + 1
        : 0;
    final upNext = (base <= queue.length)
        ? queue.sublist(base)
        : const <Song>[];
    // Per-track accent: the current cover's dominant colour, so the sheet is
    // tinted by what's playing. Falls back to the placeholder gradient while the
    // colour is still being extracted or when the track has no artwork.
    final fallbackAccent =
        (hero ?? current)?.artGradient.first ?? AppColors.accentA;
    final accent = hero == null
        ? fallbackAccent
        : ref.watch(coverAccentProvider(hero.id)).asData?.value ??
              fallbackAccent;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: BoxDecoration(
            color: const Color.fromRGBO(15, 15, 21, 0.86),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            border: Border(top: BorderSide(color: AppColors.whiteAlpha(0.09))),
          ),
          child: Stack(
            children: [
              // Cover-gradient bleed at the top, fading into the glass.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 200,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          accent.withValues(alpha: 0.22),
                          accent.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.whiteAlpha(0.22),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    if (hero == null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 44),
                        child: Text(
                          'Nothing is playing.',
                          style: TextStyle(
                            color: AppColors.whiteAlpha(0.5),
                            fontSize: 14,
                          ),
                        ),
                      )
                    else ...[
                      const SizedBox(height: 6),
                      _QueueHero(song: hero, accent: accent),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 0,
                        ),
                        child: Divider(
                          height: 1,
                          color: AppColors.whiteAlpha(0.08),
                        ),
                      ),
                      Flexible(
                        child: upNext.isEmpty
                            ? Align(
                                alignment: Alignment.topCenter,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    24,
                                    18,
                                    24,
                                    32,
                                  ),
                                  child: Text(
                                    'Nothing queued after this track.',
                                    style: TextStyle(
                                      color: AppColors.whiteAlpha(0.4),
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              )
                            : ReorderableListView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  6,
                                  20,
                                  16,
                                ),
                                physics: const BouncingScrollPhysics(),
                                buildDefaultDragHandles: false,
                                itemCount: upNext.length,
                                onReorder: (oldIndex, newIndex) => ref
                                    .read(playbackProvider.notifier)
                                    .reorderQueue(
                                      base + oldIndex,
                                      base + newIndex,
                                    ),
                                itemBuilder: (context, i) => _UpNextRow(
                                  key: ValueKey(upNext[i].id),
                                  song: upNext[i],
                                  index: i,
                                  onTap: () {
                                    ref
                                        .read(playbackProvider.notifier)
                                        .playQueueIndex(base + i);
                                    Navigator.of(context).pop();
                                  },
                                ),
                              ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "Now Playing" hero at the top of the queue sheet: cover with a
/// gradient halo, a live equalizer, title/artist, and the scrubbable progress
/// bar. Watches only the playback fields it shows, so the queue list below it
/// doesn't rebuild on every position tick.
class _QueueHero extends ConsumerWidget {
  const _QueueHero({required this.song, required this.accent});

  final Song song;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(playbackProvider.select((p) => p.playing));

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.5),
                      blurRadius: 26,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: SongArtwork(song: song, size: 66, radius: 18),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          'NOW PLAYING',
                          style: TextStyle(
                            color: AppColors.whiteAlpha(0.55),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.8,
                          ),
                        ),
                        const SizedBox(width: 10),
                        _EqualizerBars(playing: playing, color: accent),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.whiteAlpha(0.55),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// One upcoming track. The left affordance is a drag handle: press and drag it
/// to reorder the queue. Tapping the rest of the row jumps to that track.
class _UpNextRow extends StatelessWidget {
  const _UpNextRow({
    super.key,
    required this.song,
    required this.index,
    required this.onTap,
  });

  final Song song;

  /// Position within the up-next list, used by the reorder drag listener.
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 58,
        child: Row(
          children: [
            // Drag handle: only this initiates a reorder (the list is built
            // with buildDefaultDragHandles: false).
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
                child: Icon(
                  Icons.drag_handle_rounded,
                  size: 22,
                  color: AppColors.whiteAlpha(0.4),
                ),
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.whiteAlpha(0.45),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              song.durationLabel,
              style: TextStyle(
                color: AppColors.whiteAlpha(0.4),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A tiny four-bar audio equalizer. Bars bounce while [playing]; they hold a
/// staggered static shape when paused or when the platform asks to reduce
/// motion. This is the sheet's signature — the visual language of sound.
class _EqualizerBars extends StatefulWidget {
  const _EqualizerBars({required this.playing, required this.color});

  final bool playing;
  final Color color;

  @override
  State<_EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<_EqualizerBars>
    with SingleTickerProviderStateMixin {
  static const _bars = 4;
  static const _height = 13.0;
  static const _phases = [0.0, 1.4, 0.6, 2.1];

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(_EqualizerBars old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.playing && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!widget.playing || reduceMotion) {
      return _row(const [0.45, 0.85, 0.35, 0.65]);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value * 2 * math.pi;
        return _row([
          for (var i = 0; i < _bars; i++)
            0.28 + 0.72 * (0.5 + 0.5 * math.sin(t + _phases[i])),
        ]);
      },
    );
  }

  Widget _row(List<double> fractions) {
    return SizedBox(
      height: _height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < fractions.length; i++)
            Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 2.5),
              child: Container(
                width: 3,
                height: (_height * fractions[i]).clamp(3.0, _height),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
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
