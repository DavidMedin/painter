// What: Immutable theme definitions, app settings, theme construction, and the
//   ChangeNotifier that applies and persists setting changes through a callback.
// Why: Theme choice is app-wide state, separate from canvas/document state; the
//   app shell, settings pane, canvas painter, and settings store share this
//   model without depending on one another's UI or persistence details.
//
// ---------------------------------------------------------------------------
// Theme system overview
//
// PainterTheme stores user-editable application color roles and brightness for
// one named palette. Its ThemeData maps those roles into Material 3's ColorScheme;
// PainterThemeColors carries diagnostic status colors that Material does not
// define. Canvas paper is fixed by CanvasView and independent from app theme.
// Gruvbox Light and Gruvbox Dark are built-in and cannot be overwritten.
// PainterSettings stores system/light/dark mode, selected palette IDs, and saved
// custom palettes. Settings are serialized by settings_store.dart, while
// PainterSettingsController notifies the app shell and invokes its persistence
// callback.
//
// The app shell supplies the two selected ThemeData values to MaterialApp and lets
// Flutter resolve system brightness. The settings pane edits the same immutable
// settings object; custom color input is saved before its ID becomes selected.
// Canvas paper stays white when app theme changes; diagnostic overlays use
// PainterThemeColors and non-paint UI uses ColorScheme.
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';

/// One named, brightness-specific user interface palette.
@immutable
class PainterTheme {
  const PainterTheme({
    required this.id,
    required this.name,
    required this.brightness,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.onSecondary,
    required this.surface,
    required this.surfaceVariant,
    required this.onSurface,
    required this.mutedText,
    required this.outline,
    required this.error,
    required this.onError,
    required this.success,
    required this.warning,
    required this.info,
  });

  final String id;
  final String name;
  final Brightness brightness;
  final int primary;
  final int onPrimary;
  final int secondary;
  final int onSecondary;
  final int surface;
  final int surfaceVariant;
  final int onSurface;
  final int mutedText;
  final int outline;
  final int error;
  final int onError;
  final int success;
  final int warning;
  final int info;

