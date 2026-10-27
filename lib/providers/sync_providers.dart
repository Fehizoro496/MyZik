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
import '../sync/usb_bridge.dart';
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

final usbBridgeProvider = Provider<UsbBridge>((ref) => UsbBridge());

/// Sync by USB cable on the computer: the phones plugged in and whether
/// they reach the server.
class UsbSyncState {
  const UsbSyncState({
    this.enabled = false,
    this.adb,
    this.adbMissing = false,
    this.devices = const [],
    this.connected = const {},
    this.error,
  });

  final bool enabled;

  /// The `adb` in use, once found.
  final String? adb;
  final bool adbMissing;
  final List<UsbDevice> devices;

  /// Serials of the phones whose `127.0.0.1` leads to the server.
  final Set<String> connected;
  final String? error;
}

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
    this.usb = const UsbSyncState(),
  });

  final bool running;
  final int? port;
  final List<String> addresses;
  final String? error;
  final List<PairedDevice> devices;

  /// The pairing window open right now, as shown in the QR code.
  final PairingPayload? pairing;
  final String? lastEvent;
  final UsbSyncState usb;

  SyncServerState copyWith({
    bool? running,
    int? port,
    List<String>? addresses,
    String? error,
    List<PairedDevice>? devices,
    PairingPayload? pairing,
    bool clearPairing = false,
    String? lastEvent,
    UsbSyncState? usb,
  }) => SyncServerState(
    running: running ?? this.running,
    port: port ?? this.port,
    addresses: addresses ?? this.addresses,
    error: error,
    devices: devices ?? this.devices,
    pairing: clearPairing ? null : pairing ?? this.pairing,
    lastEvent: lastEvent ?? this.lastEvent,
    usb: usb ?? this.usb,
  );
}

/// Runs the synchronization server on the computer and keeps the Sync page
/// up to date.
class SyncServerNotifier extends Notifier<SyncServerState> {
  late final SyncServer _server;
  StreamSubscription<SyncServerEvent>? _events;
  Timer? _usbTimer;
  bool _usbChecking = false;

  static const _usbKey = 'sync.usb.enabled';
  static const _adbKey = 'sync.usb.adbPath';

  @override
  SyncServerState build() {
    _server = SyncServer(
      engine: ref.read(syncEngineProvider),
      files: ref.read(syncFilesProvider),
      preferences: ref.read(sharedPreferencesProvider),
      name: Platform.localHostname,
    );
    _events = _server.events.listen(_onEvent);
    final prefs = ref.read(sharedPreferencesProvider);
    ref.read(usbBridgeProvider).adbPath = prefs.getString(_adbKey);
    if (prefs.getBool(_usbKey) ?? false) {
      Future.microtask(() => setUsb(true));
    }
    ref.onDispose(() {
      _usbTimer?.cancel();
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

  /// Turns sync by USB cable on or off. While on, phones plugged in are
  /// connected to the server every few seconds, as they come.
  Future<void> setUsb(bool enabled) async {
    ref.read(sharedPreferencesProvider).setBool(_usbKey, enabled);
    _usbTimer?.cancel();
    _usbTimer = null;
    if (!enabled) {
      state = state.copyWith(usb: const UsbSyncState());
      return;
    }
    state = state.copyWith(usb: const UsbSyncState(enabled: true));
    await start();
    _usbTimer = Timer.periodic(const Duration(seconds: 3), (_) => checkUsb());
    await checkUsb();
  }

  /// Uses [path] as `adb`, when it is not found on its own.
  Future<void> chooseAdb(String path) async {
    ref.read(sharedPreferencesProvider).setString(_adbKey, path);
    ref.read(usbBridgeProvider).adbPath = path;
    state = state.copyWith(usb: UsbSyncState(enabled: state.usb.enabled));
    if (state.usb.enabled) await checkUsb();
  }

  /// Lists the phones plugged in and connects the new ones.
  Future<void> checkUsb() async {
    final port = _server.boundPort;
    if (_usbChecking || !state.usb.enabled || port == null) return;
    _usbChecking = true;
    final bridge = ref.read(usbBridgeProvider);
    var usb = state.usb;
    try {
      final adb = usb.adb ?? await bridge.findAdb();
      if (adb == null) {
        usb = UsbSyncState(enabled: true, adbMissing: true);
        return;
      }
      final devices = await bridge.devices(adb);
      final connected = {
        for (final serial in usb.connected)
          if (devices.any((d) => d.ready && d.serial == serial)) serial,
      };
      String? error;
      for (final device in devices) {
        if (!device.ready || connected.contains(device.serial)) continue;
        try {
          await bridge.reverse(adb, device, port);
          connected.add(device.serial);
        } on UsbBridgeException catch (e) {
          error = e.message;
        }
      }
      usb = UsbSyncState(
        enabled: true,
        adb: adb,
        devices: devices,
        connected: connected,
        error: error,
      );
    } catch (e) {
      usb = UsbSyncState(enabled: true, adb: usb.adb, error: '$e');
    } finally {
      _usbChecking = false;
      // Turned off meanwhile: stay off.
      if (state.usb.enabled) state = state.copyWith(usb: usb);
    }
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
    this.transport = SyncTransport.wifi,
    this.syncing = false,
    this.progress,
    this.lastSyncAt,
    this.lastReport,
    this.error,
  });

  final SyncConnection? connection;
  final TransferMode mode;
  final SyncTransport transport;
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
    SyncTransport? transport,
    bool? syncing,
    SyncProgress? progress,
    DateTime? lastSyncAt,
    SyncReport? lastReport,
    String? error,
  }) => SyncClientState(
    connection: clearConnection ? null : connection ?? this.connection,
    mode: mode ?? this.mode,
    transport: transport ?? this.transport,
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
  static const _transportKey = 'sync.transport';

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
    final transport = SyncTransport.values
        .where(
          (t) =>
              t.name ==
              ref.read(sharedPreferencesProvider).getString(_transportKey),
        )
        .firstOrNull;
    _client.transport = transport ?? SyncTransport.wifi;
    final initial = SyncClientState(
      connection: _client.connection,
      mode: mode ?? TransferMode.downloads,
      transport: _client.transport,
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
    state = SyncClientState(mode: state.mode, transport: state.transport);
  }

  /// Reaches the computer over Wi-Fi or by USB cable from now on.
  void setTransport(SyncTransport transport) {
    ref
        .read(sharedPreferencesProvider)
        .setString(_transportKey, transport.name);
    _client.transport = transport;
    state = state.copyWith(transport: transport);
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
