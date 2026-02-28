import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:encrypt_shared_preferences/provider.dart';

/// Light theme color scheme for the application
ColorScheme? colorSchemeLight;

/// Dark theme color scheme for the application
ColorScheme? colorSchemeDark;

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
  // Make function async
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (delay != null) {
      await Future.delayed(delay);
    }
    final currentTheme = await themeCurrent(context, prefs); // Await themeCurrent
    color ??= currentTheme.colorScheme.surface;
    bool colorsEqual(Color a, Color b) {
      return a.r == b.r && a.g == b.g && a.b == b.b && a.a == b.a;
    }

    Color effectiveStatusColor = (statusBarColor != null) ? statusBarColor : color!;
    bool shouldBeTransparent = !kIsWeb && colorsEqual(effectiveStatusColor, currentTheme.colorScheme.surface); // Use awaited theme
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarIconBrightness: (effectiveStatusColor.computeLuminance() > 0.179) ? Brightness.dark : Brightness.light,
        statusBarColor: shouldBeTransparent ? Colors.transparent : effectiveStatusColor,
        systemNavigationBarColor: (systemNavigationBarColor != null) ? systemNavigationBarColor : color,
      ),
    );
  });
}

/// Modifies the base theme with custom transition animations
/// Parameters:
///   - theme: The base theme to modify
/// Returns:
///   Modified ThemeData with custom page transitions
ThemeData themeModifier(ThemeData theme) {
  return theme.copyWith(
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{TargetPlatform.android: PredictiveBackPageTransitionsBuilder()},
    ),
  );
}

/// Gets the current theme based on system settings and user preferences
/// Parameters:
///   - context: The build context
///   - prefs: Encrypted shared preferences instance
/// Returns:
///   The appropriate ThemeData based on current settings
Future<ThemeData> themeCurrent(BuildContext context, EncryptedSharedPreferencesAsync prefs) async {
  final currentMode = await themeMode(prefs); // Await themeMode
  if (currentMode == ThemeMode.system) {
    if (MediaQuery.of(context).platformBrightness == Brightness.light) {
      return await themeLight(prefs); // Await themeLight
    } else {
      return await themeDark(prefs); // Await themeDark
    }
  } else {
    if (currentMode == ThemeMode.light) {
      return await themeLight(prefs); // Await themeLight
    } else {
      return await themeDark(prefs); // Await themeDark
    }
  }
}

/// Gets the light theme configuration
/// Parameters:
///   - prefs: Encrypted shared preferences instance
/// Returns:
///   Light theme configuration with appropriate color scheme
Future<ThemeData> themeLight(EncryptedSharedPreferencesAsync prefs) async {
  // Await getBool and provide default value, add null assertion
  if (!(await prefs.getBool("useDeviceTheme", defaultValue: false))! || colorSchemeLight == null) {
    return themeModifier(
      ThemeData.from(
        colorScheme: const ColorScheme(
          brightness: Brightness.light,
          primary: Colors.black,
          onPrimary: Colors.white,
          secondary: Colors.white,
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
  // Await getBool and provide default value, add null assertion
  if (!(await prefs.getBool("useDeviceTheme", defaultValue: false))! || colorSchemeDark == null) {
    return themeModifier(
      ThemeData.from(
        colorScheme: const ColorScheme(
          brightness: Brightness.dark,
          primary: Colors.white,
          onPrimary: Colors.black,
          secondary: Colors.black,
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

/// Gets the current theme mode from preferences
/// Parameters:
///   - prefs: Encrypted shared preferences instance
/// Returns:
///   ThemeMode based on user preferences (system, light, or dark)
Future<ThemeMode> themeMode(EncryptedSharedPreferencesAsync prefs) async {
  // Await getString and provide default value
  final brightness = await prefs.getString("brightness", defaultValue: "system");
  return (brightness == "system") ? ThemeMode.system : ((brightness == "dark") ? ThemeMode.dark : ThemeMode.light);
}
