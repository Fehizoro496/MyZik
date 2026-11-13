import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shared_preferences_provider.dart';

/// Who the app greets: a display name and an optional photo of their own.
class Profile {
  const Profile({required this.name, this.avatarPath});

  static const defaultName = 'Fehizoro';

  final String name;

  /// The picked photo, copied into the app's support folder; null shows the
  /// bundled avatar.
  final String? avatarPath;
}

/// The profile shown on Home and edited in Settings, persisted to
/// [SharedPreferences].
class ProfileNotifier extends Notifier<Profile> {
  static const _nameKey = 'profile.name';
  static const _avatarKey = 'profile.avatar';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  Profile build() {
    final avatar = _prefs.getString(_avatarKey);
    return Profile(
      name: _prefs.getString(_nameKey) ?? Profile.defaultName,
      avatarPath: avatar != null && File(avatar).existsSync() ? avatar : null,
    );
  }

  /// Renames the profile; a blank name brings the default back.
  Future<void> setName(String name) async {
    final trimmed = name.trim();
    state = Profile(
      name: trimmed.isEmpty ? Profile.defaultName : trimmed,
      avatarPath: state.avatarPath,
    );
    if (trimmed.isEmpty) {
      await _prefs.remove(_nameKey);
    } else {
      await _prefs.setString(_nameKey, trimmed);
    }
  }

  /// Keeps [bytes] as the profile photo. Each photo gets its own file name so
  /// the image cache never shows the previous one.
  Future<void> setAvatar(Uint8List bytes) async {
    final folder = await getApplicationSupportDirectory();
    final file = File(
      p.join(
        folder.path,
        'avatar_${DateTime.now().millisecondsSinceEpoch}.img',
      ),
    );
    await file.writeAsBytes(bytes, flush: true);
    _deleteAvatarFile();
    state = Profile(name: state.name, avatarPath: file.path);
    await _prefs.setString(_avatarKey, file.path);
  }

  /// Goes back to the bundled avatar.
  Future<void> removeAvatar() async {
    _deleteAvatarFile();
    state = Profile(name: state.name);
    await _prefs.remove(_avatarKey);
  }

  void _deleteAvatarFile() {
    final path = state.avatarPath;
    if (path == null) return;
    try {
      File(path).deleteSync();
    } catch (_) {}
  }
}

final profileProvider = NotifierProvider<ProfileNotifier, Profile>(
  ProfileNotifier.new,
);
