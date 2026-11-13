import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../icons.dart';
import '../models.dart';
import '../providers/library_provider.dart';
import '../providers/liked_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/now_playing_panel_provider.dart';
import '../providers/playback_provider.dart';
import '../theme.dart';
import '../widgets.dart';
import 'lyrics_view.dart';

/// The track playing, on a stage that the cover, the lyrics or the queue
/// take in turn, above transport controls that never move.
///
/// Rebuilds are kept local: this widget only follows the current track and
/// the panel shown, the progress bar alone follows the playhead.
class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(playbackProvider.select((p) => p.current));
    if (track == null) {
      return _empty(ref);
    }
    final artwork = ref.watch(coverArtProvider(track.coverKey)).asData?.value;
    final panel = ref.watch(nowPlayingPanelProvider);
    final panels = ref.read(nowPlayingPanelProvider.notifier);
    return Container(
      color: const Color(0xFF0A0A0C),
      child: Stack(
        children: [
          // Ambient background: a heavily blurred, cross-fading copy of the
          // current cover (or its placeholder gradient) so the whole screen
          // reflects the track that's playing, not a fixed theme color. Its
          // own layer, so the blur isn't redrawn with the controls.
          Positioned.fill(
            child: RepaintBoundary(child: _background(track, artwork)),
          ),
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
                            icon: AppIcons.back,
                            size: 44,
                            iconSize: 22,
                            // Like the back gesture: the cover comes back
                            // before the screen is left.
                            onTap: () => panel != null
                                ? panels.close()
                                : ref.read(navigationProvider.notifier).back(),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _PanelToggle(
                                icon: AppIcons.lyrics,
                                label: 'Lyrics',
                                active: panel == NowPlayingPanel.lyrics,
                                onTap: () =>
                                    panels.toggle(NowPlayingPanel.lyrics),
                              ),
                              const SizedBox(width: 6),
                              _PanelToggle(
                                icon: AppIcons.queue,
                                label: 'Queue',
                                active: panel == NowPlayingPanel.queue,
                                onTap: () =>
                                    panels.toggle(NowPlayingPanel.queue),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: panel != null ? 1 : 0),
                    duration: const Duration(milliseconds: 460),
                    curve: Curves.easeInOutCubic,
                    builder: (context, t, _) => LayoutBuilder(
                      builder: (context, constraints) => _Stage(
                        track: track,
                        // While the cover comes back, the panel that was open
                        // stays on screen as it fades.
                        panel: panel ?? panels.lastShown,
                        t: t,
                        size: constraints.biggest,
                      ),
                    ),
                  ),
                ),
                const _Transport(),
                const SizedBox(height: 10),
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
                  // Blurred beyond recognition anyway: a small decode is
                  // enough and spares memory and GPU uploads.
                  child: Image(
                    image: ResizeImage(
                      MemoryImage(artwork),
                      width: 96,
                      policy: ResizeImagePolicy.fit,
                    ),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
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
                  icon: AppIcons.back,
                  size: 44,
                  iconSize: 22,
                  onTap: () => ref.read(navigationProvider.notifier).back(),
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
}

/// A top-bar button giving the stage to a panel: lit, on a glass disc, while
/// that panel is shown.
class _PanelToggle extends StatelessWidget {
  const _PanelToggle({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? AppColors.whiteAlpha(0.16) : Colors.transparent,
          ),
          child: Icon(
            icon,
            size: 21,
            color: active ? AppColors.white : AppColors.whiteAlpha(0.7),
          ),
        ),
      ),
    );
  }
}

/// Like/unlike the track: next to its title, on the cover as in a panel.
class _LikeButton extends ConsumerWidget {
  const _LikeButton({required this.track});

  final Song track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liked = ref.watch(isLikedProvider(track.songKey));
    return GlassIconButton(
      icon: liked ? AppIcons.heartFilled : AppIcons.heart,
      iconColor: liked ? AppColors.liked : AppColors.white,
      size: 44,
      onTap: () => ref.read(likedProvider.notifier).toggle(track),
    );
  }
}

/// The cover (with title, artist and lyrics teaser) or, at [t] = 1, a
/// [panel]: the cover shrunk to a turning disc in a header row and the panel
/// below it. In between, the cover travels from one place to the other while
/// the two layouts cross-fade.
class _Stage extends ConsumerWidget {
  const _Stage({
    required this.track,
    required this.panel,
    required this.t,
    required this.size,
  });

  final Song track;
  final NowPlayingPanel panel;
  final double t;
  final Size size;

  static const _padding = 24.0;
  static const _headerArtSize = 52.0;
  static const _headerTop = 12.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(playbackProvider.select((p) => p.playing));
    // The full cover gives up some size on short screens so the title and
    // lyrics teaser under it always fit.
    final coverSize = (size.height - 250).clamp(140.0, 270.0);
    final artSize = lerpDouble(coverSize, _headerArtSize, t)!;
    final artLeft = lerpDouble((size.width - coverSize) / 2, _padding, t)!;
    final artTop = lerpDouble(28, _headerTop, t)!;
    const panelTop = _headerTop + _headerArtSize + 10;
    // The cover layout leaves quickly, the panel layout arrives late, so the
    // two never sit on top of each other at half opacity.
    final coverOpacity = (1 - t * 2.5).clamp(0.0, 1.0);
    final panelOpacity = ((t - 0.4) / 0.6).clamp(0.0, 1.0);
    final close = ref.read(nowPlayingPanelProvider.notifier).close;

