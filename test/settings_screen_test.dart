import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_zik/data/sample_music_repository.dart';
import 'package:my_zik/icons.dart';
import 'package:my_zik/main.dart';
import 'package:my_zik/providers/app_database_provider.dart';
import 'package:my_zik/providers/library_provider.dart';
import 'package:my_zik/providers/shared_preferences_provider.dart';
import 'package:my_zik/screens/lyrics_view.dart' show autoSyncConsentKey;

import 'support/test_database.dart';

void main() {
  testWidgets('the avatar opens Settings, where the name is changed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({autoSyncConsentKey: true});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(await testDatabase(tester)),
          musicRepositoryProvider.overrideWithValue(SampleMusicRepository()),
        ],
        child: const MyZikApp(desktop: false),
      ),
    );
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('AI synchronization'), findsOneWidget);

    // Turning AI synchronization off asks again next time.
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(prefs.getBool(autoSyncConsentKey), isNull);

    await tester.tap(find.text('Fehizoro'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Alex');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Alex'), findsOneWidget);
    expect(prefs.getString('profile.name'), 'Alex');

    await tester.tap(find.byIcon(AppIcons.back));
    await tester.pumpAndSettle();
    expect(find.text('Hi, Alex'), findsOneWidget);
  });
}
