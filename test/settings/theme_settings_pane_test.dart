// What: Widget tests for the Settings pane's theme-mode selection and custom
//   palette creation flow.
// Why: Theme preferences are visible app behavior; changing a selector or saving
//   an edited palette must update the shared settings model and persistence.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:painter/settings/painter_settings.dart';
import 'package:painter/settings/theme_settings_pane.dart';

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
}
