import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:encrypt_shared_preferences/provider.dart';

/// Light theme color scheme for the application
ColorScheme? colorSchemeLight;

/// Dark theme color scheme for the application
ColorScheme? colorSchemeDark;

const Set<String> _supportedBrightnessValues = {
  'system',
  'light',
  'dark',
  'oled',
};

/// Resets the system navigation bar and status bar appearance
/// Parameters:
///   - context: The build context
///   - prefs: Encrypted shared preferences instance
///   - color: Optional base color for the system UI
///   - statusBarColor: Optional specific color for the status bar
///   - systemNavigationBarColor: Optional specific color for the navigation bar
///   - delay: Optional delay before applying the changes
Future<void> resetSystemNavigation(
  BuildContext context,
  EncryptedSharedPreferencesAsync prefs, {
  Color? color,
  Color? statusBarColor,
  Color? systemNavigationBarColor,
  Duration? delay,
}) async {
  final platformBrightness = MediaQuery.platformBrightnessOf(context);
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (delay != null) {
      await Future.delayed(delay);
    }
    final currentTheme = await themeCurrent(
      prefs,
      platformBrightness: platformBrightness,
    );
    color ??= currentTheme.colorScheme.surface;
    bool colorsEqual(Color a, Color b) {
      return a.r == b.r && a.g == b.g && a.b == b.b && a.a == b.a;
    }

    Color effectiveStatusColor =
        (statusBarColor != null) ? statusBarColor : color!;
    bool shouldBeTransparent = !kIsWeb &&
        colorsEqual(effectiveStatusColor,
            currentTheme.colorScheme.surface); // Use awaited theme
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarIconBrightness:
            (effectiveStatusColor.computeLuminance() > 0.179)
                ? Brightness.dark
                : Brightness.light,
        statusBarColor:
            shouldBeTransparent ? Colors.transparent : effectiveStatusColor,
        systemNavigationBarColor: (systemNavigationBarColor != null)
            ? systemNavigationBarColor
            : color,
      ),
    );
  });
}

/// Modifies the base theme with custom transition animations and button styling
/// Parameters:
///   - theme: The base theme to modify
/// Returns:
///   Modified ThemeData with custom page transitions and button colors
ThemeData themeModifier(ThemeData theme) {
  return theme.copyWith(
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder()
      },
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
    ),
  );
}

/// Gets the current theme based on system settings and user preferences
/// Parameters:
///   - prefs: Encrypted shared preferences instance
///   - platformBrightness: Current platform brightness
/// Returns:
///   The appropriate ThemeData based on current settings
Future<ThemeData> themeCurrent(
  EncryptedSharedPreferencesAsync prefs, {
  required Brightness platformBrightness,
}) async {
  final brightnessValue = await themeBrightnessPreference(prefs);
  if (brightnessValue == 'system') {
    if (platformBrightness == Brightness.light) {
      return await themeLight(prefs); // Await themeLight
    } else {
      return await themeDark(prefs); // Await themeDark
    }
  }
  if (brightnessValue == 'light') {
    return await themeLight(prefs);
  }
  if (brightnessValue == 'oled') {
    return await themeOled(prefs);
  }
  return await themeDark(prefs);
}

/// Gets the light theme configuration
/// Parameters:
///   - prefs: Encrypted shared preferences instance
/// Returns:
///   Light theme configuration with appropriate color scheme
Future<ThemeData> themeLight(EncryptedSharedPreferencesAsync prefs) async {
  final secondaryColorInt =
      await prefs.getInt('pref_secondary_color', defaultValue: 0xFF2196F3);
  final secondaryColor = Color(secondaryColorInt!);

  // Await getBool and provide default value, add null assertion
  if (!(await prefs.getBool("useDeviceTheme", defaultValue: false))! ||
      colorSchemeLight == null) {
    return themeModifier(
      ThemeData.from(
        colorScheme: ColorScheme(
          brightness: Brightness.light,
          primary: secondaryColor,
          onPrimary: Colors.white,
          secondary: secondaryColor,
          onSecondary: Colors.black,
          error: Colors.red,
          onError: Colors.white,
          surface: Colors.white,
          onSurface: Colors.black,
        ),
      ),
    );
  } else {
    return themeModifier(ThemeData.from(colorScheme: colorSchemeLight!));
  }
}

/// Gets the dark theme configuration
/// Parameters:
///   - prefs: Encrypted shared preferences instance
/// Returns:
///   Dark theme configuration with appropriate color scheme
Future<ThemeData> themeDark(EncryptedSharedPreferencesAsync prefs) async {
  final secondaryColorInt =
      await prefs.getInt('pref_secondary_color', defaultValue: 0xFF2196F3);
  final secondaryColor = Color(secondaryColorInt!);

  final ColorScheme darkGrayScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: secondaryColor,
    onPrimary: Colors.black,
    secondary: secondaryColor,
    onSecondary: Colors.white,
    error: Colors.red,
    onError: Colors.black,
    surface: const Color(0xFF1A1A1A),
    onSurface: Colors.white,
  );
  return themeModifier(ThemeData.from(colorScheme: darkGrayScheme));
}

/// Gets the OLED theme configuration (pure black surface)
/// Parameters:
///   - prefs: Encrypted shared preferences instance
/// Returns:
///   OLED theme configuration using the previous dark palette
Future<ThemeData> themeOled(EncryptedSharedPreferencesAsync prefs) async {
  final secondaryColorInt =
      await prefs.getInt('pref_secondary_color', defaultValue: 0xFF2196F3);
  final secondaryColor = Color(secondaryColorInt!);

  // Await getBool and provide default value, add null assertion
  if (!(await prefs.getBool("useDeviceTheme", defaultValue: false))! ||
      colorSchemeDark == null) {
    return themeModifier(
      ThemeData.from(
        colorScheme: ColorScheme(
          brightness: Brightness.dark,
          primary: secondaryColor,
          onPrimary: Colors.black,
          secondary: secondaryColor,
          onSecondary: Colors.white,
          error: Colors.red,
          onError: Colors.black,
          surface: Colors.black,
          onSurface: Colors.white,
        ),
      ),
    );
  } else {
    return themeModifier(ThemeData.from(colorScheme: colorSchemeDark!));
  }
}

/// Gets the raw brightness preference from preferences
/// Returns one of: system, light, dark, oled
Future<String> themeBrightnessPreference(
    EncryptedSharedPreferencesAsync prefs) async {
  final rawValue = await prefs.getString("brightness", defaultValue: "system");
  if (rawValue == null || !_supportedBrightnessValues.contains(rawValue)) {
    return 'system';
  }
  return rawValue;
}

/// Gets the current theme mode from preferences
/// Parameters:
///   - prefs: Encrypted shared preferences instance
/// Returns:
///   ThemeMode based on user preferences (system, light, or dark)
Future<ThemeMode> themeMode(EncryptedSharedPreferencesAsync prefs) async {
  final brightness = await themeBrightnessPreference(prefs);
  if (brightness == 'system') return ThemeMode.system;
  if (brightness == 'light') return ThemeMode.light;
  return ThemeMode.dark;
}
