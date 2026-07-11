import 'package:flutter/material.dart';
import 'package:flutter_iconly/flutter_iconly.dart';

import '../player_controller.dart';
import '../theme.dart';
import '../widgets.dart';

/// The "Settings" screen: profile card + grouped preference rows.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});

  final PlayerController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notifications = true;
  bool _wifiOnly = false;
  bool _crossfade = true;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.musicBackground),
      child: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GlassIconButton(
                        icon: IconlyLight.arrowLeft2,
                        size: 44,
                        iconSize: 22,
                        onTap: () => c.goTo(AppScreen.home),
                      ),
                      const Text(
                        'Settings',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 44),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 120),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      _profile(),
                      const SizedBox(height: 28),
                      _sectionLabel('Account'),
                      const SizedBox(height: 12),
                      _card([
                        _navRow(IconlyLight.profile, 'Edit profile'),
                        _divider(),
                        _switchRow(
                          IconlyLight.notification,
                          'Notifications',
                          _notifications,
                          (v) => setState(() => _notifications = v),
                        ),
                        _divider(),
                        _navRow(IconlyLight.shieldDone, 'Privacy'),
                      ]),
                      const SizedBox(height: 24),
                      _sectionLabel('Playback'),
                      const SizedBox(height: 12),
                      _card([
                        _navRow(
                          IconlyLight.voice,
                          'Audio quality',
                          trailing: 'High',
                        ),
                        _divider(),
                        _switchRow(
                          IconlyLight.download,
                          'Download over Wi-Fi only',
                          _wifiOnly,
                          (v) => setState(() => _wifiOnly = v),
                        ),
                        _divider(),
                        _switchRow(
                          IconlyLight.swap,
                          'Crossfade',
                          _crossfade,
                          (v) => setState(() => _crossfade = v),
                        ),
                      ]),
                      const SizedBox(height: 24),
                      _sectionLabel('About'),
                      const SizedBox(height: 12),
                      _card([
                        _navRow(IconlyLight.infoSquare, 'Help & support'),
                        _divider(),
                        _navRow(IconlyLight.document, 'About MyZik'),
                        _divider(),
                        _navRow(IconlyLight.logout, 'Log out', danger: true),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 22,
            right: 22,
            bottom: 0,
            child: FloatingNavBar(controller: c),
          ),
        ],
      ),
    );
  }

  Widget _profile() {
    return Row(
      children: [
        const CircleAvatar(
          radius: 32,
          backgroundColor: Color(0xFF1A1730),
          backgroundImage: AssetImage('assets/images/avatar.png'),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Fehizoro',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Premium · fehizoro@myzik.app',
                style: TextStyle(
                  color: AppColors.whiteAlpha(0.55),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const GlassIconButton(icon: IconlyLight.edit, size: 44),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: AppColors.whiteAlpha(0.4),
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.whiteAlpha(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.whiteAlpha(0.08)),
      ),
      child: Column(children: children),
    );
  }

  Widget _divider() {
    return Padding(
      padding: const EdgeInsets.only(left: 60),
      child: Divider(
        height: 1,
        thickness: 1,
        color: AppColors.whiteAlpha(0.06),
      ),
    );
  }

  Widget _rowLeading(IconData icon, String title, {bool danger = false}) {
    final color = danger ? const Color(0xFFFF6F7A) : AppColors.white;
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(width: 16),
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _navRow(
    IconData icon,
    String title, {
    String? trailing,
    bool danger = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          _rowLeading(icon, title, danger: danger),
          if (trailing != null)
            Text(
              trailing,
              style: TextStyle(
                color: AppColors.whiteAlpha(0.5),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (!danger) ...[
            const SizedBox(width: 8),
            Icon(
              IconlyLight.arrowRight2,
              size: 18,
              color: AppColors.whiteAlpha(0.35),
            ),
          ],
        ],
      ),
    );
  }

  Widget _switchRow(
    IconData icon,
    String title,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: Row(
        children: [
          _rowLeading(icon, title),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.accentA,
          ),
        ],
      ),
    );
  }
}
