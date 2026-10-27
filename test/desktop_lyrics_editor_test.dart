import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_zik/data/lyrics_repository.dart';
import 'package:my_zik/desktop/lyrics_editor.dart';
import 'package:my_zik/models.dart';
import 'package:my_zik/providers/lyrics_provider.dart';
import 'package:my_zik/providers/shared_preferences_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _song = Song(
  id: 7,
  title: 'Starlit Reverie',
  artist: 'Budiarti',
  duration: Duration(minutes: 3),
);

const _synced = Lyrics(
  source: LyricsSource.manual,
  plain: '[Verse 1]\nFirst line\nSecond line\n\n[Chorus]\nThird line',
  lines: [
    LyricLine(Duration(seconds: 10), 'First line'),
    LyricLine(Duration(seconds: 14), 'Second line'),
    LyricLine(Duration(seconds: 20), 'Third line'),
  ],
);

/// Serves fixed lyrics and records what the editor saves.
class _FakeLyrics extends LyricsNotifier {
  _FakeLyrics(this.saved);

  final List<Lyrics> saved;

  @override
  Future<Lyrics?> build(Song song) async => _synced;

  @override
  Future<void> saveEdited(Lyrics lyrics) async {
    saved.add(lyrics);
    state = AsyncData(lyrics);
  }
}

Future<List<Lyrics>> _pumpEditor(
  WidgetTester tester, {
  Lyrics? lyrics = _synced,
  bool liveSync = false,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final saved = <Lyrics>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        lyricsProvider.overrideWith(() => _FakeLyrics(saved)),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => DesktopLyricsEditor.open(
                  context,
                  _song,
                  lyrics,
                  liveSync: liveSync,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return saved;
}

void main() {
  testWidgets('shows the text and its timing side by side', (tester) async {
    await _pumpEditor(tester);

    expect(find.text('Edit lyrics'), findsOneWidget);
    expect(find.text('TEXT'), findsOneWidget);
    expect(find.text('TIMING'), findsOneWidget);
    expect(find.text('0:10.0'), findsWidgets);
    expect(find.text('CHORUS'), findsOneWidget);
    // The text pane holds the plain lyrics with their section labels.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, _synced.plain);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('nudging a selected line rewrites its time, then saves', (
    tester,
  ) async {
    final saved = await _pumpEditor(tester);

    await tester.tap(find.text('Second line').last);
    // Rows also take double clicks, so a single click lands after the
    // double-click timeout.
    await tester.pump(kDoubleTapTimeout);
    expect(find.text('1 line'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.pump();
    expect(find.text('0:14.1'), findsWidgets);
    expect(find.text('Unsaved changes'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, hasLength(1));
    expect(saved.single.lines[1].time, const Duration(milliseconds: 14100));
    expect(saved.single.edited, isTrue);
    // Saving closes the editor.
    expect(find.text('Open'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a line added in the text gets an estimated time', (
    tester,
  ) async {
    await _pumpEditor(tester);

    await tester.enterText(
      find.byType(TextField),
      '[Verse 1]\nFirst line\nNew line\nSecond line\n\n[Chorus]\nThird line',
    );
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();

    expect(find.text('New line'), findsOneWidget);
    expect(find.textContaining('estimated time'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('merging two selected lines keeps the first time', (
    tester,
  ) async {
    await _pumpEditor(tester);

    await tester.tap(find.text('First line').last);
    await tester.pump(kDoubleTapTimeout);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('Second line').last);
    await tester.pump(kDoubleTapTimeout);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(find.text('2 lines'), findsOneWidget);

    await tester.tap(find.text('Merge'));
    await tester.pump();
    expect(find.text('First line Second line'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('live sync shows the next line to mark', (tester) async {
    await _pumpEditor(tester, liveSync: true);

    expect(find.text('Synchronize lyrics'), findsOneWidget);
    expect(find.text('next →'), findsOneWidget);
    expect(find.text('First line'), findsOneWidget);
    expect(find.text('Mark line'), findsOneWidget);
    expect(find.text('Auto-sync'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('TIMING'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('lyrics without timing offer to synchronize them', (
    tester,
  ) async {
    await _pumpEditor(
      tester,
      lyrics: const Lyrics(
        source: LyricsSource.manual,
        plain: 'First line\nSecond line',
      ),
    );

    expect(find.text('Not synchronized yet'), findsOneWidget);
    await tester.tap(find.widgetWithText(InkWell, 'Live sync').last);
    await tester.pumpAndSettle();
    expect(find.text('next →'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
