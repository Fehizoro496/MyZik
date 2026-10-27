import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/app_sync.dart';
import '../sync/sync_client.dart';
import '../sync/sync_discovery.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_files.dart';
import '../sync/sync_server.dart';
import '../sync/sync_store.dart';
import 'shared_preferences_provider.dart';

/// The journal of synchronized changes on this device.
final syncStoreProvider = Provider<SyncStore>(
  (ref) => SyncStore(ref.read(sharedPreferencesProvider)),
);

final syncEngineProvider = Provider<SyncEngine>(
  (ref) => SyncEngine(ref.read(syncStoreProvider), AppSyncData(ref)),
);

final syncFilesProvider = Provider<SyncFiles>((ref) => AppSyncFiles(ref));

final syncDiscoveryProvider = Provider<SyncDiscovery>(
  (ref) => NsdSyncDiscovery(),
);

/// What the computer's Sync page shows.
class SyncServerState {
  const SyncServerState({
    this.running = false,
    this.port,
    this.addresses = const [],
    this.error,
    this.devices = const [],
    this.pairing,
    this.lastEvent,
  });

  final bool running;
  final int? port;
  final List<String> addresses;
  final String? error;
  final List<PairedDevice> devices;

  /// The pairing window open right now, as shown in the QR code.
  final PairingPayload? pairing;
  final String? lastEvent;

  SyncServerState copyWith({
    bool? running,
    int? port,
    List<String>? addresses,
    String? error,
    List<PairedDevice>? devices,
    PairingPayload? pairing,
    bool clearPairing = false,
    String? lastEvent,
  }) => SyncServerState(
    running: running ?? this.running,
    port: port ?? this.port,
    addresses: addresses ?? this.addresses,
    error: error,
    devices: devices ?? this.devices,
    pairing: clearPairing ? null : pairing ?? this.pairing,
    lastEvent: lastEvent ?? this.lastEvent,
  );
}

/// Runs the synchronization server on the computer and keeps the Sync page
/// up to date.
class SyncServerNotifier extends Notifier<SyncServerState> {
  late final SyncServer _server;
  StreamSubscription<SyncServerEvent>? _events;

  @override
  SyncServerState build() {
    _server = SyncServer(
      engine: ref.read(syncEngineProvider),
      files: ref.read(syncFilesProvider),
      preferences: ref.read(sharedPreferencesProvider),
      name: Platform.localHostname,
    );
    _events = _server.events.listen(_onEvent);
    ref.onDispose(() {
      _events?.cancel();
      ref.read(syncDiscoveryProvider).stopAdvertising();
      _server.dispose();
    });
    return SyncServerState(devices: _server.devices);
  }

  /// Starts listening and announces the computer on the network.
  Future<void> start() async {
    if (_server.isRunning) return;
    try {
      await _server.start();
      state = state.copyWith(
        running: true,
        port: _server.boundPort,
        addresses: await localAddresses(),
      );
      await ref
          .read(syncDiscoveryProvider)
          .advertise(
            serverId: _server.serverId,
            name: 'My Zik on ${_server.name}',
            port: _server.boundPort!,
          );
    } catch (e) {
      state = state.copyWith(running: false, error: 'Cannot start: $e');
    }
  }

  /// Opens a pairing window; the QR code shows [SyncServerState.pairing].
  Future<void> startPairing() async {
    await start();
    final payload = await _server.payloadFor(_server.startPairing());
    state = state.copyWith(pairing: payload, addresses: payload.hosts);
  }

  void cancelPairing() {
    _server.cancelPairing();
    state = state.copyWith(clearPairing: true);
  }

  void revoke(String deviceId) {
    _server.revoke(deviceId);
    state = state.copyWith(devices: _server.devices);
  }

  void _onEvent(SyncServerEvent event) {
    state = state.copyWith(
      devices: _server.devices,
      clearPairing: event is DevicePaired,
      lastEvent: switch (event) {
        DevicePaired(:final device) => '${device.name} is paired.',
        DeviceSynced(:final device, :final received) =>
          received == 0
              ? '${device.name} synced.'
              : '${device.name} synced $received change'
                    '${received == 1 ? '' : 's'}.',
        FileReceived(:final device, :final track) =>
          'Received “${track.title}” from ${device.name}.',
      },
    );
  }
}

final syncServerProvider =
    NotifierProvider<SyncServerNotifier, SyncServerState>(
      SyncServerNotifier.new,
    );

/// What the phone's Sync screen shows.
class SyncClientState {
  const SyncClientState({
    this.connection,
    this.mode = TransferMode.downloads,
    this.syncing = false,
    this.progress,
    this.lastSyncAt,
    this.lastReport,
    this.error,
  });