  /// Builds the Material theme and Painter-specific semantic colors.
  ThemeData get themeData {
    final primaryColor = Color(primary);
    final secondaryColor = Color(secondary);
    final surfaceColor = Color(surface);
    final surfaceVariantColor = Color(surfaceVariant);
    final onSurfaceColor = Color(onSurface);
    final mutedTextColor = Color(mutedText);
    final outlineColor = Color(outline);
    final errorColor = Color(error);
    final infoColor = Color(info);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: primaryColor,
          brightness: brightness,
          surface: surfaceColor,
        ).copyWith(
          primary: primaryColor,
          onPrimary: Color(onPrimary),
          secondary: secondaryColor,
          onSecondary: Color(onSecondary),
          tertiary: infoColor,
          onTertiary: onSurfaceColor,
          surface: surfaceColor,
          onSurface: onSurfaceColor,
          surfaceContainerHighest: surfaceVariantColor,
          onSurfaceVariant: mutedTextColor,
          outline: outlineColor,
          outlineVariant: outlineColor,
          error: errorColor,
          onError: Color(onError),
          surfaceTint: primaryColor,
        );
    return ThemeData.from(colorScheme: scheme, useMaterial3: true).copyWith(
      scaffoldBackgroundColor: surfaceColor,
      dividerColor: outlineColor,
      extensions: [
        PainterThemeColors(
          success: Color(success),
          warning: Color(warning),
          info: infoColor,
        ),
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceColor,
        foregroundColor: onSurfaceColor,
        surfaceTintColor: surfaceColor,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceVariantColor,
        border: OutlineInputBorder(borderSide: BorderSide(color: outlineColor)),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: outlineColor),
        ),
      ),
    );
  }

  /// Copies this palette while preserving unedited color roles.
  PainterTheme copyWith({
    String? id,
    String? name,
    Brightness? brightness,
    int? primary,
    int? onPrimary,
    int? secondary,
    int? onSecondary,
    int? surface,
    int? surfaceVariant,
    int? onSurface,
    int? mutedText,
    int? outline,
    int? error,
    int? onError,
    int? success,
    int? warning,
    int? info,
  }) => PainterTheme(
    id: id ?? this.id,
    name: name ?? this.name,
    brightness: brightness ?? this.brightness,
    primary: primary ?? this.primary,
    onPrimary: onPrimary ?? this.onPrimary,
    secondary: secondary ?? this.secondary,
    onSecondary: onSecondary ?? this.onSecondary,
    surface: surface ?? this.surface,
    surfaceVariant: surfaceVariant ?? this.surfaceVariant,
    onSurface: onSurface ?? this.onSurface,
    mutedText: mutedText ?? this.mutedText,
    outline: outline ?? this.outline,
    error: error ?? this.error,
    onError: onError ?? this.onError,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    info: info ?? this.info,
  );

  /// Converts the palette to JSON using integer ARGB color values.
  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'brightness': brightness.name,
    'primary': primary,
    'onPrimary': onPrimary,
    'secondary': secondary,
    'onSecondary': onSecondary,
    'surface': surface,
    'surfaceVariant': surfaceVariant,
    'onSurface': onSurface,
    'mutedText': mutedText,
    'outline': outline,
    'error': error,
    'onError': onError,
    'success': success,
    'warning': warning,
    'info': info,
  };

  /// Reads a stored custom palette, rejecting incomplete or invalid records.
  factory PainterTheme.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Theme must be a JSON object.');
    }
    final map = value;
    int color(String name) {
      final colorValue = map[name];
      if (colorValue is! int || colorValue < 0 || colorValue > 0xFFFFFFFF) {
        throw FormatException('Theme color "$name" is invalid.');
      }
      return colorValue;
    }

    final id = map['id'];
    final name = map['name'];
    final brightnessName = map['brightness'];
    if (id is! String || id.isEmpty || name is! String || name.trim().isEmpty) {
      throw const FormatException('Theme ID and name are required.');
    }
    final brightness = switch (brightnessName) {
      'light' => Brightness.light,
      'dark' => Brightness.dark,
      _ => throw const FormatException('Theme brightness is invalid.'),
    };
    return PainterTheme(
      id: id,
      name: name,
      brightness: brightness,
      primary: color('primary'),
      onPrimary: color('onPrimary'),
      secondary: color('secondary'),
      onSecondary: color('onSecondary'),
      surface: color('surface'),
      surfaceVariant: color('surfaceVariant'),
      onSurface: color('onSurface'),
      mutedText: color('mutedText'),
      outline: color('outline'),
      error: color('error'),
      onError: color('onError'),
      success: color('success'),
      warning: color('warning'),
      info: color('info'),
    );
  }
}

/// Painter-specific status colors that Material's [ColorScheme] does not define.
@immutable
class PainterThemeColors extends ThemeExtension<PainterThemeColors> {
  const PainterThemeColors({
    required this.success,
    required this.warning,
    required this.info,
  });

  /// Provides semantic colors for embedders using a plain Material ColorScheme.
  static PainterThemeColors fromColorScheme(ColorScheme scheme) =>
      PainterThemeColors(
        success: scheme.primary,
        warning: scheme.tertiary,
        info: scheme.secondary,
      );

  final Color success;
  final Color warning;
  final Color info;

  @override
  PainterThemeColors copyWith({Color? success, Color? warning, Color? info}) =>
      PainterThemeColors(
        success: success ?? this.success,
        warning: warning ?? this.warning,
        info: info ?? this.info,
      );

  @override
  PainterThemeColors lerp(
    covariant ThemeExtension<PainterThemeColors>? other,
    double t,
  ) {
    if (other is! PainterThemeColors) return this;
    return PainterThemeColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
    );
  }
}

/// User settings that are independent of the current document.
@immutable
class PainterSettings {
  const PainterSettings({
    required this.mode,
    required this.lightThemeId,
    required this.darkThemeId,
    this.customThemes = const [],
  });

  static const gruvboxLight = PainterTheme(
    id: 'gruvbox-light',
    name: 'Gruvbox Light',
    brightness: Brightness.light,
    primary: 0xFFAF3A03,
    onPrimary: 0xFFFBF1C7,
    secondary: 0xFF076678,
    onSecondary: 0xFFFBF1C7,
    surface: 0xFFFBF1C7,
    surfaceVariant: 0xFFEBDBB2,
    onSurface: 0xFF3C3836,
    mutedText: 0xFF7C6F64,
    outline: 0xFFA89984,
    error: 0xFF9D0006,
    onError: 0xFFFBF1C7,
    success: 0xFF79740E,
    warning: 0xFFB57614,
    info: 0xFF458588,
  );

