import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_zik/data/sample_music_repository.dart';
import 'package:my_zik/main.dart';
import 'package:my_zik/providers/library_provider.dart';
import 'package:my_zik/providers/navigation_provider.dart';
import 'package:my_zik/providers/shared_preferences_provider.dart';
import 'package:my_zik/providers/sync_providers.dart';
import 'package:my_zik/sync/sync_client.dart';
import 'package:my_zik/sync/sync_server.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The computer's server, without sockets.
class _FakeServer extends SyncServerNotifier {
  @override
  SyncServerState build() => SyncServerState(
    running: true,
    port: 47815,
    addresses: const ['192.168.1.20'],
    devices: [
      PairedDevice(
        id: 'phone-1',
        name: 'Android phone',
        tokenHash: 'x',
        pairedAt: DateTime(2026, 10, 1, 9),
        lastSyncAt: DateTime(2026, 10, 27, 18, 5),
      ),
    ],
  );

  @override
  Future<void> startPairing() async {
    state = state.copyWith(
      pairing: const PairingPayload(
        serverId: 'desk',
        serverName: 'DESK',
        hosts: ['192.168.1.20'],
        port: 47815,
        code: '123456',
      ),
    );
  }

  @override
  void cancelPairing() => state = state.copyWith(clearPairing: true);

  @override
  void revoke(String deviceId) => state = state.copyWith(devices: const []);
}

/// The phone's client, without network.
class _FakeClient extends SyncClientNotifier {
  _FakeClient(this.initial);

  final SyncClientState initial;
  int syncs = 0;
  PairingPayload? pairedWith;

  @override
  SyncClientState build() => initial;

  @override
  Future<void> syncNow() async => syncs++;

  @override
  Future<void> pairWith(PairingPayload payload) async => pairedWith = payload;

  @override
  void setMode(TransferMode mode) => state = state.copyWith(mode: mode);

  @override
  void setTransport(SyncTransport transport) =>
      state = state.copyWith(transport: transport);
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required bool desktop,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = desktop
      ? const Size(1440, 900)
      : const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        musicRepositoryProvider.overrideWithValue(SampleMusicRepository()),
        ...overrides,
      ],
      child: MyZikApp(desktop: desktop),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(MyZikApp)));
}

void main() {
  testWidgets('the computer pairs a phone with a QR code and unpairs it', (
    tester,
  ) async {
    await _pump(
      tester,
      desktop: true,
      overrides: [syncServerProvider.overrideWith(_FakeServer.new)],
    );

    await tester.tap(find.text('Sync with phone'));
    await tester.pumpAndSettle();
    expect(find.text('Ready for your phone'), findsOneWidget);
    expect(find.text('Android phone'), findsOneWidget);

    await tester.tap(find.text('Pair a phone'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.textContaining('code 123456'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Unpair'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Unpair'));
    await tester.pumpAndSettle();
    expect(find.text('No phone yet.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an unpaired phone offers to scan or type the code', (
    tester,
  ) async {
    final client = _FakeClient(const SyncClientState());
    final container = await _pump(
      tester,
      desktop: false,
      overrides: [syncClientProvider.overrideWith(() => client)],
    );
    container.read(navigationProvider.notifier).goTo(AppScreen.sync);
    await tester.pumpAndSettle();

    expect(find.text('Sync with your computer'), findsOneWidget);
    expect(find.text('Scan the code'), findsOneWidget);

    await tester.tap(find.text('Enter the code by hand'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '192.168.1.20');
    await tester.enterText(fields.at(2), '654321');
    await tester.tap(find.text('Pair'));
    await tester.pumpAndSettle();
    expect(client.pairedWith?.hosts, ['192.168.1.20']);
    expect(client.pairedWith?.port, SyncServer.defaultPort);
    expect(client.pairedWith?.code, '654321');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an Android phone can pair through the USB cable', (
    tester,
  ) async {
    final client = _FakeClient(const SyncClientState());
    final container = await _pump(
      tester,
      desktop: false,
      overrides: [syncClientProvider.overrideWith(() => client)],
    );
    container.read(navigationProvider.notifier).goTo(AppScreen.sync);
    await tester.pumpAndSettle();

    await tester.tap(find.text('USB cable'));
    await tester.pumpAndSettle();
    expect(container.read(syncClientProvider).transport, SyncTransport.usb);
    expect(find.textContaining('USB debugging'), findsWidgets);

    await tester.tap(find.text('Enter the code by hand'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(2), '654321');
    await tester.tap(find.text('Pair'));
    await tester.pumpAndSettle();
    expect(client.pairedWith?.hosts, ['127.0.0.1']);

    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('a paired phone syncs on demand and picks a transfer mode', (
    tester,
  ) async {
    final client = _FakeClient(
      SyncClientState(
        connection: const SyncConnection(
          serverId: 'desk',
          serverName: 'DESK',
          hosts: ['192.168.1.20'],
          port: 47815,
          token: 't',
        ),
        lastSyncAt: DateTime.now().subtract(const Duration(minutes: 5)),
        lastReport: const SyncReport(sent: 2, received: 3, downloaded: 1),
      ),
    );
    final container = await _pump(
      tester,
      desktop: false,
      overrides: [syncClientProvider.overrideWith(() => client)],
    );
    container.read(navigationProvider.notifier).goTo(AppScreen.sync);
    await tester.pumpAndSettle();

    expect(find.text('DESK'), findsOneWidget);
    expect(find.text('Synced 5 min ago'), findsOneWidget);
    expect(find.textContaining('2 changes sent, 3 received'), findsOneWidget);

    await tester.tap(find.text('Sync now'));
    await tester.pump();
    expect(client.syncs, 1);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(container.read(syncClientProvider).mode, TransferMode.everything);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
