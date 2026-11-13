import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models.dart';
import '../sync/sync_store.dart';
import 'app_database_provider.dart';
import 'sync_providers.dart';

/// Where the covers the listener picked are kept: next to the database, so
/// they live and go with the rest of the app's data.
final editedCoversDirectoryProvider = Provider<Directory>((ref) {
  final database = ref.read(appDatabaseProvider);
  return Directory(p.join(p.dirname(database.path), 'covers'));
});

/// The tags the listener edited, by [Song.songKey]. The library shows songs
/// with these tags (and cover) instead of the ones in their files, and the
/// edits follow the recording to the listener's other devices.
class SongTagsNotifier extends Notifier<Map<String, SongTags>> {
  /// Covers larger than this are scaled down before they are kept: they
  /// travel inside sync records.
  static const _maxCoverBytes = 700 * 1024;
  static const _coverSize = 800;

  @override
  Map<String, SongTags> build() => {
    for (final MapEntry(:key, :value)
        in ref.read(appDatabaseProvider).songTags.entries)
      key: ?SongTags.tryFromJson(value),
  };

  /// [song] with its edited tags and cover, if any.
  Song apply(Song song) {
    final tags = state[song.songKey];
    if (tags == null) return song;
    final edited = song.withTags(tags, coverUrl: coverUrl(tags.cover));
    return edited.sameLabels(song) ? song : edited;
  }

  /// The edited cover named [name], or null.
  File? coverFile(String? name) => name == null
      ? null
      : File(p.join(ref.read(editedCoversDirectoryProvider).path, name));

  String? coverUrl(String? name) => switch (coverFile(name)) {
    final file? => Uri.file(file.path).toString(),
    null => null,
  };

  /// Saves [song]'s new tags: [cover] (image bytes) replaces its cover,
  /// [removeCover] brings back the file's own, otherwise the cover stays as
  /// it is. False when the title or artist is empty.
  Future<bool> save(
    Song song, {
    required String title,
    required String artist,
    String? album,
    Uint8List? cover,
    bool removeCover = false,
  }) async {
    final name = cover != null
        ? await storeCover(cover)
        : removeCover
        ? null
        : state[song.songKey]?.cover;
    final tags = SongTags.tryClean(
      title: title,
      artist: artist,
      album: album,
      cover: name,
    );
    if (tags == null) return false;
    edit(song, tags);
    return true;
  }

  /// Shows [song] with [tags] from now on.
  void edit(Song song, SongTags tags) {
    final key = song.songKey;
    if (state[key] == tags) return;
    _put(key, tags);
    ref.read(syncStoreProvider).touch(SyncIds.forTags(key));
  }

  /// Goes back to the tags and cover in the file of the song with [songKey].
  void reset(String songKey) {
    if (!state.containsKey(songKey)) return;
    _remove(songKey);
    ref.read(syncStoreProvider).touch(SyncIds.forTags(songKey), deleted: true);
  }

  /// Applies tags edited, or reset when [tags] is null, on another device.
  /// [cover] is the picture the other device picked, if any.
  Future<void> setFromSync(
    String songKey,
    SongTags? tags, {
    Uint8List? cover,
  }) async {
    if (tags == null) return _remove(songKey);
    final name = cover == null ? null : await storeCover(cover);
    await _put(songKey, tags.withCover(name));
  }

  /// Keeps [bytes] as an edited cover (scaled down when large) and returns
  /// its file name, made from its content: the same picture gets the same
  /// name on every device.
  Future<String> storeCover(Uint8List bytes) async {
    final data = bytes.length > _maxCoverBytes
        ? await _scaledDown(bytes)
        : bytes;
    final name = '${sha1.convert(data)}${_extension(data)}';
    final file = coverFile(name)!;
    if (!file.existsSync()) {
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data, flush: true);
    }
    return name;
  }

  Future<void> _put(String key, SongTags tags) {
    final previous = state[key]?.cover;
    state = {...state, key: tags};
    _dropUnusedCover(previous);
    return ref.read(appDatabaseProvider).putSongTags(key, tags.toJson());
  }

  Future<void> _remove(String key) {
    if (!state.containsKey(key)) return Future.value();
    final previous = state[key]?.cover;
    state = {...state}..remove(key);
    _dropUnusedCover(previous);
    return ref.read(appDatabaseProvider).deleteSongTags(key);
  }

  /// Deletes the cover [name] once no song shows it any more.
  void _dropUnusedCover(String? name) {
    if (name == null || state.values.any((t) => t.cover == name)) return;
    try {
      coverFile(name)!.deleteSync();
    } catch (_) {
      // Already gone, or still open: left behind, it is small.
    }
  }

  /// [bytes] decoded and encoded again as a PNG of at most [_coverSize]
  /// pixels a side. [bytes] themselves when they can't be decoded.
  static Future<Uint8List> _scaledDown(Uint8List bytes) async {
    try {
      final descriptor = await ui.ImageDescriptor.encoded(
        await ui.ImmutableBuffer.fromUint8List(bytes),
      );
      final wide = descriptor.width >= descriptor.height;
      final codec = await descriptor.instantiateCodec(
        targetWidth: wide ? _coverSize : null,
        targetHeight: wide ? null : _coverSize,
      );
      final image = (await codec.getNextFrame()).image;
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return png?.buffer.asUint8List() ?? bytes;
    } catch (_) {
      return bytes;
    }
  }

  static String _extension(Uint8List data) {
    bool startsWith(List<int> magic) {
      if (data.length < magic.length) return false;
      for (var i = 0; i < magic.length; i++) {
        if (data[i] != magic[i]) return false;
      }
      return true;
    }

    if (startsWith([0x89, 0x50, 0x4E, 0x47])) return '.png';
    if (startsWith([0xFF, 0xD8])) return '.jpg';
    if (startsWith([0x52, 0x49, 0x46, 0x46])) return '.webp';
    return '.img';
  }
}

final songTagsProvider =
    NotifierProvider<SongTagsNotifier, Map<String, SongTags>>(
      SongTagsNotifier.new,
    );

/// Whether the listener edited the tags of the song with this key.
final hasEditedTagsProvider = Provider.family<bool, String>((ref, songKey) {
  return ref.watch(
    songTagsProvider.select((tags) => tags.containsKey(songKey)),
  );
});
