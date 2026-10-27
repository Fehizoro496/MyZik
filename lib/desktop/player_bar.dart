import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../icons.dart';
import '../providers/liked_provider.dart';
import '../providers/playback_provider.dart';
import '../theme.dart';
import '../widgets.dart';
import 'desktop_navigation.dart';
import 'desktop_style.dart';

/// Full-width transport bar along the bottom of the desktop window: the
/// current track on the left, controls and seek bar in the middle, panel
/// toggles and volume on the right.
class DesktopPlayerBar extends ConsumerWidget {
  const DesktopPlayerBar({super.key});

  static const height = 88.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: DesktopColors.bar,
        border: Border(top: BorderSide(color: AppColors.whiteAlpha(0.06))),
      ),
      child: const Row(
        children: [
          Expanded(flex: 3, child: _NowPlayingInfo()),
          Expanded(flex: 4, child: _Transport()),
          Expanded(flex: 3, child: _BarActions()),
        ],
      ),
    );
  }
}

class _NowPlayingInfo extends ConsumerWidget {
  const _NowPlayingInfo();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(playbackProvider.select((p) => p.current));
    if (track == null) {
      return Text(
        'Nothing playing',
        style: TextStyle(color: AppColors.whiteAlpha(0.4), fontSize: 13),
      );
    }
    final liked = ref.watch(isLikedProvider(track.id));
    return Row(
      children: [
        Tooltip(
          message: 'Full screen',
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () =>
                  ref.read(desktopFullscreenProvider.notifier).state = true,
              child: SongArtwork(song: track, size: 56, radius: 10),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.whiteAlpha(0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: liked ? 'Remove from liked' : 'Add to liked',
          iconSize: 18,
          onPressed: () => ref.read(likedProvider.notifier).toggle(track.id),
          icon: Icon(
            liked ? AppIcons.heartFilled : AppIcons.heart,
            color: liked ? AppColors.liked : AppColors.whiteAlpha(0.6),
          ),
        ),
      ],
    );
  }
}

class _Transport extends ConsumerWidget {
  const _Transport();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(playbackProvider.select((p) => p.playing));
    final shuffle = ref.watch(playbackProvider.select((p) => p.shuffle));
    final repeat = ref.watch(playbackProvider.select((p) => p.repeatMode));
    final hasTrack = ref.watch(
      playbackProvider.select((p) => p.current != null),
    );
    final notifier = ref.read(playbackProvider.notifier);
    Color toggled(bool on) =>
        on ? DesktopColors.accentText : AppColors.whiteAlpha(0.66);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Shuffle',
              iconSize: 16,
              onPressed: notifier.toggleShuffle,
              icon: Icon(AppIcons.shuffle, color: toggled(shuffle)),
            ),
            IconButton(
              tooltip: 'Previous (Ctrl+←)',
              iconSize: 18,
              onPressed: hasTrack ? notifier.previous : null,
              icon: const Icon(AppIcons.skipPrevious),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: playing ? 'Pause (Space)' : 'Play (Space)',
              child: Material(
                color: AppColors.white,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: hasTrack ? notifier.togglePlay : null,
                  child: SizedBox(
                    width: 42,
                    height: 42,
                    child: Icon(
                      playing ? AppIcons.pause : AppIcons.playFilled,
                      size: 18,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Next (Ctrl+→)',
              iconSize: 18,
              onPressed: hasTrack ? notifier.next : null,
              icon: const Icon(AppIcons.skipNext),
            ),
            IconButton(
              tooltip: switch (repeat) {
                PlaybackRepeatMode.off => 'Repeat: off',
                PlaybackRepeatMode.all => 'Repeat: all',
                PlaybackRepeatMode.one => 'Repeat: one',
              },
              iconSize: 16,
              onPressed: notifier.cycleRepeatMode,
              icon: Icon(
                repeat == PlaybackRepeatMode.one
                    ? AppIcons.repeatOne
                    : AppIcons.repeat,
                color: toggled(repeat != PlaybackRepeatMode.off),
              ),
            ),
          ],
        ),
        const _SeekBar(),
      ],
    );
  }
}

/// Seek slider with elapsed and total time. Dragging only seeks on release so
/// the player isn't flooded with seeks.
class _SeekBar extends ConsumerStatefulWidget {
  const _SeekBar();

  @override
  ConsumerState<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends ConsumerState<_SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final playback = ref.watch(playbackProvider);
    final labelStyle = TextStyle(
      color: AppColors.whiteAlpha(0.5),
      fontSize: 11,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      children: [
        SizedBox(
          width: 44,
          child: Text(
            playback.elapsed,
            textAlign: TextAlign.right,
            style: labelStyle,
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: AppColors.accentA,
              inactiveTrackColor: AppColors.whiteAlpha(0.12),
              thumbColor: AppColors.white,
            ),
            child: Slider(
              value: _dragValue ?? playback.progress,
              onChanged: playback.current == null
                  ? null
                  : (value) => setState(() => _dragValue = value),
              onChangeEnd: (value) {
                ref.read(playbackProvider.notifier).seekFraction(value);
                setState(() => _dragValue = null);
              },
            ),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(_format(playback.duration), style: labelStyle),
        ),
      ],
    );
  }
}

String _format(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

class _BarActions extends ConsumerStatefulWidget {
  const _BarActions();

  @override
  ConsumerState<_BarActions> createState() => _BarActionsState();
}

class _BarActionsState extends ConsumerState<_BarActions> {
  double? _volume;

  @override
  Widget build(BuildContext context) {
    final panel = ref.watch(desktopPanelProvider);
    final notifier = ref.read(playbackProvider.notifier);
    final volume = _volume ?? notifier.volume;

    Widget panelToggle(DesktopPanel target, IconData icon, String tooltip) {
      final active = panel == target;
      return IconButton(
        tooltip: tooltip,
        iconSize: 18,
        style: IconButton.styleFrom(
          backgroundColor: active
              ? AppColors.accentA.withValues(alpha: 0.14)
              : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        onPressed: () => ref.read(desktopPanelProvider.notifier).state = active
            ? null
            : target,
        icon: Icon(
          icon,
          color: active ? DesktopColors.accentText : AppColors.whiteAlpha(0.66),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        panelToggle(DesktopPanel.lyrics, AppIcons.lyrics, 'Lyrics (Ctrl+L)'),
        const SizedBox(width: 4),
        panelToggle(DesktopPanel.queue, AppIcons.queue, 'Queue (Ctrl+Q)'),
        const SizedBox(width: 8),
        Icon(
          volume == 0
              ? Icons.volume_off_rounded
              : volume < 0.5
              ? Icons.volume_down_rounded
              : Icons.volume_up_rounded,
          size: 18,
          color: AppColors.whiteAlpha(0.6),
        ),
        SizedBox(
          width: 120,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: AppColors.white,
              inactiveTrackColor: AppColors.whiteAlpha(0.15),
              thumbColor: AppColors.white,
            ),
            child: Slider(
              value: volume,
              onChanged: (value) {
                setState(() => _volume = value);
                notifier.setVolume(value);
              },
            ),
          ),
        ),
        IconButton(
          tooltip: 'Full screen',
          iconSize: 17,
          onPressed: () =>
              ref.read(desktopFullscreenProvider.notifier).state = true,
          icon: const Icon(Icons.open_in_full_rounded),
        ),
      ],
    );
  }
}
