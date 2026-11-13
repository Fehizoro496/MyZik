import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'icons.dart';
import 'models.dart';
import 'providers/collection_provider.dart';
import 'providers/library_provider.dart';
import 'providers/liked_provider.dart';
import 'providers/navigation_provider.dart';
import 'providers/playback_provider.dart';
import 'providers/playlists_provider.dart';
import 'providers/song_detail_provider.dart';
import 'screens/delete_song_dialog.dart';
import 'theme.dart';

/// A bare icon button used throughout the design, with a fixed square tap
/// target.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 46,
    this.iconSize = 20,
    this.iconColor = AppColors.white,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(icon, size: iconSize, color: iconColor),
      ),
    );
  }
}

/// A secondary page's top bar: back on the left, the page's name centred,
/// an optional action on the right (an empty slot keeps the title centred).
class PageHeader extends ConsumerWidget {
  const PageHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          GlassIconButton(
            icon: AppIcons.back,
            size: 44,
            iconSize: 22,
            onTap: () => ref.read(navigationProvider.notifier).back(),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          trailing ?? const SizedBox(width: 44),
        ],
      ),
    );
  }
}

/// A page action as a pill: [primary] is the white one that starts playback,
/// the others are glass. A null [onTap] dims and disables it.
class ActionPill extends StatelessWidget {
  const ActionPill({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final foreground = primary ? AppColors.ink : AppColors.white;
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedOpacity(
          opacity: onTap == null ? 0.4 : 1,
          duration: const Duration(milliseconds: 150),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            decoration: BoxDecoration(
              color: primary ? AppColors.white : AppColors.whiteAlpha(0.08),
              borderRadius: BorderRadius.circular(24),
              border: primary
                  ? null
                  : Border.all(color: AppColors.whiteAlpha(0.12)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: iconColor ?? foreground, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The light of a page's cover: a wash of [color] glowing down from the top
/// of the page, as Now Playing is lit by the track playing. Place it first
/// in the page's [Stack]; it ignores touches.
class CoverGlow extends StatelessWidget {
  const CoverGlow({super.key, required this.color, this.height = 520});

  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: height,
      child: IgnorePointer(
        child: TweenAnimationBuilder<Color?>(
          // The cover's colour is extracted asynchronously: ease into it
          // rather than switching abruptly.
          tween: ColorTween(end: color),
          duration: const Duration(milliseconds: 500),
          builder: (context, color, _) => DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -1.1),
                radius: 1.15,
                colors: [
                  color!.withValues(alpha: 0.55),
                  color.withValues(alpha: 0.18),
                  color.withValues(alpha: 0),
                ],
                stops: const [0, 0.5, 1],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The colour lighting a page for [song]'s cover: its dominant colour, or
/// its placeholder gradient's while that is extracted or when it has none.
Color coverLight(WidgetRef ref, Song song) =>
    ref.watch(coverAccentProvider(song.coverKey)).asData?.value ??
    song.artGradient.first;

/// Opens the detail page of an album or artist.
void openCollection(WidgetRef ref, MusicCollection collection) {
  ref.read(selectedCollectionProvider.notifier).show(collection);
  ref.read(navigationProvider.notifier).goTo(AppScreen.collection);
}

/// A titled, horizontally scrolling shelf of albums (square covers) or
/// artists (round discs, like the record turning in Now Playing). Tapping
/// one opens its page.
class CollectionShelf extends ConsumerWidget {
  const CollectionShelf({
    super.key,
    required this.title,
    required this.collections,
    this.padding = 22,
  });

  final String title;
  final List<MusicCollection> collections;

  /// The page's side margin: the shelf bleeds to the screen edges but its
  /// first item and title line up with the page content.
  final double padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (collections.isEmpty) return const SizedBox.shrink();
    final artists = collections.first.isArtist;
    final size = artists ? 96.0 : 132.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: padding),
          child: SectionTitle(title),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: size + (artists ? 34 : 52),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: padding),
            itemCount: collections.length,
            separatorBuilder: (_, _) => SizedBox(width: artists ? 18 : 16),
            itemBuilder: (context, i) {
              final collection = collections[i];
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => openCollection(ref, collection),
                child: SizedBox(
                  width: size,
                  child: Column(
                    crossAxisAlignment: artists
                        ? CrossAxisAlignment.center
                        : CrossAxisAlignment.start,
                    children: [
                      SongArtwork(
                        song: collection.cover,
                        size: size,
                        radius: 18,
                        circle: artists,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        collection.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: artists ? TextAlign.center : TextAlign.start,
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (!artists) ...[
                        const SizedBox(height: 2),
                        Text(
                          collection.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.whiteAlpha(0.5),
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The top of a detail page (album, artist, playlist, liked songs, a song):
/// its cover lifted off the page, its name, a line or two about it and its
/// actions, the first of which plays it.
class PageHero extends StatelessWidget {
  const PageHero({
    super.key,
    required this.cover,
    required this.title,
    this.subtitle,
    this.meta,
    this.actions = const [],
    this.coverSize = 220,
    this.circle = false,
    this.coverRadius = 28,
  });

  /// The cover, drawn at [coverSize]; [circle] and [coverRadius] shape its
  /// shadow to match.
  final Widget cover;
  final String title;

  /// Who made it (an album's artist, a song's artist).
  final String? subtitle;

  /// Counts and length ("5 songs, 17 min").
  final String? meta;
  final List<Widget> actions;
  final double coverSize;
  final bool circle;
  final double coverRadius;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: circle ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: circle ? null : BorderRadius.circular(coverRadius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 48,
                  offset: const Offset(0, 22),
                ),
              ],
            ),
            child: SizedBox.square(dimension: coverSize, child: cover),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.white,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            height: 1.15,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.whiteAlpha(0.75), fontSize: 15),
          ),
        ],
        if (meta != null) ...[
          const SizedBox(height: 4),
          Text(
            meta!,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.whiteAlpha(0.5), fontSize: 13),
          ),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 22),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: actions,
          ),
        ],
      ],
    );
  }
}

/// "5 songs, 17 min": how many [songs] and how long they play.
String songsSummary(List<Song> songs, {int? count}) {
  final n = count ?? songs.length;
  final label = '$n ${n == 1 ? 'song' : 'songs'}';
  if (songs.isEmpty) return label;
  final total = songs.fold(Duration.zero, (sum, s) => sum + s.duration);
  if (total.inMinutes == 0) return label;
  final hours = total.inHours;
  final minutes = total.inMinutes % 60;
  final length = hours == 0
      ? '$minutes min'
      : minutes == 0
      ? '$hours h'
      : '$hours h $minutes min';
  return '$label, $length';
}

/// Plays [songs] in a random order from a random one of them, turning
/// shuffle on.
void playShuffled(WidgetRef ref, List<Song> songs) {
  if (songs.isEmpty) return;
  final playback = ref.read(playbackProvider.notifier);
  if (!ref.read(playbackProvider).shuffle) playback.toggleShuffle();
  playback.playSong(songs[Random().nextInt(songs.length)], context: songs);
}

/// The Play and Shuffle pair opening most detail pages.
List<Widget> playActions(WidgetRef ref, List<Song> songs) => [
  ActionPill(
    icon: AppIcons.playFilled,
    label: 'Play',
    primary: true,
    onTap: songs.isEmpty
        ? null
        : () => ref
              .read(playbackProvider.notifier)
              .playSong(songs.first, context: songs),
  ),
  ActionPill(
    icon: AppIcons.shuffle,
    label: 'Shuffle',
    onTap: songs.isEmpty ? null : () => playShuffled(ref, songs),
  ),
];

/// A section's title on a page ("Albums", "Songs").
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.white,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    );
  }
}