    return Stack(
      children: [
        // Title, artist and lyrics teaser under the full cover.
        Positioned(
          top: 28 + coverSize + 24 - 16 * t,
          left: _padding,
          right: _padding,
          child: coverOpacity == 0
              ? const SizedBox.shrink()
              : IgnorePointer(
                  ignoring: t > 0,
                  child: Opacity(
                    opacity: coverOpacity,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            // Balances the like button, keeping the title
                            // centred under the cover.
                            const SizedBox(width: 44),
                            Expanded(
                              child: Column(
                                children: [
                                  Text(
                                    track.title,
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.white,
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    track.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: AppColors.whiteAlpha(0.55),
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _LikeButton(track: track),
                          ],
                        ),
                        const SizedBox(height: 22),
                        LyricsPreview(song: track),
                      ],
                    ),
                  ),
                ),
        ),
        // A panel: the header row beside the small disc, then its content.
        Positioned.fill(
          child: t == 0
              ? const SizedBox.shrink()
              : IgnorePointer(
                  ignoring: t < 1,
                  child: Opacity(
                    opacity: panelOpacity,
                    child: Stack(
                      children: [
                        Positioned(
                          top: _headerTop,
                          left: _padding + _headerArtSize + 14,
                          right: _padding,
                          height: _headerArtSize,
                          child: Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: close,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        track.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppColors.white,
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        track.artist,
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
                              ),
                              _LikeButton(track: track),
                            ],
                          ),
                        ),
                        Positioned.fill(
                          top: panelTop,
                          // Lyrics and queue swap in place, the header and
                          // disc staying where they are.
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: switch (panel) {
                              NowPlayingPanel.lyrics => LyricsPanel(
                                key: const ValueKey(NowPlayingPanel.lyrics),
                                song: track,
                              ),
                              NowPlayingPanel.queue => const _QueuePanel(
                                key: ValueKey(NowPlayingPanel.queue),
                              ),
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
        // The cover itself, drawn last so it travels over both layouts.
        Positioned(
          top: artTop,
          left: artLeft,
          width: artSize,
          height: artSize,
          child: GestureDetector(
            onTap: t == 1 ? close : null,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: lerpDouble(70, 18, t)!,
                    offset: Offset(0, lerpDouble(30, 6, t)!),
                  ),
                ],
              ),
              child: _TurningDisc(
                spinning: playing && t == 1,
                unwind: t,
                // Decoded once at the full size and scaled, rather than
                // re-decoded at every size the animation goes through.
                child: FittedBox(
                  child: SongArtwork(
                    song: track,
                    size: coverSize,
                    circle: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Progress bar, times and transport row, pinned under the stage.
class _Transport extends ConsumerWidget {
  const _Transport();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(playbackProvider.notifier);
    final (playing, shuffle, repeatMode) = ref.watch(
      playbackProvider.select((p) => (p.playing, p.shuffle, p.repeatMode)),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
      child: Column(
        children: [
          const _Progress(),
          const SizedBox(height: 22),
          // Standard 5-slot transport row with a clear visual hierarchy:
          // play/pause is the largest and brightest (primary), prev/next
          // are mid-sized and slightly dimmed (secondary), shuffle/repeat
          // are the smallest and dim unless active (tertiary toggles).
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _toggleControl(
                icon: AppIcons.shuffle,
                label: 'Shuffle',
                active: shuffle,
                onTap: notifier.toggleShuffle,
              ),
              _iconControl(
                AppIcons.skipPrevious,
                'Previous',
                notifier.previous,
                size: 30,
                color: AppColors.whiteAlpha(0.85),
              ),
              _iconControl(
                playing ? AppIcons.pause : AppIcons.playFilled,
                playing ? 'Pause' : 'Play',
                notifier.togglePlay,
                size: 48,
              ),
              _iconControl(
                AppIcons.skipNext,
                'Next',
                notifier.next,
                size: 30,
                color: AppColors.whiteAlpha(0.85),
              ),
              _toggleControl(
                // Stays on Material: its rounded repeat/repeat-one pair reads
                // as more clearly distinct at this size than the Iconsax one.
                icon: repeatMode == PlaybackRepeatMode.one
                    ? AppIcons.repeatOne
                    : AppIcons.repeat,
                label: 'Repeat',
                active: repeatMode != PlaybackRepeatMode.off,
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
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      toggled: active,
      label: label,
      child: GestureDetector(
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
      ),
    );
  }

  /// Prev/play/next: just the icon on a real tap target, no circle chrome.
  Widget _iconControl(
    IconData icon,
    String label,
    VoidCallback onTap, {
    double size = 26,
    Color? color,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Icon(icon, size: size, color: color ?? AppColors.white),
        ),
      ),
    );
  }
}

/// The scrubbable progress bar and its times: the only part of the screen
/// that follows the playhead.
class _Progress extends ConsumerWidget {
  const _Progress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (progress, elapsed, remaining) = ref.watch(
      playbackProvider.select((p) => (p.progress, p.elapsed, p.remaining)),
    );
    final timeStyle = TextStyle(
      color: AppColors.whiteAlpha(0.55),
      fontSize: 12,
      fontWeight: FontWeight.w600,
      // Digits keep their width, so the times don't jitter as they count.
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Column(
      children: [
        ProgressBar(
          progress: progress,
          onSeek: ref.read(playbackProvider.notifier).seekFraction,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(elapsed, style: timeStyle),
            Text(remaining, style: timeStyle),
          ],
        ),
      ],
    );
  }
}

/// The cover shrunk into a panel's header turns slowly while the track plays, like a
/// record. [unwind] (the panel transition's progress) scales the angle down to
/// zero as the cover grows back, so the full-size cover is always upright.
class _TurningDisc extends StatefulWidget {
  const _TurningDisc({
    required this.spinning,
    required this.unwind,
    required this.child,
  });

  final bool spinning;
  final double unwind;
  final Widget child;

  @override
  State<_TurningDisc> createState() => _TurningDiscState();
}

class _TurningDiscState extends State<_TurningDisc>
    with SingleTickerProviderStateMixin {
  late final _turns = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didUpdateWidget(_TurningDisc oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  void _update() {
    final spin = widget.spinning && !MediaQuery.disableAnimationsOf(context);
    if (spin && !_turns.isAnimating) {
      _turns.repeat();
    } else if (!spin && _turns.isAnimating) {
      // A paused record stops where it is.
      _turns.stop();
    }
  }

  @override
  void dispose() {
    _turns.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _turns,
      builder: (context, child) => Transform.rotate(
        angle: _turns.value * 2 * math.pi * widget.unwind,
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// The queue panel: what plays after the current track, in queue order. Rows
/// reorder by their handle; tapping one plays it and the panel stays, so
/// several picks can follow each other.
class _QueuePanel extends ConsumerWidget {
  const _QueuePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(playbackProvider.select((p) => p.queue));
    final currentIndex = ref.watch(
      playbackProvider.select((p) => p.currentIndex),
    );
    final shuffle = ref.watch(playbackProvider.select((p) => p.shuffle));
    final notifier = ref.read(playbackProvider.notifier);

    // "Up next" is everything after the current track, in queue order (no
    // wrap — reorder indices must map 1:1 to the queue). `base` is where
    // that slice starts in the full queue.
    final base = (currentIndex != null && currentIndex >= 0)
        ? currentIndex + 1
        : 0;
    final upNext = (base <= queue.length)
        ? queue.sublist(base)
        : const <Song>[];
    final mutedStyle = TextStyle(
      color: AppColors.whiteAlpha(0.45),
      fontSize: 12.5,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 6, 28, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text(
                'Up next',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (upNext.isNotEmpty)
                Text(
                  upNext.length == 1 ? '1 track' : '${upNext.length} tracks',
                  style: mutedStyle,
                ),
            ],
          ),
        ),
        if (shuffle)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 4, 28, 0),
            child: Text(
              'Shuffle is on: these play in a random order.',
              style: mutedStyle,
            ),
          ),
        Expanded(
          child: upNext.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(28, 18, 28, 0),
                  child: Text(
                    'Nothing queued after this track.',
                    style: mutedStyle,
                  ),
                )
              : FadedEdges(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(24, 16, 16, 40),
                    physics: const BouncingScrollPhysics(),
                    buildDefaultDragHandles: false,
                    // The lifted row keeps the screen's glass rather than
                    // Material's opaque card.
                    proxyDecorator: (child, _, _) => DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.whiteAlpha(0.08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: child,
                    ),
                    itemCount: upNext.length,
                    onReorderItem: (oldIndex, newIndex) =>
                        notifier.reorderQueue(
                          base + oldIndex,
                          base + newIndex + (newIndex > oldIndex ? 1 : 0),
                        ),
                    itemBuilder: (context, i) => _UpNextRow(
                      key: ValueKey(upNext[i].id),
                      song: upNext[i],
                      index: i,
                      onTap: () => notifier.playQueueIndex(base + i),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// One upcoming track: cover, title and artist, duration, and a drag handle
/// on the right to reorder the queue. Tapping the rest of the row plays it.
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
        height: 60,
        child: Row(
          children: [
            SongArtwork(song: song, size: 42, radius: 10),
            const SizedBox(width: 14),
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
            // Drag handle: only this initiates a reorder (the list is built
            // with buildDefaultDragHandles: false).
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 12, 8, 12),
                child: Icon(
                  AppIcons.dragHandle,
                  size: 22,
                  color: AppColors.whiteAlpha(0.4),
                ),
              ),
            ),
          ],
        ),
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
