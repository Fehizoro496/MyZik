import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../icons.dart';
import '../providers/sync_providers.dart';
import '../sync/sync_server.dart';
import '../theme.dart';
import 'desktop_style.dart';
import 'pages.dart';

/// The computer's side of phone sync: the server's state, pairing a phone
/// with a QR code, and the paired phones.
class SyncPage extends ConsumerWidget {
  const SyncPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncServerProvider);
    final notifier = ref.read(syncServerProvider.notifier);
    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        const PageHeader(
          title: 'Sync with phone',
          subtitle:
              'Likes, playlists, your lyrics and music files, kept in step '
              'with My Zik on your phone over Wi-Fi.',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Card(child: _ServerStatus(sync)),
              const SizedBox(height: 16),
              _Card(
                child: sync.pairing == null
                    ? Row(
                        children: [
                          const Icon(AppIcons.phone, size: 22),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              'Pair a phone once: it then syncs on its own '
                              'whenever both are on the same Wi-Fi.',
                              style: TextStyle(
                                color: AppColors.whiteAlpha(0.7),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          FilledButton.icon(
                            onPressed: sync.running || sync.error == null
                                ? notifier.startPairing
                                : null,
                            icon: const Icon(AppIcons.qrCode, size: 16),
                            label: const Text('Pair a phone'),
                          ),
                        ],
                      )
                    : _Pairing(sync.pairing!),
              ),
              const SizedBox(height: 28),
              Text(
                'PAIRED PHONES',
                style: TextStyle(
                  color: AppColors.whiteAlpha(0.45),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              if (sync.devices.isEmpty)
                Text(
                  'No phone yet.',
                  style: TextStyle(color: AppColors.whiteAlpha(0.45)),
                ),
              for (final device in sync.devices) _DeviceRow(device),
              if (sync.lastEvent != null) ...[
                const SizedBox(height: 20),
                Text(
                  sync.lastEvent!,
                  style: TextStyle(
                    color: AppColors.whiteAlpha(0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: DesktopColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.whiteAlpha(0.06)),
      ),
      child: child,
    );
  }
}

class _ServerStatus extends ConsumerWidget {
  const _ServerStatus(this.sync);

  final SyncServerState sync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = sync.running
        ? DesktopColors.success
        : sync.error != null
        ? DesktopColors.error
        : AppColors.whiteAlpha(0.4);
    final address = sync.addresses.isEmpty
        ? null
        : '${sync.addresses.first}:${sync.port}';
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sync.running
                    ? 'Ready for your phone'
                    : sync.error ?? 'Starting…',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                sync.running
                    ? 'Listening${address == null ? '' : ' on $address'}. '
                          'If Windows asks, allow My Zik on private networks.'
                    : 'Phones can\'t reach this computer right now.',
                style: TextStyle(
                  color: AppColors.whiteAlpha(0.55),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        if (!sync.running && sync.error != null)
          OutlinedButton(
            onPressed: () => ref.read(syncServerProvider.notifier).start(),
            child: const Text('Try again'),
          ),
      ],
    );
  }
}

class _Pairing extends ConsumerWidget {
  const _Pairing(this.payload);

  final PairingPayload payload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: QrImageView(
            data: payload.encode(),
            size: 200,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(width: 28),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Scan this code with your phone',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'In My Zik on your phone: Home → Sync → Scan the code. '
                'The code works once, for 10 minutes.',
                style: TextStyle(color: AppColors.whiteAlpha(0.65)),
              ),
              const SizedBox(height: 18),
              Text(
                'No camera? Enter by hand:',
                style: TextStyle(
                  color: AppColors.whiteAlpha(0.5),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 6),
              SelectableText(
                '${payload.hosts.isEmpty ? '?' : payload.hosts.first}'
                ' · port ${payload.port} · code ${payload.code}',
                style: DesktopText.mono.copyWith(fontSize: 15),
              ),
              const SizedBox(height: 18),
              TextButton(
                onPressed: () =>
                    ref.read(syncServerProvider.notifier).cancelPairing(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DeviceRow extends ConsumerWidget {
  const _DeviceRow(this.device);

  final PairedDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final last = device.lastSyncAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _Card(
        child: Row(
          children: [
            const Icon(AppIcons.phone, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    last == null
                        ? 'Paired ${_date(device.pairedAt)}, never synced'
                        : 'Last synced ${_date(last)}',
                    style: TextStyle(
                      color: AppColors.whiteAlpha(0.55),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: const Color(0xFF16161E),
                    title: Text('Unpair ${device.name}?'),
                    content: const Text(
                      'It will need to scan a new code to sync again.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Unpair'),
                      ),
                    ],
                  ),
                );
                if (confirmed ?? false) {
                  ref.read(syncServerProvider.notifier).revoke(device.id);
                }
              },
              child: const Text('Unpair'),
            ),
          ],
        ),
      ),
    );
  }

  static String _date(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)}';
  }
}