/// Album-art placeholder: a rounded gradient tile (or circle) with a subtle
/// note glyph, standing in for the design's image slots.
class AlbumArt extends StatelessWidget {
  const AlbumArt({
    super.key,
    required this.gradient,
    this.size = 56,
    this.radius = 16,
    this.circle = false,
    this.showGlyph = true,
  });

  final List<Color> gradient;
  final double size;
  final double radius;
  final bool circle;
  final bool showGlyph;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        borderRadius: circle ? null : BorderRadius.circular(radius),
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
      ),
      child: showGlyph
          ? Icon(
              AppIcons.musicNote,
              size: size * 0.34,
              color: AppColors.whiteAlpha(0.85),
            )
          : null,
    );
  }
}

/// Real album art for a [Song] (MediaStore cover or remote artwork), loaded
/// lazily via [coverArtProvider]. Falls back to the song's gradient placeholder
/// while loading or when the track has no cover. Keeps the artwork query
/// out of the [Song] model so the UI stays source-agnostic.
class SongArtwork extends ConsumerWidget {
  const SongArtwork({
    super.key,
    required this.song,
    this.size = 56,
    this.radius = 16,
    this.circle = false,
  });

  final Song song;
  final double size;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placeholder = AlbumArt(
      gradient: song.artGradient,
      size: size,
      radius: radius,
      circle: circle,
    );
    final artwork = ref.watch(coverArtProvider(song.coverKey));
    final bytes = artwork.asData?.value;
    if (bytes == null) return placeholder;
    // Decode at the on-screen pixel size rather than the full 400px source:
    // keeps decoding and GPU uploads cheap while a list of covers scrolls.
    final cacheSize = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final image = Image(
      image: ResizeImage(
        MemoryImage(bytes),
        width: cacheSize,
        height: cacheSize,
        policy: ResizeImagePolicy.fit,
      ),
      width: size,
      height: size,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => placeholder,
    );
    return circle
        ? ClipOval(
            child: SizedBox(width: size, height: size, child: image),
          )
        : ClipRRect(borderRadius: BorderRadius.circular(radius), child: image);
  }
}