  final SyncConnection? connection;
  final TransferMode mode;
  final bool syncing;
  final SyncProgress? progress;
  final DateTime? lastSyncAt;
  final SyncReport? lastReport;
  final String? error;

  bool get paired => connection != null;

  SyncClientState copyWith({
    SyncConnection? connection,
    bool clearConnection = false,
    TransferMode? mode,
    bool? syncing,
    SyncProgress? progress,
    DateTime? lastSyncAt,
    SyncReport? lastReport,
    String? error,
  }) => SyncClientState(
    connection: clearConnection ? null : connection ?? this.connection,
    mode: mode ?? this.mode,
    syncing: syncing ?? this.syncing,
    progress: progress,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    lastReport: lastReport ?? this.lastReport,
    error: error,
  );
}

/// The phone's synchronization: pairing, syncing on demand and whenever the
/// app comes back to the foreground.
class SyncClientNotifier extends Notifier<SyncClientState> {
  late final SyncClient _client;
  static const _modeKey = 'sync.transferMode';

  @override
  SyncClientState build() {
    _client = SyncClient(
      engine: ref.read(syncEngineProvider),
      files: ref.read(syncFilesProvider),
      preferences: ref.read(sharedPreferencesProvider),
      discovery: ref.read(syncDiscoveryProvider),
    );
    final lifecycle = AppLifecycleListener(onResume: syncIfPaired);
    ref.onDispose(() {
      lifecycle.dispose();
      _client.close();
    });
    final mode = TransferMode.values
        .where(
          (m) =>
              m.name == ref.read(sharedPreferencesProvider).getString(_modeKey),
        )
        .firstOrNull;
    final initial = SyncClientState(
      connection: _client.connection,
      mode: mode ?? TransferMode.downloads,
      lastSyncAt: _client.lastSyncAt,
    );
    if (initial.paired) Future.microtask(syncIfPaired);
    return initial;
  }

  /// Pairs with the computer whose QR code read [text].
  Future<void> pair(String text) async {
    final payload = PairingPayload.tryDecode(text);
    if (payload == null) {
      state = state.copyWith(error: 'This is not a My Zik pairing code.');
      return;
    }
    await pairWith(payload);
  }

  /// Pairs from the details typed by hand.
  Future<void> pairWith(PairingPayload payload) async {
    state = state.copyWith(
      syncing: true,
      progress: const SyncProgress('Pairing…'),
    );
    try {
      final connection = await _client.pair(
        payload,
        deviceName: Platform.isAndroid
            ? 'Android phone'
            : Platform.isIOS
            ? 'iPhone'
            : Platform.localHostname,
      );
      state = state.copyWith(connection: connection, syncing: false);
      await syncNow();
    } on SyncException catch (e) {
      state = state.copyWith(syncing: false, error: e.message);
    }
  }

  void unpair() {
    _client.unpair();
    state = SyncClientState(mode: state.mode);
  }

  void setMode(TransferMode mode) {
    ref.read(sharedPreferencesProvider).setString(_modeKey, mode.name);
    state = state.copyWith(mode: mode);
  }

  Future<void> syncIfPaired() async {
    if (state.paired && !state.syncing) await syncNow();
  }

  Future<void> syncNow() => _run(
    (onProgress) => _client.sync(mode: state.mode, onProgress: onProgress),
  );

  /// Files only one side has, to pick from.
  Future<FileDifferences?> differences() async {
    try {
      return await _client.differences();
    } on SyncException catch (e) {
      state = state.copyWith(error: e.message);
      return null;
    }
  }

  Future<void> transfer(FileDifferences picked) =>
      _run((onProgress) => _client.transfer(picked, onProgress: onProgress));

  Future<void> _run(
    Future<SyncReport> Function(void Function(SyncProgress) onProgress) job,
  ) async {
    if (state.syncing) return;
    state = state.copyWith(syncing: true);
    try {
      final report = await job((progress) {
        state = state.copyWith(syncing: true, progress: progress);
      });
      state = state.copyWith(
        syncing: false,
        lastReport: report,
        lastSyncAt: _client.lastSyncAt,
      );
    } on SyncException catch (e) {
      if (e.unpaired) _client.unpair();
      state = state.copyWith(
        syncing: false,
        error: e.message,
        clearConnection: e.unpaired,
      );
    } catch (e) {
      state = state.copyWith(syncing: false, error: 'Sync failed: $e');
    }
  }
}

final syncClientProvider =
    NotifierProvider<SyncClientNotifier, SyncClientState>(
      SyncClientNotifier.new,
    );
