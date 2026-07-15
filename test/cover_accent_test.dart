// Verifies coverAccentProvider extracts a cover's dominant colour, and yields
// null when a track has no artwork.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_zik/data/music_repository.dart';
import 'package:my_zik/models.dart';
import 'package:my_zik/providers/library_provider.dart';

class _ArtRepo implements MusicRepository {
  _ArtRepo(this.bytes);
  final Uint8List? bytes;

  @override
  bool get isSupported => true;
  @override
  Future<bool> ensurePermission() async => true;
  @override
  Future<List<Song>> fetchSongs() async => const [
    Song(id: 1, title: 'A', artist: 'x'),
  ];
  @override
  Future<Uint8List?> artworkFor(int id) async => bytes;
}

Future<Uint8List> _solidPng(int r, int g, int b, {int size = 16}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    ui.Paint()..color = ui.Color.fromARGB(255, r, g, b),
  );
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  test('coverAccent extracts a cover\'s dominant colour', () async {
    final png = await _solidPng(220, 40, 40); // strong red
    final container = ProviderContainer(
      overrides: [musicRepositoryProvider.overrideWithValue(_ArtRepo(png))],
    );
    addTearDown(container.dispose);

    final color = await container.read(coverAccentProvider(1).future);
    expect(color, isNotNull);
    expect(color!.r, greaterThan(0.7)); // red channel dominant (0..1)
    expect(color.g, lessThan(0.35));
    expect(color.b, lessThan(0.35));
  });

  test('coverAccent is null when the track has no artwork', () async {
    final container = ProviderContainer(
      overrides: [musicRepositoryProvider.overrideWithValue(_ArtRepo(null))],
    );
    addTearDown(container.dispose);

    expect(await container.read(coverAccentProvider(1).future), isNull);
  });
}
