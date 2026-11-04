// What: Widget tests cover theme selection, custom palettes, and the app route
//   into Settings through the Pane Mode selector.
// Why: Both the settings pane and its integration into the pane workspace must
//   update the visible app behavior and persistent settings model.
// Coupled to: main.dart, settings/painter_settings.dart,
//   settings/theme_settings_pane.dart, and ui/pane_system.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:painter/settings/painter_settings.dart';
import 'package:painter/settings/theme_settings_pane.dart';
import 'package:painter/main.dart';

/// Builds the Settings pane under the same paired themes used by the app shell.
Future<void> _pumpSettingsPane(
  WidgetTester tester,
  PainterSettingsController controller,
) async {
  final settings = controller.settings;
  await tester.pumpWidget(
    MaterialApp(
      theme: settings.themeFor(Brightness.light).themeData,
      darkTheme: settings.themeFor(Brightness.dark).themeData,
      home: Scaffold(body: ThemeSettingsPane(controller: controller)),
    ),
  );
}

void main() {
  testWidgets('long theme names fit in a narrow Settings pane', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final theme = PainterSettings.gruvboxLight.copyWith(
      id: 'custom-long-name',
      name:
          'CopperPaletteCustomNameThatIsMuchTooLongToFitInTheSettingsDropdown',
    );
    final settings = PainterSettings.defaults.copyWith(
      lightThemeId: theme.id,
      customThemes: [theme],
    );
    await _pumpSettingsPane(
      tester,
      PainterSettingsController(initial: settings),
    );

    final selector = find.byKey(const ValueKey('theme-select-light'));
    expect(
      tester.getSize(find.text(theme.name).first).width,
      lessThanOrEqualTo(tester.getSize(selector).width),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing theme mode updates and persists settings', (
    tester,
  ) async {
    final persisted = <PainterSettings>[];
    final controller = PainterSettingsController(
      persist: (settings) async => persisted.add(settings),
    );
    await _pumpSettingsPane(tester, controller);

    await tester.tap(find.byKey(const ValueKey('theme-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Light').last);
    await tester.pumpAndSettle();

    expect(controller.settings.mode, ThemeMode.light);
    expect(persisted, hasLength(1));
    expect(persisted.single.mode, ThemeMode.light);
  });

  testWidgets('creates a selected custom palette with edited colors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = PainterSettingsController();
    await _pumpSettingsPane(tester, controller);

    await tester.tap(find.text('Create theme').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('custom-theme-name')),
      'Copper Light',
    );
    await tester.enterText(
      find.byKey(const ValueKey('theme-color-primary')),
      '#123456',
    );
    await tester.tap(find.byKey(const ValueKey('save-custom-theme')));
    await tester.pumpAndSettle();

    final selected = controller.settings.themeFor(Brightness.light);
    expect(selected.id, startsWith('custom-'));
    expect(selected.name, 'Copper Light');
    expect(selected.primary, 0xFF123456);
    expect(controller.settings.customThemes, contains(selected));
    expect(find.text('Settings saved'), findsOneWidget);
  });

  testWidgets('PainterApp opens the Settings pane from Pane Mode', (
    tester,
  ) async {
    await tester.pumpWidget(const PainterApp());
    await tester.tap(find.byKey(const ValueKey('pane-mode-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('theme-mode')), findsOneWidget);
    expect(find.text('Theme mode'), findsOneWidget);
  });
}
