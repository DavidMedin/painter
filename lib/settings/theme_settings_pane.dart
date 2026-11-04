// What: The Settings pane's theme mode, light/dark palette selectors, and
//   custom palette editor.
// Why: Theme configuration belongs beside the selectable Canvas and Diagnostics
//   panes; it edits PainterSettings through the shared controller and leaves
//   persistence and app-wide ThemeData ownership to the app shell.
// Coupled to: painter_settings.dart (palette/controller), main.dart (pane host),
//   and contextual_help.dart (accessible settings controls).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../help/contextual_help.dart';
import '../ui/painter_action_button.dart';
import 'painter_settings.dart';

/// The sole Settings-pane section: application theme appearance.
class ThemeSettingsPane extends StatefulWidget {
  const ThemeSettingsPane({super.key, required this.controller});

  final PainterSettingsController controller;

  @override
  State<ThemeSettingsPane> createState() => _ThemeSettingsPaneState();
}

class _ThemeSettingsPaneState extends State<ThemeSettingsPane> {
  String? _notice;

  /// Saves an immutable settings change and leaves the selected value active if
  /// the backing preference service reports an error.
  Future<void> _save(PainterSettings settings) async {
    setState(() => _notice = null);
    try {
      await widget.controller.update(settings);
      if (mounted) setState(() => _notice = 'Settings saved');
    } catch (error) {
      if (mounted) setState(() => _notice = 'Could not save settings: $error');
    }
  }

