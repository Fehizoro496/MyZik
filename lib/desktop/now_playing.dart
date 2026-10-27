import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/lyrics_structure.dart';
import '../icons.dart';
import '../models.dart';
import '../providers/library_provider.dart';
import '../providers/liked_provider.dart';
import '../providers/lyrics_provider.dart';
import '../providers/playback_provider.dart';
import '../screens/lyrics_view.dart';
import '../theme.dart';
import '../widgets.dart';
import 'desktop_navigation.dart';
import 'desktop_style.dart';
import 'lyrics_editor.dart';
import 'side_panel.dart';

/// Now Playing filling the window: large artwork and controls on the left,
/// the lyrics in large type on the right, over a glow tinted by the cover.
/// Esc (or the chevron) goes back to the library layout.
class DesktopNowPlaying extends ConsumerWidget {
  const DesktopNowPlaying({super.key});

  void _exit(WidgetRef ref) =>
      ref.read(desktopFullscreenProvider.notifier).state = false;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(playbackProvider.select((p) => p.current));
    final glow = track == null
        ? AppColors.accentB
        : ref.watch(coverAccentProvider(track.coverKey)).asData?.value ??
              track.artGradient.first;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.homeBackground,
        gradient: RadialGradient(
          center: const Alignment(-0.55, -0.4),
          radius: 1.1,
          colors: [glow.withValues(alpha: 0.38), AppColors.homeBackground],
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Exit full screen (Esc)',
                  iconSize: 20,
                  onPressed: () => _exit(ref),
                  icon: const Icon(AppIcons.chevronDown),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text('NOW PLAYING', style: DesktopText.overline),
                      if (track?.album != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          track!.album!,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
          ),
          Expanded(
            child: track == null
                ? Center(
                    child: Text(
                      'Nothing playing',
                      style: TextStyle(color: AppColors.whiteAlpha(0.6)),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.fromLTRB(64, 24, 64, 40),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Flexible(
                          flex: 4,
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 440),
                              child: _PlayerColumn(track: track),
                            ),
                          ),
                        ),
                        const SizedBox(width: 80),
                        Flexible(
                          flex: 5,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 640),
                              child: _LyricsColumn(track: track),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PlayerColumn extends ConsumerStatefulWidget {
  const _PlayerColumn({required this.track});

  final Song track;

  @override
  ConsumerState<_PlayerColumn> createState() => _PlayerColumnState();
}

class _PlayerColumnState extends ConsumerState<_PlayerColumn> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final playback = ref.watch(playbackProvider);
    final notifier = ref.read(playbackProvider.notifier);
    final liked = ref.watch(isLikedProvider(track.songKey));
    final muted = TextStyle(
      color: AppColors.whiteAlpha(0.7),
      fontSize: 12,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Color toggled(bool on) =>
        on ? DesktopColors.accentText : AppColors.whiteAlpha(0.78);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Leave room under the cover for the title, seek bar and controls.
        final cover = constraints.maxWidth.clamp(
          160.0,
          (constraints.maxHeight - 250).clamp(160.0, 440.0),
        );
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 80,
                      offset: const Offset(0, 40),
                      spreadRadius: -24,
                    ),
                  ],
                ),
                child: SongArtwork(song: track, size: cover, radius: 28),
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.whiteAlpha(0.72),
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: liked ? 'Remove from liked' : 'Add to liked',
                  iconSize: 24,
                  onPressed: () =>
                      ref.read(likedProvider.notifier).toggle(track),
                  icon: Icon(
                    liked ? AppIcons.heartFilled : AppIcons.heart,
                    color: liked ? AppColors.liked : AppColors.whiteAlpha(0.78),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: AppColors.white,
                inactiveTrackColor: AppColors.whiteAlpha(0.14),
                thumbColor: AppColors.white,
              ),
              child: Slider(
                padding: EdgeInsets.zero,
                value: _dragValue ?? playback.progress,
                onChanged: (value) => setState(() => _dragValue = value),
                onChangeEnd: (value) {
                  notifier.seekFraction(value);
                  setState(() => _dragValue = null);
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(playback.elapsed, style: muted),
                Text(playback.remaining, style: muted),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  tooltip: 'Shuffle',
                  iconSize: 20,
                  onPressed: notifier.toggleShuffle,
                  icon: Icon(
                    AppIcons.shuffle,
                    color: toggled(playback.shuffle),
                  ),
                ),
                IconButton(
                  tooltip: 'Previous (Ctrl+←)',
                  iconSize: 28,
                  onPressed: notifier.previous,
                  icon: const Icon(AppIcons.skipPrevious),
                ),
                Tooltip(
                  message: playback.playing ? 'Pause (Space)' : 'Play (Space)',
                  child: Material(
                    color: AppColors.white,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: notifier.togglePlay,
                      child: SizedBox.square(
                        dimension: 76,
                        child: Icon(
                          playback.playing
                              ? AppIcons.pause
                              : AppIcons.playFilled,
                          size: 30,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Next (Ctrl+→)',
                  iconSize: 28,
                  onPressed: notifier.next,
                  icon: const Icon(AppIcons.skipNext),
                ),
                IconButton(
                  tooltip: 'Repeat',
                  iconSize: 20,
                  onPressed: notifier.cycleRepeatMode,
                  icon: Icon(
                    playback.repeatMode == PlaybackRepeatMode.one
                        ? AppIcons.repeatOne
                        : AppIcons.repeat,
                    color: toggled(
                      playback.repeatMode != PlaybackRepeatMode.off,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _LyricsColumn extends ConsumerWidget {
  const _LyricsColumn({required this.track});

  final Song track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lyricsProvider(track));
    final lyrics = state.asData?.value;
    final Widget body;
    if (state.isLoading) {
      body = const Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else if (lyrics == null || lyrics.instrumental) {
      body = Center(
        child: Text(
          lyrics?.instrumental ?? false ? 'Instrumental' : 'No lyrics yet.',
          style: TextStyle(color: AppColors.whiteAlpha(0.6), fontSize: 18),
        ),
      );
    } else if (lyrics.synced) {
      body = DesktopSyncedLyrics(
        key: ValueKey(lyrics),
        lyrics: lyrics,
        fontSize: 30,
        padding: const EdgeInsets.fromLTRB(0, 24, 0, 240),
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.only(top: 24, bottom: 80),
        children: [
          for (final stanza in parseLyricsStructure(lyrics.plain ?? ''))
            Padding(
              padding: const EdgeInsets.only(bottom: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (stanza.label != null) LyricsSectionLabel(stanza.label!),
                  for (final line in stanza.lines)
                    LyricText(
                      line,
                      style: TextStyle(
                        fontSize: 26,
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                        color: AppColors.whiteAlpha(0.85),
                      ),
                    ),
                ],
              ),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (lyrics != null && !lyrics.instrumental)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.whiteAlpha(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  lyrics.synced ? 'SYNCED LYRICS' : 'LYRICS',
                  style: TextStyle(
                    color: AppColors.whiteAlpha(0.8),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            const Spacer(),
            if (!state.isLoading)
              DesktopPill(
                icon: AppIcons.edit,
                label: lyrics == null ? 'Write lyrics' : 'Edit lyrics',
                onPressed: () =>
                    DesktopLyricsEditor.open(context, track, lyrics),
              ),
          ],
        ),
        Expanded(
          child: ShaderMask(
            // Fade the lines out at the top and bottom edges.
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.white,
                Colors.white,
                Colors.transparent,
              ],
              stops: [0, 0.08, 0.85, 1],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: body,
          ),
        ),
      ],
    );
  }
}
