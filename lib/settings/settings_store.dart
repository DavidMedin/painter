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
  /// [onInvalid] is told about each part replaced by a default
  /// (docs/spec/logging.md LOG-13; see PainterSettings.fromJson).
  Future<PainterSettings> load({
    void Function(String problem)? onInvalid,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(_key);
    if (stored == null) return PainterSettings.defaults;
    final Object? json;
    try {
      json = jsonDecode(stored);
    } on FormatException catch (error) {
      onInvalid?.call('the settings record is not JSON: ${error.message}');
      return PainterSettings.defaults;
    }
    return PainterSettings.fromJson(json, onInvalid: onInvalid);
  }

  /// Replaces the stored settings record atomically at the preference level.
  Future<void> save(PainterSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, jsonEncode(settings.toJson()));
  }
}