  /// Opens the color editor and adds the completed custom palette to settings.
  Future<void> _createTheme(
    BuildContext context,
    Brightness brightness,
    PainterTheme base,
  ) async {
    final theme = await showDialog<PainterTheme>(
      context: context,
      builder: (context) =>
          _CustomThemeDialog(brightness: brightness, base: base),
    );
    if (theme == null || !mounted) return;
    final settings = widget.controller.settings;
    final updated = settings.copyWith(
      customThemes: [...settings.customThemes, theme],
      lightThemeId: brightness == Brightness.light
          ? theme.id
          : settings.lightThemeId,
      darkThemeId: brightness == Brightness.dark
          ? theme.id
          : settings.darkThemeId,
    );
    await _save(updated);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final settings = widget.controller.settings;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Theming',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Theme mode',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  HelpTarget(
                    topic: HelpIds.themeMode,
                    child: DropdownButtonFormField<ThemeMode>(
                      key: const ValueKey('theme-mode'),
                      initialValue: settings.mode,
                      decoration: const InputDecoration(labelText: 'Mode'),
                      items: const [
                        DropdownMenuItem(
                          value: ThemeMode.system,
                          child: Text('System'),
                        ),
                        DropdownMenuItem(
                          value: ThemeMode.light,
                          child: Text('Light'),
                        ),
                        DropdownMenuItem(
                          value: ThemeMode.dark,
                          child: Text('Dark'),
                        ),
                      ],
                      onChanged: (mode) {
                        if (mode != null) {
                          unawaited(_save(settings.copyWith(mode: mode)));
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  _themeSelector(
                    context,
                    brightness: Brightness.light,
                    label: 'Light theme',
                    selectedId: settings.lightThemeId,
                    themes: settings.themesFor(Brightness.light),
                    onSelected: (id) =>
                        _save(settings.copyWith(lightThemeId: id)),
                    onCreate: (base) =>
                        _createTheme(context, Brightness.light, base),
                  ),
                  const SizedBox(height: 16),
                  _themeSelector(
                    context,
                    brightness: Brightness.dark,
                    label: 'Dark theme',
                    selectedId: settings.darkThemeId,
                    themes: settings.themesFor(Brightness.dark),
                    onSelected: (id) =>
                        _save(settings.copyWith(darkThemeId: id)),
                    onCreate: (base) =>
                        _createTheme(context, Brightness.dark, base),
                  ),
                  if (_notice != null) ...[
                    const SizedBox(height: 12),
                    Text(_notice!, key: const ValueKey('settings-notice')),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Shows a brightness-specific built-in/custom theme selector and creator.
  Widget _themeSelector(
    BuildContext context, {
    required Brightness brightness,
    required String label,
    required String selectedId,
    required List<PainterTheme> themes,
    required ValueChanged<String> onSelected,
    required ValueChanged<PainterTheme> onCreate,
  }) {
    final selected = themes.firstWhere((theme) => theme.id == selectedId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: HelpTarget(
                topic: HelpIds.themePalette,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('theme-select-${brightness.name}'),
                  isExpanded: true,
                  initialValue: selectedId,
                  decoration: InputDecoration(labelText: label),
                  items: [
                    for (final theme in themes)
                      DropdownMenuItem(
                        value: theme.id,
                        child: Text(
                          theme.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (id) {
                    if (id != null) onSelected(id);
                  },
                ),
              ),
            ),
            const SizedBox(width: 10),
            PainterActionButton(
              icon: Icons.palette_outlined,
              label: 'Create theme',
              topic: HelpIds.createTheme,
              onPressed: () => onCreate(selected),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _ThemeSwatch(theme: selected),
      ],
    );
  }
}

/// A small preview of the selected palette's principal surface and accents.
class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.theme});

  final PainterTheme theme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color(theme.surface),
        border: Border.all(color: Color(theme.outline)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            for (final color in [
              theme.primary,
              theme.secondary,
              theme.success,
              theme.warning,
              theme.error,
            ]) ...[
              Container(
                width: 22,
                height: 22,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: Color(color),
                  shape: BoxShape.circle,
                ),
              ),
            ],
            Expanded(
              child: Text(
                theme.name,
                style: TextStyle(color: Color(theme.onSurface)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Edits every palette color role and returns a custom named theme.
class _CustomThemeDialog extends StatefulWidget {
  const _CustomThemeDialog({required this.brightness, required this.base});

  final Brightness brightness;
  final PainterTheme base;

  @override
  State<_CustomThemeDialog> createState() => _CustomThemeDialogState();
}

class _CustomThemeDialogState extends State<_CustomThemeDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: '${widget.base.name} Custom',
  );
  late final Map<String, TextEditingController> _colors = {
    for (final entry in _colorValues(widget.base).entries)
      entry.key: TextEditingController(text: _hex(entry.value)),
  };

  static const _colorLabels = <String, String>{
    'primary': 'Primary',
    'onPrimary': 'Text on primary',
    'secondary': 'Secondary',
    'onSecondary': 'Text on secondary',
    'surface': 'Surface',
    'surfaceVariant': 'Raised surface',
    'onSurface': 'Main text',
    'mutedText': 'Secondary text',
    'outline': 'Borders',
    'error': 'Error',
    'onError': 'Text on error',
    'success': 'Success status',
    'warning': 'Warning status',
    'info': 'Information accent',
  };

  static Map<String, int> _colorValues(PainterTheme theme) => {
    'primary': theme.primary,
    'onPrimary': theme.onPrimary,
    'secondary': theme.secondary,
    'onSecondary': theme.onSecondary,
    'surface': theme.surface,
    'surfaceVariant': theme.surfaceVariant,
    'onSurface': theme.onSurface,
    'mutedText': theme.mutedText,
    'outline': theme.outline,
    'error': theme.error,
    'onError': theme.onError,
    'success': theme.success,
    'warning': theme.warning,
    'info': theme.info,
  };

  @override
  void dispose() {
    _name.dispose();
    for (final controller in _colors.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Parses and validates all color fields before closing the editor.
  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final values = {
      for (final entry in _colors.entries)
        entry.key:
            int.parse(entry.value.text.replaceFirst('#', ''), radix: 16) |
            0xFF000000,
    };
    final id = 'custom-${DateTime.now().microsecondsSinceEpoch}';
    Navigator.of(context).pop(
      widget.base.copyWith(
        id: id,
        name: _name.text.trim(),
        brightness: widget.brightness,
        primary: values['primary'],
        onPrimary: values['onPrimary'],
        secondary: values['secondary'],
        onSecondary: values['onSecondary'],
        surface: values['surface'],
        surfaceVariant: values['surfaceVariant'],
        onSurface: values['onSurface'],
        mutedText: values['mutedText'],
        outline: values['outline'],
        error: values['error'],
        onError: values['onError'],
        success: values['success'],
        warning: values['warning'],
        info: values['info'],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text('Create ${widget.brightness.name} theme'),
      content: SizedBox(
        width: 540,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                HelpTarget(
                  topic: HelpIds.createTheme,
                  child: TextFormField(
                    key: const ValueKey('custom-theme-name'),
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Theme name'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter a theme name.'
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                for (final entry in _colorLabels.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: HelpTarget(
                      topic: HelpIds.themeColor,
                      child: TextFormField(
                        key: ValueKey('theme-color-${entry.key}'),
                        controller: _colors[entry.key],
                        decoration: InputDecoration(
                          labelText: entry.value,
                          prefixIcon: Padding(
                            padding: const EdgeInsets.all(12),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: _previewColor(entry.key),
                                shape: BoxShape.circle,
                                border: Border.all(color: colors.outline),
                              ),
                            ),
                          ),
                        ),
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          return RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(text)
                              ? null
                              : 'Enter a 6-digit hex color, such as #D65D0E.';
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        HelpTarget(
          topic: HelpIds.dialogClose,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ),
        HelpTarget(
          topic: HelpIds.createTheme,
          child: FilledButton(
            key: const ValueKey('save-custom-theme'),
            onPressed: _save,
            child: const Text('Save theme'),
          ),
        ),
      ],
    );
  }

  Color _previewColor(String key) {
    final value = _colors[key]!.text.replaceFirst('#', '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(value)) {
      return Theme.of(context).colorScheme.surfaceContainerHighest;
    }
    return Color(0xFF000000 | int.parse(value, radix: 16));
  }

  static String _hex(int color) =>
      '#${color.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
}

/// Previews the theme controls with an in-memory settings controller.
@Preview(
  name: 'Theme settings',
  group: 'Painter settings',
  size: Size(760, 720),
)
Widget themeSettingsPanePreview() {
  final settings = PainterSettings.defaults;
  return MaterialApp(
    theme: settings.themeFor(Brightness.light).themeData,
    darkTheme: settings.themeFor(Brightness.dark).themeData,
    home: Scaffold(
      body: ThemeSettingsPane(controller: PainterSettingsController()),
    ),
  );
}
