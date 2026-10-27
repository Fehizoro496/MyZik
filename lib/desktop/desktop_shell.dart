import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../icons.dart';
import '../providers/downloads_provider.dart';
import '../providers/library_provider.dart';
import '../providers/playback_provider.dart';
import '../providers/playlists_provider.dart';
import '../theme.dart';
import '../widgets.dart';
import 'desktop_navigation.dart';
import 'desktop_style.dart';
import 'discover_page.dart';
import 'now_playing.dart';
import 'pages.dart';
import 'player_bar.dart';
import 'side_panel.dart';

/// The desktop layout: sidebar, page area with a top bar, optional lyrics or
/// queue panel on the right, and a player bar along the bottom, or Now
/// Playing filling the window. Shares every provider with the mobile
/// [PlayerShell]; only the presentation differs.
class DesktopShell extends ConsumerStatefulWidget {
  const DesktopShell({super.key});

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell> {
  final _searchFocus = FocusNode();
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchFocus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Whether a text field has the keyboard, so Space types instead of
  /// toggling playback.
  bool get _typing =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorStateOfType<EditableTextState>() !=
      null;

  void _togglePanel(DesktopPanel panel) {
    final controller = ref.read(desktopPanelProvider.notifier);
    controller.state = controller.state == panel ? null : panel;
  }

  @override
  Widget build(BuildContext context) {
    final route = ref.watch(desktopNavigatorProvider);
    final panel = ref.watch(desktopPanelProvider);
    final fullscreen = ref.watch(desktopFullscreenProvider);
    final navigator = ref.read(desktopNavigatorProvider.notifier);
    final playback = ref.read(playbackProvider.notifier);
    // Leaving search results (back, sidebar) clears the search box.
    ref.listen(desktopNavigatorProvider.select((r) => r.isSearch), (_, search) {
      if (!search) _searchController.clear();
    });

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () {
          if (!_typing) playback.togglePlay();
        },
        const SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
            playback.next,
        const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
            playback.previous,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          ref.read(desktopFullscreenProvider.notifier).state = false;
          _searchFocus.requestFocus();
        },
        const SingleActivator(LogicalKeyboardKey.keyL, control: true): () =>
            _togglePanel(DesktopPanel.lyrics),
        const SingleActivator(LogicalKeyboardKey.keyQ, control: true): () =>
            _togglePanel(DesktopPanel.queue),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
            navigator.back,
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
            navigator.forward,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!_typing) {
            ref.read(desktopFullscreenProvider.notifier).state = false;
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Listener(
          // Mouse side buttons navigate like in a browser.
          onPointerDown: (event) {
            if (event.buttons & kBackMouseButton != 0) navigator.back();
            if (event.buttons & kForwardMouseButton != 0) navigator.forward();
          },
          child: Scaffold(
            backgroundColor: AppColors.homeBackground,
            body: fullscreen
                ? const DesktopNowPlaying()
                : Column(
                    children: [
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _Sidebar(),
                            Expanded(
                              child: Column(
                                children: [
                                  _TopBar(
                                    searchController: _searchController,
                                    searchFocus: _searchFocus,
                                  ),
                                  Expanded(child: _page(route)),
                                ],
                              ),
                            ),
                            if (panel != null) DesktopSidePanel(panel: panel),
                          ],
                        ),
                      ),
                      const DesktopPlayerBar(),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _page(DesktopRoute route) {
    if (route.isSearch) return SongsPage(query: route.query);
    final collection = route.collection;
    if (collection != null) {
      return CollectionPage(key: ObjectKey(collection), collection: collection);
    }
    final playlistId = route.playlistId;
    if (playlistId != null) {
      return PlaylistPage(key: ValueKey(playlistId), playlistId: playlistId);
    }
    return switch (route.section) {
      DesktopSection.home => const HomePage(),
      DesktopSection.songs => const SongsPage(),
      DesktopSection.albums => const CollectionsPage(
        key: ValueKey('albums'),
        artists: false,
      ),
      DesktopSection.artists => const CollectionsPage(
        key: ValueKey('artists'),
        artists: true,
      ),
      DesktopSection.liked => const LikedPage(),
      DesktopSection.playlists => const PlaylistsPage(),
      DesktopSection.discover => const DiscoverPage(),
    };
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.searchController, required this.searchFocus});

  final TextEditingController searchController;
  final FocusNode searchFocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuild the arrows whenever the page changes.
    ref.watch(desktopNavigatorProvider);
    final navigator = ref.read(desktopNavigatorProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 28, 6),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back (Alt+←)',
            iconSize: 18,
            onPressed: navigator.canGoBack ? navigator.back : null,
            icon: const Icon(AppIcons.back),
          ),
          IconButton(
            tooltip: 'Forward (Alt+→)',
            iconSize: 18,
            onPressed: navigator.canGoForward ? navigator.forward : null,
            icon: const Icon(AppIcons.chevronRight),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SizedBox(
                height: 40,
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.escape): () {
                      searchController.clear();
                      navigator.search('');
                      searchFocus.unfocus();
                    },
                  },
                  child: TextField(
                    controller: searchController,
                    focusNode: searchFocus,
                    onChanged: navigator.search,
                    textAlignVertical: TextAlignVertical.center,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search songs, albums, artists',
                      hintStyle: TextStyle(color: AppColors.whiteAlpha(0.5)),
                      prefixIcon: const Icon(AppIcons.search, size: 16),
                      suffixIcon: const Padding(
                        padding: EdgeInsets.only(right: 10),
                        child: Center(widthFactor: 1, child: KeyHint('Ctrl F')),
                      ),
                      isDense: true,
                      filled: true,
                      fillColor: AppColors.whiteAlpha(0.07),
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          const CircleAvatar(
            radius: 17,
            backgroundImage: AssetImage('assets/images/avatar.png'),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar();

  static const width = 240.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = ref.watch(desktopNavigatorProvider);
    final playlists = ref.watch(playlistsProvider);
    final songCount = ref.watch(libraryProvider.select((s) => s.songs.length));
    final downloading = ref.watch(
      downloadsProvider.select(
        (d) => d.active.values.where((a) => !a.isFailed).length,
      ),
    );
    final navigator = ref.read(desktopNavigatorProvider.notifier);

    Widget item(
      DesktopSection section,
      IconData icon,
      String label, {
      Widget? trailing,
    }) {
      final selected =
          route.section == section &&
          route.playlistId == null &&
          route.collection == null &&
          !route.isSearch;
      return _SidebarItem(
        leading: Icon(
          icon,
          size: 18,
          color: selected ? AppColors.white : AppColors.whiteAlpha(0.66),
        ),
        label: label,
        selected: selected,
        trailing: trailing,
        onTap: () => navigator.openSection(section),
      );
    }

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: DesktopColors.panel,
        border: Border(right: BorderSide(color: AppColors.whiteAlpha(0.06))),
      ),
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    gradient: AppColors.accentGradient,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    AppIcons.musicNote,
                    size: 16,
                    color: AppColors.white,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'My Zik',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
          ),
          item(DesktopSection.home, AppIcons.home, 'Home'),
          item(
            DesktopSection.discover,
            AppIcons.search,
            'Discover',
            trailing: downloading == 0
                ? null
                : Tooltip(
                    message: '$downloading downloading',
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 20),
                      height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: AppColors.accentGradient,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$downloading',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
          ),
          const SidebarHeading('LIBRARY'),
          item(
            DesktopSection.songs,
            AppIcons.musicNote,
            'Songs',
            trailing: songCount == 0
                ? null
                : Text(
                    '$songCount',
                    style: TextStyle(
                      color: AppColors.whiteAlpha(0.6),
                      fontSize: 12,
                    ),
                  ),
          ),
          item(DesktopSection.albums, AppIcons.category, 'Albums'),
          item(DesktopSection.artists, AppIcons.folder, 'Artists'),
          item(DesktopSection.liked, AppIcons.heart, 'Liked songs'),
          SidebarHeading(
            'PLAYLISTS',
            trailing: IconButton(
              tooltip: 'New playlist',
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              onPressed: () => createPlaylist(context, ref),
              icon: const Icon(AppIcons.add),
            ),
            onTap: () => navigator.openSection(DesktopSection.playlists),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final playlist in playlists)
                  _SidebarItem(
                    leading: PlaylistCover(
                      songs: ref.watch(playlistSongsProvider(playlist.id)),
                      size: 32,
                      radius: 7,
                      probeLimit: 4,
                    ),
                    label: playlist.name,
                    subtitle: '${playlist.songIds.length} songs',
                    selected: route.playlistId == playlist.id,
                    onTap: () => navigator.open(
                      DesktopRoute(
                        DesktopSection.playlists,
                        playlistId: playlist.id,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small uppercase title above a group of sidebar or panel entries.
class SidebarHeading extends StatelessWidget {
  const SidebarHeading(this.label, {super.key, this.trailing, this.onTap});

  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 20, 0, 6),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: Text(label, style: DesktopText.overline),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.leading,
    required this.label,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });

  final Widget leading;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? AppColors.whiteAlpha(0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: AppColors.whiteAlpha(0.05),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: subtitle == null ? 12 : 8,
              vertical: subtitle == null ? 10 : 6,
            ),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected || subtitle != null
                              ? AppColors.white
                              : AppColors.whiteAlpha(0.7),
                          fontSize: subtitle == null ? 14 : 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: TextStyle(
                            color: AppColors.whiteAlpha(0.6),
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
