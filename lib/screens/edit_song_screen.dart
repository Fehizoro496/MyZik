import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../icons.dart';
import '../models.dart';
import '../providers/library_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/song_detail_provider.dart';
import '../providers/song_tags_provider.dart';
import '../theme.dart';
import '../widgets.dart';
import 'song_detail_screen.dart';

/// Asks for a picture to use as a cover. Null when cancelled or unreadable.
Future<Uint8List?> pickCoverImage() async {
  try {
    final file = await FilePicker.pickFile(type: FileType.image);
    return await file?.readAsBytes();
  } catch (_) {
    return null;
  }
}

/// Edits the title, artist, album and cover of [shownSongProvider], laid out
/// like its detail page: the cover on top, the fields below. Edits stay in
/// the app (and follow the song to the listener's other devices); the audio
/// file is left untouched.
class EditSongScreen extends ConsumerWidget {
  const EditSongScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(shownSongProvider);
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.musicBackground),
      // Keyed by song: the fields start over for another one.
      child: song == null
          ? const SizedBox.expand()
          : _EditSongForm(key: ValueKey(song.songKey), song: song),
    );
  }
}

class _EditSongForm extends ConsumerStatefulWidget {
  const _EditSongForm({super.key, required this.song});

  final Song song;

  @override
  ConsumerState<_EditSongForm> createState() => _EditSongFormState();
}

class _EditSongFormState extends ConsumerState<_EditSongForm> {
  late final _title = TextEditingController(text: widget.song.title);
  late final _artist = TextEditingController(text: widget.song.artist);
  late final _album = TextEditingController(text: widget.song.album ?? '');

  /// The picture picked to replace the cover, not saved yet.
  Uint8List? _pickedCover;

  /// Whether the file's own cover comes back on save.
  bool _removeCover = false;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _album.dispose();
    super.dispose();
  }

  bool get _valid =>
      _title.text.trim().isNotEmpty && _artist.text.trim().isNotEmpty;

  /// Whether the listener picked the cover shown, before or now.
  bool get _hasPickedCover =>
      _pickedCover != null ||
      (!_removeCover &&
          ref.read(songTagsProvider)[widget.song.songKey]?.cover != null);

  Future<void> _pickCover() async {
    final bytes = await pickCoverImage();
    if (bytes == null || !mounted) return;
    setState(() {
      _pickedCover = bytes;
      _removeCover = false;
    });
  }

  void _useFileCover() => setState(() {
    _pickedCover = null;
    _removeCover = true;
  });

  Future<void> _save() async {
    if (!_valid || _saving) return;
    setState(() => _saving = true);
    final saved = await ref
        .read(songTagsProvider.notifier)
        .save(
          widget.song,
          title: _title.text,
          artist: _artist.text,
          album: _album.text,
          cover: _pickedCover,
          removeCover: _removeCover,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved) ref.read(navigationProvider.notifier).back();
  }

  void _restore() {
    ref.read(songTagsProvider.notifier).reset(widget.song.songKey);
    ref.read(navigationProvider.notifier).back();
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    final edited = ref.watch(hasEditedTagsProvider(song.songKey));
    // The cover as it will be once saved.
    final fileSong = _removeCover
        ? ref.read(libraryProvider.notifier).fileSong(song.songKey)
        : null;
    final coverSong = fileSong ?? song;
    final picked = _pickedCover;
    return Stack(
      children: [
        Positioned.fill(
          child: SongBackdrop(song: coverSong, cover: picked),
        ),
        SafeArea(
          bottom: false,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 12, 24, 8),
                child: PageHeader(title: 'Edit song'),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                  physics: const BouncingScrollPhysics(),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    const SizedBox(height: 8),
                    Center(
                      child: GestureDetector(
                        onTap: _pickCover,
                        child: _CoverPreview(song: coverSong, picked: picked),
                      ),
                    ),
                    // The cover itself (and its pen badge) changes it.
                    if (_hasPickedCover) ...[
                      const SizedBox(height: 18),
                      Center(
                        child: ActionPill(
                          icon: AppIcons.undo,
                          label: 'Use file\'s cover',
                          onTap: _useFileCover,
                        ),
                      ),
                    ],
                    const SizedBox(height: 26),
                    _fieldsCard(),
                    const SizedBox(height: 10),
                    Text(
                      'Changes stay in MyZik and follow the song to your '
                      'other devices. The audio file is left untouched.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.whiteAlpha(0.45),
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        ActionPill(
                          icon: AppIcons.checkCircle,
                          label: _saving ? 'Saving…' : 'Save',
                          primary: true,
                          onTap: _valid && !_saving ? _save : null,
                        ),
                        if (edited)
                          ActionPill(
                            icon: AppIcons.retry,
                            label: 'Restore file info',
                            onTap: _saving ? null : _restore,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The fields in a card like the detail page's info card.
  Widget _fieldsCard() {
    final rows = [
      _FieldRow(label: 'Title', controller: _title, onChanged: _changed),
      _FieldRow(label: 'Artist', controller: _artist, onChanged: _changed),
      _FieldRow(
        label: 'Album',
        controller: _album,
        hint: 'Unknown album',
        onChanged: _changed,
        onSubmitted: _save,
      ),
    ];
    return Container(
      decoration: BoxDecoration(
        color: AppColors.whiteAlpha(0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.whiteAlpha(0.07)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i != rows.length - 1)
              Divider(height: 1, color: AppColors.whiteAlpha(0.06)),
          ],
        ],
      ),
    );
  }

  void _changed() => setState(() {});
}

/// The cover as it will look, with a camera badge saying it can be changed.
class _CoverPreview extends StatelessWidget {
  const _CoverPreview({required this.song, this.picked});

  final Song song;
  final Uint8List? picked;

  static const _size = 220.0;

  @override
  Widget build(BuildContext context) {
    final picked = this.picked;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 40,
            offset: const Offset(0, 20),
            spreadRadius: -10,
          ),
        ],
      ),
      child: Stack(
        children: [
          if (picked != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Image.memory(
                picked,
                width: _size,
                height: _size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            )
          else
            SongArtwork(song: song, size: _size, radius: 28),
          Positioned(
            right: 12,
            bottom: 12,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.55),
                border: Border.all(color: AppColors.whiteAlpha(0.2)),
              ),
              child: const Icon(
                AppIcons.edit,
                size: 18,
                color: AppColors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One editable line of the card: the label on the left, the field filling
/// the rest.
class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.hint,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final String? hint;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.whiteAlpha(0.5),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              textAlign: TextAlign.right,
              cursorColor: AppColors.accentA,
              textCapitalization: TextCapitalization.words,
              textInputAction: onSubmitted == null
                  ? TextInputAction.next
                  : TextInputAction.done,
              onChanged: (_) => onChanged(),
              onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
                hintText: hint,
                hintStyle: TextStyle(
                  color: AppColors.whiteAlpha(0.3),
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