/// A floating, frosted segmented tab control: a glass capsule that hovers over
/// the content (which scrolls behind it), split into equal segments with a
/// gradient highlight that slides to the active one. Shares the MiniPlayer /
/// NavBar glass recipe — same backdrop blur, tint and rim — so the app's
/// floating surfaces read as one material. Used to switch between library
/// views (Songs / Albums / Artists / …).
class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelected,
  });

  final List<String> tabs;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final count = tabs.length;
    return DecoratedBox(
      // Soft drop shadow so the capsule lifts off the list scrolling underneath.
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter.grouped(
          // Same blur as the MiniPlayer — this is what makes the content behind
          // it read as frosted glass rather than a flat panel. Grouped so it
          // shares one backdrop read with the other glass surfaces when an
          // ancestor [BackdropGroup] exists.
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            height: 50,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              // Same tint + alpha as the NavBar / MiniPlayer frosted panels.
              color: const Color.fromRGBO(22, 22, 30, 0.5),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: AppColors.whiteAlpha(0.08)),
            ),
            child: Stack(
              children: [
                // Sliding gradient highlight behind the active segment. Aligned
                // so its 1/count-wide box lands exactly over segment [selected].
                AnimatedAlign(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  alignment: count == 1
                      ? Alignment.center
                      : Alignment(-1 + 2 * selected / (count - 1), 0),
                  child: FractionallySizedBox(
                    widthFactor: 1 / count,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: AppColors.accentGradient,
                        borderRadius: BorderRadius.circular(21),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accentA.withValues(alpha: 0.45),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < count; i++)
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onSelected(i),
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 200),
                              style: DefaultTextStyle.of(context).style.merge(
                                TextStyle(
                                  color: i == selected
                                      ? AppColors.white
                                      : AppColors.whiteAlpha(0.6),
                                  fontSize: 13,
                                  fontWeight: i == selected
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                ),
                              ),
                              child: Text(
                                tabs[i],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A song list row: art + title/subtitle + a trailing button. Long-pressing the
/// row opens the "add to playlist" sheet unless [onLongPress] overrides it. The
/// trailing button is the ⋮ track menu (song details, add to playlist, like) by
/// default; pass [trailing] to replace it (e.g. a playlist's remove menu).
class TrackRow extends ConsumerWidget {
  const TrackRow({
    super.key,
    required this.song,
    this.onTap,
    this.onLongPress,
    this.trailing,
    this.leading,
  });

  final Song song;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  /// Replaces the cover, e.g. by the track number on an album's page, where
  /// every row would repeat the same cover.
  final Widget? leading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The track playing stands out in any list it shows up in.
    final playing = ref.watch(
      playbackProvider.select((p) => p.current?.id == song.id),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress ?? () => showAddToPlaylistSheet(context, song),
      child: Row(
        children: [
          leading ?? SongArtwork(song: song),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: playing ? AppColors.playing : AppColors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${song.artist} · ${song.durationLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.whiteAlpha(0.5),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing ?? _TrackMenuButton(song: song),
        ],
      ),
    );
  }
}

/// [TrackRow]'s default trailing button: a ⋮ that opens the track's popover menu
/// (song details, add to playlist, like/unlike, delete).
class _TrackMenuButton extends ConsumerWidget {
  const _TrackMenuButton({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Builder(
      builder: (buttonContext) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openMenu(buttonContext, ref),
        child: Icon(
          AppIcons.moreVert,
          size: 20,
          color: AppColors.whiteAlpha(0.8),
        ),
      ),
    );
  }

  Future<void> _openMenu(BuildContext buttonContext, WidgetRef ref) async {
    final liked = ref.read(isLikedProvider(song.songKey));
    final deletable = canDeleteSong(ref, song);
    final selected = await showPopoverMenu<String>(buttonContext, [
      const PopupMenuItem(
        value: 'details',
        child: PopoverMenuRow(icon: AppIcons.info, label: 'Song details'),
      ),
      const PopupMenuItem(
        value: 'add',
        child: PopoverMenuRow(
          icon: AppIcons.playlistAdd,
          label: 'Add to playlist',
        ),
      ),
      PopupMenuItem(
        value: 'like',
        child: PopoverMenuRow(
          icon: liked ? AppIcons.heartFilled : AppIcons.heart,
          label: liked ? 'Remove from liked' : 'Add to liked',
        ),
      ),
      if (deletable)
        const PopupMenuItem(
          value: 'delete',
          child: PopoverMenuRow(icon: AppIcons.delete, label: 'Delete'),
        ),
    ]);
    switch (selected) {
      case 'details':
        ref.read(selectedSongProvider.notifier).state = song;
        ref.read(navigationProvider.notifier).goTo(AppScreen.songDetail);
      case 'add':
        if (buttonContext.mounted) {
          showAddToPlaylistSheet(buttonContext, song);
        }
      case 'like':
        ref.read(likedProvider.notifier).toggle(song);
      case 'delete':
        if (buttonContext.mounted) {
          await confirmDeleteSong(buttonContext, ref, song);
        }
    }
  }
}

/// A page whose content scrolls *behind* a frosted header instead of stopping
/// under it. The [header] (just its row(s): the status-bar inset is added here)
/// floats over the top of the page on a blurred, darkening gradient; [body]
/// fills the whole page and receives `top`, the header's measured height, to
/// use as its scrollable's top padding.
///
/// Place it as the first child of the page's [Stack] (under any floating
/// mini-player / nav bar), or alone. Wrap the page in a [BackdropGroup] to let
/// the header share its backdrop read with the other glass surfaces.
class FrostedHeaderLayout extends StatefulWidget {
  const FrostedHeaderLayout({
    super.key,
    required this.header,
    required this.body,
    this.color = AppColors.musicBackground,
  });

  final Widget header;
  final Widget Function(BuildContext context, double top) body;

  /// Page background colour the header's gradient is tinted with.
  final Color color;

  @override
  State<FrostedHeaderLayout> createState() => _FrostedHeaderLayoutState();
}

class _FrostedHeaderLayoutState extends State<FrostedHeaderLayout> {
  double? _headerHeight;

  void _onHeaderSize(Size size) {
    if (size.height == _headerHeight) return;
    // Reported during layout: rebuild the body with the new inset next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _headerHeight = size.height);
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    return Stack(
      children: [
        Positioned.fill(
          child: widget.body(
            context,
            _headerHeight ?? MediaQuery.paddingOf(context).top,
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _SizeReporter(
            onSize: _onHeaderSize,
            child: ClipRect(
              child: BackdropFilter.grouped(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: DecoratedBox(
                  // Darker at the top (status bar) easing off toward the
                  // bottom edge, where the frosted content still shows.
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        color.withValues(alpha: 0.95),
                        color.withValues(alpha: 0.8),
                      ],
                    ),
                  ),
                  child: SafeArea(bottom: false, child: widget.header),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Calls [onSize] with its child's size after each layout that changes it.
class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({required this.onSize, super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeReporter(onSize);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSizeReporter renderObject,
  ) {
    renderObject.onSize = onSize;
  }
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSize);

  ValueChanged<Size> onSize;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    if (size != _last) {
      _last = size;
      onSize(size);
    }
  }
}

/// A light fade at the bottom of a page, from transparent to [color], laid
/// under the floating mini-player / nav bar so content scrolling behind them
/// dissolves instead of being cut off at the screen edge. Must be a direct
/// child of a [Stack], placed before the floating controls. Ignores touches.
class BottomFade extends StatelessWidget {
  const BottomFade({
    super.key,
    this.color = AppColors.musicBackground,
    this.height = 140,
  });

  final Color color;

  /// Height above the system bottom inset.
  final double height;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: height + MediaQuery.viewPaddingOf(context).bottom,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: 0),
                color.withValues(alpha: 0.85),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The frosted bottom navigation bar: a floating glass capsule lifted off the
/// screen's bottom edge (clear of the system gesture area), with a mini-player
/// floating above it. Shown on every screen except Now Playing. The active tab
/// is derived from [navigationProvider] and shows the accent pill.
class NavBar extends ConsumerWidget {
  const NavBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screen = ref.watch(navigationProvider);
    final goTo = ref.read(navigationProvider.notifier).goTo;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 16),
      child: DecoratedBox(
        // Soft drop shadow so the capsule lifts off the content behind it.
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter.grouped(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color.fromRGBO(22, 22, 30, 0.5),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: AppColors.whiteAlpha(0.08)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _tab(
                    screen,
                    goTo,
                    icon: AppIcons.home,
                    activeIcon: AppIcons.homeFilled,
                    target: AppScreen.home,
                  ),
                  _tab(
                    screen,
                    goTo,
                    icon: AppIcons.category,
                    activeIcon: AppIcons.categoryFilled,
                    target: AppScreen.myMusic,
                  ),
                  // _action(
                  //   AppIcons.swap,
                  //   () => goTo(AppScreen.nowPlaying),
                  // ),
                  _tab(
                    screen,
                    goTo,
                    icon: AppIcons.heart,
                    activeIcon: AppIcons.heartFilled,
                    target: AppScreen.liked,
                  ),
                  _tab(
                    screen,
                    goTo,
                    icon: AppIcons.download,
                    activeIcon: AppIcons.downloadFilled,
                    target: AppScreen.discover,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(
    AppScreen current,
    ValueChanged<AppScreen> goTo, {
    required IconData icon,
    required IconData activeIcon,
    required AppScreen target,
  }) {
    final active = current == target;
    if (active) {
      return Container(
        width: 48,
        height: 48,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppColors.accentGradient,
        ),
        child: Icon(activeIcon, size: 22, color: AppColors.white),
      );
    }
    return _action(icon, () => goTo(target));
  }

  Widget _action(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Icon(icon, size: 24, color: AppColors.whiteAlpha(0.55)),
      ),
    );
  }
}

/// The frosted mini-player pill: floats above the [NavBar] whenever a
/// track is loaded, showing its art + title as a "playback in progress"
/// notice. Tapping it opens Now Playing; the play/pause button toggles
/// playback in place without navigating. Renders nothing when no track has
/// been played yet.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackProvider);
    final track = playback.current;
    if (track == null) return const SizedBox.shrink();
    final notifier = ref.read(playbackProvider.notifier);
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter.grouped(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: GestureDetector(
          onTap: () =>
              ref.read(navigationProvider.notifier).goTo(AppScreen.nowPlaying),
          child: Container(
            height: 60,
            padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
            decoration: BoxDecoration(
              // Same tint + alpha as NavBar's frosted panel so the two floating
              // elements read as one consistent glass surface.
              color: const Color.fromRGBO(22, 22, 30, 0.5),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: AppColors.whiteAlpha(0.08)),
            ),
            child: Row(
              children: [
                SongArtwork(song: track, size: 44, circle: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.whiteAlpha(0.55),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: notifier.togglePlay,
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(
                      playback.playing ? AppIcons.pause : AppIcons.playFilled,
                      size: 18,
                      color: AppColors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows a dark popover menu anchored on the tapped button ([buttonContext] is
/// the button's own context, used to position it) and returns the picked value.
/// Opens below the button, or above it when there isn't room below.
Future<T?> showPopoverMenu<T>(
  BuildContext buttonContext,
  List<PopupMenuEntry<T>> items,
) {
  final button = buttonContext.findRenderObject() as RenderBox;
  final overlay =
      Navigator.of(buttonContext).overlay!.context.findRenderObject()
          as RenderBox;
  const gap = 6.0;
  final topLeft = button.localToGlobal(Offset.zero, ancestor: overlay);
  final bottomRight = button.localToGlobal(
    button.size.bottomRight(Offset.zero),
    ancestor: overlay,
  );
  // Menu height is estimated from the item count to decide which way to open.
  final menuHeight = items.length * kMinInteractiveDimension + 16;
  final roomBelow = overlay.size.height - bottomRight.dy - gap;
  final top = roomBelow < menuHeight
      ? topLeft.dy -
            gap -
            menuHeight // above the button
      : bottomRight.dy + gap; // below the button
  final position = RelativeRect.fromLTRB(
    topLeft.dx,
    top,
    overlay.size.width - bottomRight.dx,
    overlay.size.height - top,
  );
  return showMenu<T>(
    context: buttonContext,
    position: position,
    color: const Color(0xFF1B1B24),
    elevation: 12,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: AppColors.whiteAlpha(0.08)),
    ),
    items: items,
  );
}

/// One row of a [showPopoverMenu]: an icon + label, styled for the dark menu
/// surface.
class PopoverMenuRow extends StatelessWidget {
  const PopoverMenuRow({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: AppColors.whiteAlpha(0.85)),
        const SizedBox(width: 14),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// A playlist's cover: a mosaic of the first tracks that actually have embedded
/// artwork (up to four, laid out to fill the square). Tracks without a cover are
/// skipped, so the collage is real artwork only. Falls back to a gradient tile
/// (accent + queue glyph for an empty playlist, else the first track's gradient
/// when none of its tracks have covers).
class PlaylistCover extends ConsumerWidget {
  const PlaylistCover({
    super.key,
    required this.songs,
    this.size = 54,
    this.radius = 14,
    this.probeLimit = 8,
  });

  final List<Song> songs;
  final double size;
  final double radius;

  /// How many leading tracks to check for artwork while looking for four with a
  /// cover — bounds artwork loads for a mere thumbnail.
  final int probeLimit;

  /// Thin seam between mosaic tiles so they read as a collage, not one image.
  static const _gap = 2.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (songs.isEmpty) return _gradientTile(gradient: AppColors.accentGradient);

    // Take the first tracks that have a loaded cover, up to four.
    final covers = <Song>[];
    for (final song in songs.take(probeLimit)) {
      if (covers.length == 4) break;
      if (ref.watch(coverArtProvider(song.coverKey)).asData?.value != null) {
        covers.add(song);
      }
    }
    if (covers.isEmpty) {
      // Nothing has a cover (yet): tint by the first track's placeholder.
      return _gradientTile(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: songs.first.artGradient,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(width: size, height: size, child: _mosaic(covers)),
    );
  }

  Widget _gradientTile({required Gradient gradient}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: songs.isEmpty
          ? Icon(AppIcons.queue, size: size * 0.42, color: AppColors.white)
          : null,
    );
  }

  Widget _mosaic(List<Song> covers) {
    switch (covers.length) {
      case 1:
        return _CoverTile(song: covers[0]);
      case 2:
        // Two vertical halves.
        return Row(
          children: [
            Expanded(child: _CoverTile(song: covers[0])),
            const SizedBox(width: _gap),
            Expanded(child: _CoverTile(song: covers[1])),
          ],
        );
      case 3:
        // One tall tile on the left, two stacked on the right.
        return Row(
          children: [
            Expanded(child: _CoverTile(song: covers[0])),
            const SizedBox(width: _gap),
            Expanded(
              child: Column(
                children: [
                  Expanded(child: _CoverTile(song: covers[1])),
                  const SizedBox(height: _gap),
                  Expanded(child: _CoverTile(song: covers[2])),
                ],
              ),
            ),
          ],
        );
      default:
        // 2×2 grid.
        return Column(
          children: [
            Expanded(child: _mosaicRow(covers[0], covers[1])),
            const SizedBox(height: _gap),
            Expanded(child: _mosaicRow(covers[2], covers[3])),
          ],
        );
    }
  }

  Widget _mosaicRow(Song left, Song right) {
    return Row(
      children: [
        Expanded(child: _CoverTile(song: left)),
        const SizedBox(width: _gap),
        Expanded(child: _CoverTile(song: right)),
      ],
    );
  }
}

/// One tile of a [PlaylistCover] mosaic: the track's artwork covering the cell,
/// falling back to its gradient placeholder while loading or when it has none.
/// Fills whatever box its parent gives it (unlike [SongArtwork], which is a
/// fixed square).
class _CoverTile extends ConsumerWidget {
  const _CoverTile({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: song.artGradient,
        ),
      ),
    );
    final bytes = ref.watch(coverArtProvider(song.coverKey)).asData?.value;
    if (bytes == null) return placeholder;
    return Image.memory(
      bytes,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}

/// The app's frosted bottom-sheet chrome: rounded top, backdrop blur, dark
/// glass tint and a drag handle, lifting above the keyboard. [header] is a fixed
/// area under the handle; [child] fills the rest (wrap a scrollable in it, e.g.
/// a `shrinkWrap` ListView, so the sheet sizes to content up to
/// [maxHeightFactor] of the screen and scrolls beyond).
class GlassSheet extends StatelessWidget {
  const GlassSheet({
    super.key,
    required this.child,
    this.header,
    this.maxHeightFactor = 0.85,
  });

  final Widget child;
  final Widget? header;
  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: media.size.height * maxHeightFactor,
            ),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(15, 15, 21, 0.92),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30),
              ),
              border: Border(
                top: BorderSide(color: AppColors.whiteAlpha(0.09)),
              ),
            ),
            child: SafeArea(
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
                  const SizedBox(height: 8),
                  ?header,
                  Flexible(child: child),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tappable row for a sheet action (e.g. "New playlist"): a circular glass
/// icon chip + label.
class SheetActionTile extends StatelessWidget {
  const SheetActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon, size: 20, color: AppColors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Prompts for a single line of text (playlist name) in a glass sheet, returning
/// the trimmed value or null if dismissed. Autofocuses the field.
Future<String?> showNameSheet(
  BuildContext context, {
  required String title,
  String initial = '',
  required String actionLabel,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) =>
        _NameSheet(title: title, initial: initial, actionLabel: actionLabel),
  );
}

class _NameSheet extends StatefulWidget {
  const _NameSheet({
    required this.title,
    required this.initial,
    required this.actionLabel,
  });

  final String title;
  final String initial;
  final String actionLabel;

  @override
  State<_NameSheet> createState() => _NameSheetState();
}

class _NameSheetState extends State<_NameSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return GlassSheet(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.title,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.whiteAlpha(0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.whiteAlpha(0.08)),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                cursorColor: AppColors.accentA,
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.words,
                onSubmitted: (_) => _submit(),
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Playlist name',
                  hintStyle: TextStyle(
                    color: AppColors.whiteAlpha(0.4),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _submit,
              child: Container(
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: AppColors.accentGradient,
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Text(
                  widget.actionLabel,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
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

/// Opens the sheet to add/remove [song] to/from playlists. Tapping a playlist
/// toggles membership (a check marks the ones it's in); "New playlist" creates
/// one and drops the song straight in.
Future<void> showAddToPlaylistSheet(BuildContext context, Song song) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _AddToPlaylistSheet(song: song),
  );
}

class _AddToPlaylistSheet extends ConsumerWidget {
  const _AddToPlaylistSheet({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    return GlassSheet(
      maxHeightFactor: 0.7,
      header: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 10, 24, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Add to playlist',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          SheetActionTile(
            icon: AppIcons.add,
            label: 'New playlist',
            onTap: () async {
              final notifier = ref.read(playlistsProvider.notifier);
              final name = await showNameSheet(
                context,
                title: 'New playlist',
                actionLabel: 'Create',
              );
              if (name == null) return;
              final playlist = notifier.create(name);
              notifier.addSong(playlist.id, song);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Divider(height: 12, color: AppColors.whiteAlpha(0.08)),
          ),
        ],
      ),
      child: playlists.isEmpty
          ? Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
              child: Text(
                'No playlists yet. Create one above.',
                style: TextStyle(
                  color: AppColors.whiteAlpha(0.5),
                  fontSize: 14,
                ),
              ),
            )
          : ListView.builder(
              shrinkWrap: true,
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
              itemCount: playlists.length,
              itemBuilder: (context, i) {
                final playlist = playlists[i];
                final selected = playlist.contains(song);
                return _PlaylistPickRow(
                  playlist: playlist,
                  selected: selected,
                  onTap: () {
                    final notifier = ref.read(playlistsProvider.notifier);
                    if (selected) {
                      notifier.removeSong(playlist.id, song);
                    } else {
                      notifier.addSong(playlist.id, song);
                    }
                  },
                );
              },
            ),
    );
  }
}

class _PlaylistPickRow extends ConsumerWidget {
  const _PlaylistPickRow({
    required this.playlist,
    required this.selected,
    required this.onTap,
  });

  final Playlist playlist;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = ref.watch(playlistSongsProvider(playlist.id));
    final count = playlist.songKeys.length;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            PlaylistCover(songs: songs, size: 46, radius: 12),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$count ${count == 1 ? 'song' : 'songs'}',
                    style: TextStyle(
                      color: AppColors.whiteAlpha(0.45),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              selected ? AppIcons.checkCircle : AppIcons.addCircle,
              color: selected ? AppColors.accentA : AppColors.whiteAlpha(0.4),
              size: 26,
            ),
          ],
        ),
      ),
    );
  }
}

/// Scrolling content (lyrics, the queue) dissolves into what sits above and
/// below it instead of being cut by a hard edge.
class FadedEdges extends StatelessWidget {
  const FadedEdges({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        final h = bounds.height <= 0 ? 1.0 : bounds.height;
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: [0, (24 / h).clamp(0, 0.5), (1 - 40 / h).clamp(0.5, 1), 1],
        ).createShader(bounds);
      },
      child: child,
    );
  }
}
