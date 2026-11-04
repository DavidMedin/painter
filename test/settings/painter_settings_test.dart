// What: Unit coverage for theme palette serialization, brightness selection,
//   malformed saved data, theme construction, and preference-store round trips.
// Why: Settings survive app restarts and must retain independent light/dark
//   palettes without allowing malformed or stale records to break startup.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:painter/settings/painter_settings.dart';
import 'package:painter/settings/settings_store.dart';

void main() {
  group('PainterSettings', () {
    test('round-trips independent selected light and dark custom palettes', () {
      final light = PainterSettings.gruvboxLight.copyWith(
        id: 'custom-light',
        name: 'Custom Light',
        primary: 0xFF123456,
      );
      final dark = PainterSettings.gruvboxDark.copyWith(
        id: 'custom-dark',
        name: 'Custom Dark',
        canvasBackground: 0xFF112233,
      );
      final settings = PainterSettings(
        mode: ThemeMode.dark,
        lightThemeId: light.id,
        darkThemeId: dark.id,
        customThemes: [light, dark],
      );

      final restored = PainterSettings.fromJson(settings.toJson());

      expect(restored.mode, ThemeMode.dark);
      expect(restored.themeFor(Brightness.light).primary, 0xFF123456);
      expect(restored.themeFor(Brightness.dark).canvasBackground, 0xFF112233);
      expect(restored.customThemes.map((theme) => theme.id), [
        'custom-light',
        'custom-dark',
      ]);
    });

    test(
      'ignores malformed or built-in-shadowing themes and repairs selections',
      () {
        final valid = PainterSettings.gruvboxLight.copyWith(
          id: 'custom-valid',
          name: 'Valid',
        );
        final data = PainterSettings.defaults.toJson()
          ..['mode'] = 'unknown'
          ..['lightThemeId'] = 'missing'
          ..['darkThemeId'] = PainterSettings.gruvboxLight.id
          ..['customThemes'] = [
            valid.toJson(),
            {'id': 'incomplete'},
            PainterSettings.gruvboxLight.toJson(),
          ];

        final restored = PainterSettings.fromJson(data);

        expect(restored.mode, ThemeMode.system);
        expect(restored.themeFor(Brightness.light).id, 'gruvbox-light');
        expect(restored.themeFor(Brightness.dark).id, 'gruvbox-dark');
        expect(restored.customThemes.map((theme) => theme.id), [
          'custom-valid',
        ]);
      },
    );

    test(
      'builds Material colors and semantic canvas colors from the palette',
      () {
        final theme = PainterSettings.gruvboxLight.themeData;
        final colors = theme.extension<PainterThemeColors>()!;

        expect(theme.brightness, Brightness.light);
        expect(theme.colorScheme.primary, const Color(0xFFAF3A03));
        expect(colors.canvasBackground, const Color(0xFFFBF1C7));
        expect(colors.success, const Color(0xFF79740E));
      },
    );
  });

  group('SharedPreferencesPainterSettingsStore', () {
    test('persists and restores settings including custom palettes', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPreferencesPainterSettingsStore();
      final custom = PainterSettings.gruvboxDark.copyWith(
        id: 'saved-dark',
        name: 'Saved Dark',
      );
      final settings = PainterSettings(
        mode: ThemeMode.light,
        lightThemeId: PainterSettings.gruvboxLight.id,
        darkThemeId: custom.id,
        customThemes: [custom],
      );

      await store.save(settings);

      expect((await store.load()).toJson(), settings.toJson());
    });

    test('falls back to defaults for malformed preference JSON', () async {
      SharedPreferences.setMockInitialValues({
        'painter.settings.v1': '{not json',
      });
      final store = SharedPreferencesPainterSettingsStore();

      expect((await store.load()).toJson(), PainterSettings.defaults.toJson());
    });
  });
}
