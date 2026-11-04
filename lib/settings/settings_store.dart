// What: SharedPreferences-backed persistence for app theme settings.
// Why: PainterSettings stays independent of plugins and serialization I/O;
//   main.dart loads this store before the first frame and injects its save
//   callback into PainterSettingsController.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'painter_settings.dart';

/// Reads and writes the complete app settings record as one JSON preference.
class SharedPreferencesPainterSettingsStore {
  static const _key = 'painter.settings.v1';

  /// Loads saved settings, or built-in defaults when no valid record exists.
  Future<PainterSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(_key);
    if (stored == null) return PainterSettings.defaults;
    try {
      return PainterSettings.fromJson(jsonDecode(stored));
    } on FormatException {
      return PainterSettings.defaults;
    }
  }

  /// Replaces the stored settings record atomically at the preference level.
  Future<void> save(PainterSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, jsonEncode(settings.toJson()));
  }
}
