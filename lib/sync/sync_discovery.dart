import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart' as nsd;

/// A computer found on the network.
class DiscoveredServer {
  const DiscoveredServer(this.host, this.port);

  final String host;
  final int port;
}

/// Finds paired computers on the local network, so a changed IP address
/// doesn't break synchronization.
abstract class SyncDiscovery {
  /// Announces this computer as [serverId] on [port].
  Future<void> advertise({
    required String serverId,
    required String name,
    required int port,
  });

  Future<void> stopAdvertising();

  /// Where [serverId] answers, if it is found within [timeout].
  Future<List<DiscoveredServer>> find(
    String serverId, {
    Duration timeout = const Duration(seconds: 4),
  });
}

/// [SyncDiscovery] over mDNS / DNS-SD (Bonjour), with the `nsd` plugin.
class NsdSyncDiscovery implements SyncDiscovery {
  static const serviceType = '_myzik._tcp';

  nsd.Registration? _registration;

  @override
  Future<void> advertise({
    required String serverId,
    required String name,
    required int port,
  }) async {
    await stopAdvertising();
    try {
      _registration = await nsd.register(
        nsd.Service(
          name: name,
          type: serviceType,
          port: port,
          txt: {'id': utf8.encode(serverId)},
        ),
      );
    } catch (e) {
      // Synchronization still works through the QR code's addresses.
      debugPrint('Sync: cannot announce on the network: $e');
    }
  }

  @override
  Future<void> stopAdvertising() async {
    final registration = _registration;
    _registration = null;
    if (registration == null) return;
    try {
      await nsd.unregister(registration);
    } catch (_) {
      // Already gone.
    }
  }

  @override
  Future<List<DiscoveredServer>> find(
    String serverId, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    nsd.Discovery? discovery;
    final found = Completer<List<DiscoveredServer>>();
    try {
      discovery = await nsd.startDiscovery(
        serviceType,
        ipLookupType: nsd.IpLookupType.v4,
      );
      discovery.addServiceListener((service, status) {
        if (status != nsd.ServiceStatus.found || found.isCompleted) return;
        final id = service.txt?['id'];
        if (id == null || utf8.decode(id, allowMalformed: true) != serverId) {
          return;
        }
        final port = service.port;
        if (port == null) return;
        final hosts = [
          for (final address in service.addresses ?? const <InternetAddress>[])
            address.address,
          ?service.host,
        ];
        found.complete([for (final h in hosts) DiscoveredServer(h, port)]);
      });
      return await found.future.timeout(timeout, onTimeout: () => const []);
    } catch (e) {
      debugPrint('Sync: network discovery failed: $e');
      return const [];
    } finally {
      if (discovery != null) {
        try {
          await nsd.stopDiscovery(discovery);
        } catch (_) {
          // Already stopped.
        }
      }
    }
  }
}
