import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../icons.dart';
import '../providers/library_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/shared_preferences_provider.dart';
import '../theme.dart';
import '../widgets.dart';
import 'edit_song_screen.dart' show pickCoverImage;
import 'lyrics_view.dart' show autoSyncConsentKey;

/// The profile photo, or the bundled avatar until one is picked.
class ProfileAvatar extends ConsumerWidget {
  const ProfileAvatar({super.key, this.radius = 22});

  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(profileProvider.select((p) => p.avatarPath));
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF1A1730),
      backgroundImage: path != null
          ? FileImage(File(path))
          : const AssetImage('assets/images/avatar.png') as ImageProvider,
    );
  }
}

/// Opened from the avatar on Home: the profile, lyrics and library options,
/// and a way to Sync.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.musicBackground),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
          children: [
            const PageHeader(title: 'Settings'),
            const SizedBox(height: 28),
            const _ProfileCard(),
            const SizedBox(height: 32),
            const _SectionLabel('Lyrics'),
            const _AutoSyncTile(),
            const SizedBox(height: 28),
            const _SectionLabel('Library'),
            _Group(
              children: [
                _Tile(
                  icon: AppIcons.retry,
                  title: 'Rescan library',
                  subtitle: library.status == LibraryStatus.loading
                      ? 'Scanning…'
                      : '${library.songs.length} songs',
                  onTap: library.status == LibraryStatus.loading
                      ? null
                      : () => ref.read(libraryProvider.notifier).load(),
                ),
                _Tile(
                  icon: AppIcons.sync,
                  title: 'Sync with a computer',
                  subtitle: 'Likes, playlists, lyrics and music',
                  trailing: Icon(
                    AppIcons.chevronRight,
                    size: 16,
                    color: AppColors.whiteAlpha(0.4),
                  ),
                  onTap: () => ref
                      .read(navigationProvider.notifier)
                      .goTo(AppScreen.sync),
                ),
              ],
            ),
            const SizedBox(height: 36),
            Center(
              child: Text(
                'My Zik',
                style: TextStyle(
                  color: AppColors.whiteAlpha(0.35),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The photo (tap to change it) and the name Home greets.
class _ProfileCard extends ConsumerWidget {
  const _ProfileCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final notifier = ref.read(profileProvider.notifier);
    return Column(
      children: [
        GestureDetector(
          onTap: () => _changePhoto(context, ref),
          child: Stack(
            children: [
              const ProfileAvatar(radius: 48),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.white,
                    border: Border.all(
                      color: AppColors.musicBackground,
                      width: 3,
                    ),
                  ),
                  child: const Icon(
                    AppIcons.camera,
                    size: 15,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () async {
            final name = await _askName(context, profile.name);
            if (name != null) await notifier.setName(name);
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  profile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(AppIcons.edit, size: 16, color: AppColors.whiteAlpha(0.5)),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _changePhoto(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(profileProvider.notifier);
    final hasPhoto = ref.read(profileProvider).avatarPath != null;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(AppIcons.camera),
              title: const Text('Choose a photo'),
              onTap: () => Navigator.pop(context, 'pick'),
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(AppIcons.delete),
                title: const Text('Remove the photo'),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
          ],
        ),
      ),
    );
    switch (choice) {
      case 'pick':
        final bytes = await pickCoverImage();
        if (bytes != null) await notifier.setAvatar(bytes);
      case 'remove':
        await notifier.removeAvatar();
    }
  }

  Future<String?> _askName(BuildContext context, String current) =>
      showDialog<String>(
        context: context,
        builder: (context) => _NameDialog(current),
      );
}

/// Asks for the profile's name; owns its controller so it outlives the
/// dialog's closing animation.
class _NameDialog extends StatefulWidget {
  const _NameDialog(this.current);

  final String current;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Your name'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Whether tracks may be sent to Groq without asking first: switched on by
/// the first "Continue" of [confirmAutoSync], off to be asked again.
class _AutoSyncTile extends ConsumerStatefulWidget {
  const _AutoSyncTile();

  @override
  ConsumerState<_AutoSyncTile> createState() => _AutoSyncTileState();
}

class _AutoSyncTileState extends ConsumerState<_AutoSyncTile> {
  @override
  Widget build(BuildContext context) {
    final prefs = ref.read(sharedPreferencesProvider);
    final allowed = prefs.getBool(autoSyncConsentKey) ?? false;
    return _Group(
      children: [
        _Tile(
          icon: AppIcons.sparkles,
          title: 'AI synchronization',
          subtitle: allowed
              ? 'Audio is sent to Groq without asking'
              : 'Asks before sending audio to Groq',
          trailing: Switch(
            value: allowed,
            onChanged: (value) async {
              if (value) {
                await prefs.setBool(autoSyncConsentKey, true);
              } else {
                await prefs.remove(autoSyncConsentKey);
              }
              if (mounted) setState(() {});
            },
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: AppColors.whiteAlpha(0.45),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

/// Rows on one glass card, separated by hairlines.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // A Material rather than a decorated box, so the rows' ink shows on it.
    return Material(
      clipBehavior: Clip.antiAlias,
      color: AppColors.whiteAlpha(0.05),
      borderRadius: BorderRadius.circular(20),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(height: 1, indent: 62, color: AppColors.whiteAlpha(0.06)),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: AppColors.accentGradient,
              ),
              child: Icon(icon, size: 16, color: AppColors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: AppColors.whiteAlpha(0.5),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          ],
        ),
      ),
    );
  }
}
