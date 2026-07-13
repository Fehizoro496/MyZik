import 'package:flutter/material.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/library_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/playback_provider.dart';
import '../theme.dart';
import '../widgets.dart';

/// Full-text search over the on-device library, matching title, artist or
/// album as the user types. Playing a result queues the current results, so
/// next/previous stay within the search.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Open the keyboard straight away — search is a focused task.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<Song> _results(List<Song> songs) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return songs.where((s) {
      return s.title.toLowerCase().contains(q) ||
          s.artist.toLowerCase().contains(q) ||
          (s.album?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final songs = ref.watch(libraryProvider.select((s) => s.songs));
    final results = _results(songs);
    final hasQuery = _query.trim().isNotEmpty;
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.musicBackground),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                children: [
                  GlassIconButton(
                    icon: IconlyLight.arrowLeft2,
                    size: 44,
                    iconSize: 22,
                    onTap: () => ref
                        .read(navigationProvider.notifier)
                        .goTo(AppScreen.home),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: _searchField()),
                ],
              ),
            ),
            Expanded(
              child: !hasQuery
                  ? _message(
                      'Search your library',
                      'Find songs, artists and albums.',
                    )
                  : results.isEmpty
                  ? _message(
                      'No matches',
                      'Nothing matched "${_query.trim()}".',
                    )
                  : _resultList(results),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchField() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.whiteAlpha(0.06),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.whiteAlpha(0.08)),
      ),
      child: Row(
        children: [
          Icon(IconlyLight.search, size: 20, color: AppColors.whiteAlpha(0.5)),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              cursorColor: AppColors.accentA,
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Songs, artists, albums',
                hintStyle: TextStyle(
                  color: AppColors.whiteAlpha(0.4),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          if (_query.isNotEmpty)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _controller.clear();
                setState(() => _query = '');
                _focus.requestFocus();
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: AppColors.whiteAlpha(0.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _resultList(List<Song> results) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
          child: Text(
            '${results.length} ${results.length == 1 ? 'result' : 'results'}',
            style: TextStyle(
              color: AppColors.whiteAlpha(0.5),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            physics: const BouncingScrollPhysics(),
            itemCount: results.length,
            itemBuilder: (context, i) => TrackRow(
              song: results[i],
              onTap: () => ref
                  .read(playbackProvider.notifier)
                  .playSong(results[i], context: results),
            ),
            separatorBuilder: (_, _) => const SizedBox(height: 20),
          ),
        ),
      ],
    );
  }

  Widget _message(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 0, 40, 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(IconlyLight.search, size: 46, color: AppColors.whiteAlpha(0.3)),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.whiteAlpha(0.5),
              fontSize: 13.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
