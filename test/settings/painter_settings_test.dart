// What: Unit coverage for palette serialization, legacy keys, brightness
//   selection, malformed data, the loadStoredWorkspaces flag, and
//   preference-store round trips, including that every default used in
//   place of stored data is reported for the log (docs/spec/logging.md
//   LOG-13).
// Why: Saved custom themes must remain loadable while current themes omit the
//   removed canvas-paper role and retain independent light/dark palettes.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:painter/settings/painter_settings.dart';
import 'package:painter/settings/settings_store.dart';

void main() {
  group('PainterSettings', () {
    test('round-trips palettes and ignores the legacy paper color key', () {
      final light = PainterSettings.gruvboxLight.copyWith(
        id: 'custom-light',
        name: 'Custom Light',
        primary: 0xFF123456,
      );
      final dark = PainterSettings.gruvboxDark.copyWith(
        id: 'custom-dark',
        name: 'Custom Dark',
      );
      final settings = PainterSettings(
        mode: ThemeMode.dark,
        lightThemeId: light.id,
        darkThemeId: dark.id,
        customThemes: [light, dark],
      );
      final legacyTheme = {...dark.toJson(), 'canvasBackground': 0xFF112233};
      final stored = {
        ...settings.toJson(),
        'customThemes': [light.toJson(), legacyTheme],
      };

      final restored = PainterSettings.fromJson(stored);

      expect(restored.mode, ThemeMode.dark);
      expect(restored.themeFor(Brightness.light).primary, 0xFF123456);
      expect(restored.themeFor(Brightness.dark).name, 'Custom Dark');
      expect(
        restored.customThemes.last.toJson().containsKey('canvasBackground'),
        isFalse,
      );
    });

    test(
      'ignores malformed or built-in-shadowing themes and repairs selections, '
      'reporting each (LOG-13)',
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

        final problems = <String>[];
        final restored = PainterSettings.fromJson(
          data,
          onInvalid: problems.add,
        );

        expect(restored.mode, ThemeMode.system);
        expect(restored.themeFor(Brightness.light).id, 'gruvbox-light');
        expect(restored.themeFor(Brightness.dark).id, 'gruvbox-dark');
        expect(restored.customThemes.map((theme) => theme.id), [
          'custom-valid',
        ]);
        expect(problems, [
          'theme mode "unknown" is unknown',
          'skipped a custom theme: Theme ID and name are required.',
          'skipped custom theme "gruvbox-light": its id is already taken',
          '"missing" is not an available light theme',
          '"gruvbox-light" is not an available dark theme',
        ]);
      },
    );

    test('valid stored settings report nothing', () {
      final problems = <String>[];
      PainterSettings.fromJson(
        PainterSettings.defaults.toJson(),
        onInvalid: problems.add,
      );
      expect(problems, isEmpty);
    });

    test('loadStoredWorkspaces defaults to true and round-trips JSON', () {
      expect(PainterSettings.defaults.loadStoredWorkspaces, isTrue);

      final off = PainterSettings.defaults.copyWith(
        loadStoredWorkspaces: false,
      );
      expect(off.toJson()['loadStoredWorkspaces'], isFalse);
      expect(
        PainterSettings.fromJson(off.toJson()).loadStoredWorkspaces,
        isFalse,
      );
      expect(off.copyWith(mode: ThemeMode.dark).loadStoredWorkspaces, isFalse);
    });

    test('legacy and malformed loadStoredWorkspaces read as true', () {
      final legacy = Map<String, dynamic>.of(PainterSettings.defaults.toJson())
        ..remove('loadStoredWorkspaces');
      final malformed = {...legacy, 'loadStoredWorkspaces': 'no'};

      expect(PainterSettings.fromJson(legacy).loadStoredWorkspaces, isTrue);
      expect(PainterSettings.fromJson(malformed).loadStoredWorkspaces, isTrue);
    });

    test('controller toggles loadStoredWorkspaces and persists it', () async {
      final persisted = <PainterSettings>[];
      final controller = PainterSettingsController(
        persist: (settings) async => persisted.add(settings),
      );

      await controller.setLoadStoredWorkspaces(false);

      expect(controller.settings.loadStoredWorkspaces, isFalse);
      expect(persisted.single.loadStoredWorkspaces, isFalse);
    });

    test('builds Material and semantic status colors from the palette', () {
      final theme = PainterSettings.gruvboxLight.themeData;
      final colors = theme.extension<PainterThemeColors>()!;

      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.primary, const Color(0xFFAF3A03));
      expect(colors.success, const Color(0xFF79740E));
      expect(colors.warning, const Color(0xFFB57614));
    });
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

    test(
      'persists loadStoredWorkspaces and loads a legacy record as true',
      () async {
        final store = SharedPreferencesPainterSettingsStore();
        SharedPreferences.setMockInitialValues({});
        await store.save(
          PainterSettings.defaults.copyWith(loadStoredWorkspaces: false),
        );
        expect((await store.load()).loadStoredWorkspaces, isFalse);

        final legacy = Map<String, Object>.of(PainterSettings.defaults.toJson())
          ..remove('loadStoredWorkspaces');
        SharedPreferences.setMockInitialValues({
          'painter.settings.v1': jsonEncode(legacy),
        });
        expect((await store.load()).loadStoredWorkspaces, isTrue);
      },
    );

    test('falls back to defaults for malformed preference JSON, reporting '
        'it (LOG-13)', () async {
      SharedPreferences.setMockInitialValues({
        'painter.settings.v1': '{not json',
      });
      final store = SharedPreferencesPainterSettingsStore();
      final problems = <String>[];

      final loaded = await store.load(onInvalid: problems.add);
      expect(loaded.toJson(), PainterSettings.defaults.toJson());
      expect(problems.single, startsWith('the settings record is not JSON'));
    });
  });
}