  static const gruvboxDark = PainterTheme(
    id: 'gruvbox-dark',
    name: 'Gruvbox Dark',
    brightness: Brightness.dark,
    primary: 0xFFFE8019,
    onPrimary: 0xFF282828,
    secondary: 0xFF458588,
    onSecondary: 0xFF282828,
    surface: 0xFF282828,
    surfaceVariant: 0xFF3C3836,
    onSurface: 0xFFEBDBB2,
    mutedText: 0xFFA89984,
    outline: 0xFF665C54,
    error: 0xFFFB4934,
    onError: 0xFF282828,
    success: 0xFFB8BB26,
    warning: 0xFFFABD2F,
    info: 0xFF83A598,
  );

  static const List<PainterTheme> builtInThemes = [gruvboxLight, gruvboxDark];

  static const PainterSettings defaults = PainterSettings(
    mode: ThemeMode.system,
    lightThemeId: 'gruvbox-light',
    darkThemeId: 'gruvbox-dark',
  );

  final ThemeMode mode;
  final String lightThemeId;
  final String darkThemeId;
  final List<PainterTheme> customThemes;

  /// Resolves the selected theme for the requested brightness.
  PainterTheme themeFor(Brightness brightness) {
    final id = brightness == Brightness.light ? lightThemeId : darkThemeId;
    for (final theme in builtInThemes) {
      if (theme.id == id && theme.brightness == brightness) return theme;
    }
    for (final theme in customThemes) {
      if (theme.id == id && theme.brightness == brightness) return theme;
    }
    return brightness == Brightness.light ? gruvboxLight : gruvboxDark;
  }

  /// Returns built-in and custom themes usable at [brightness].
  List<PainterTheme> themesFor(Brightness brightness) => [
    for (final theme in builtInThemes)
      if (theme.brightness == brightness) theme,
    for (final theme in customThemes)
      if (theme.brightness == brightness) theme,
  ];

  /// Copies settings, retaining values whose arguments are omitted.
  PainterSettings copyWith({
    ThemeMode? mode,
    String? lightThemeId,
    String? darkThemeId,
    List<PainterTheme>? customThemes,
  }) => PainterSettings(
    mode: mode ?? this.mode,
    lightThemeId: lightThemeId ?? this.lightThemeId,
    darkThemeId: darkThemeId ?? this.darkThemeId,
    customThemes: customThemes ?? this.customThemes,
  );

  /// Converts app settings to JSON-compatible data.
  Map<String, Object> toJson() => {
    'mode': mode.name,
    'lightThemeId': lightThemeId,
    'darkThemeId': darkThemeId,
    'customThemes': customThemes.map((theme) => theme.toJson()).toList(),
  };

  /// Restores preferences and custom themes, defaulting malformed records.
  factory PainterSettings.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return defaults;
    final mode = switch (value['mode']) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    final customThemes = <PainterTheme>[];
    final storedThemes = value['customThemes'];
    if (storedThemes is List) {
      for (final stored in storedThemes) {
        try {
          final theme = PainterTheme.fromJson(stored);
          if (!builtInThemes.any((builtIn) => builtIn.id == theme.id) &&
              !customThemes.any((existing) => existing.id == theme.id)) {
            customThemes.add(theme);
          }
        } on FormatException {
          // Skip an invalid custom theme without discarding other settings.
        }
      }
    }
    final settings = PainterSettings(
      mode: mode,
      lightThemeId: value['lightThemeId'] is String
          ? value['lightThemeId'] as String
          : defaults.lightThemeId,
      darkThemeId: value['darkThemeId'] is String
          ? value['darkThemeId'] as String
          : defaults.darkThemeId,
      customThemes: List.unmodifiable(customThemes),
    );
    return settings.copyWith(
      lightThemeId: settings.themeFor(Brightness.light).id,
      darkThemeId: settings.themeFor(Brightness.dark).id,
    );
  }
}

/// Applies app settings immediately and invokes the persistence callback.
class PainterSettingsController extends ChangeNotifier {
  PainterSettingsController({
    PainterSettings initial = PainterSettings.defaults,
    this.persist,
  }) : _settings = initial;

  PainterSettings _settings;
  final Future<void> Function(PainterSettings settings)? persist;

  PainterSettings get settings => _settings;

  /// Notifies theme consumers before awaiting the preference write.
  Future<void> update(PainterSettings settings) async {
    _settings = settings;
    notifyListeners();
    await persist?.call(settings);
  }
}
