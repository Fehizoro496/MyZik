import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shared_preferences_provider.dart';

const _kNotifications = 'settings.notifications';
const _kWifiOnly = 'settings.wifiOnly';
const _kCrossfade = 'settings.crossfade';

class SettingsState {
  const SettingsState({
    required this.notifications,
    required this.wifiOnly,
    required this.crossfade,
  });

  final bool notifications;
  final bool wifiOnly;
  final bool crossfade;

  SettingsState copyWith({
    bool? notifications,
    bool? wifiOnly,
    bool? crossfade,
  }) {
    return SettingsState(
      notifications: notifications ?? this.notifications,
      wifiOnly: wifiOnly ?? this.wifiOnly,
      crossfade: crossfade ?? this.crossfade,
    );
  }
}

/// User preference toggles. Persisted to [SharedPreferences] so they survive
/// an app restart — previously these lived in the Settings screen's local
/// widget state and were silently lost on every navigation away from it.
class SettingsNotifier extends Notifier<SettingsState> {
  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  SettingsState build() {
    return SettingsState(
      notifications: _prefs.getBool(_kNotifications) ?? true,
      wifiOnly: _prefs.getBool(_kWifiOnly) ?? false,
      crossfade: _prefs.getBool(_kCrossfade) ?? true,
    );
  }

  void setNotifications(bool value) {
    state = state.copyWith(notifications: value);
    _prefs.setBool(_kNotifications, value);
  }

  void setWifiOnly(bool value) {
    state = state.copyWith(wifiOnly: value);
    _prefs.setBool(_kWifiOnly, value);
  }

  void setCrossfade(bool value) {
    state = state.copyWith(crossfade: value);
    _prefs.setBool(_kCrossfade, value);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);
