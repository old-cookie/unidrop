import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unidrop/pages/home_page.dart';
import 'package:unidrop/pages/auth_page.dart';
import 'package:unidrop/providers/settings_provider.dart';
import 'package:unidrop/services/theme_service.dart';
import 'package:encrypt_shared_preferences/provider.dart';
import 'package:unidrop/features/security/custom_encryptor.dart';
import 'package:logging/logging.dart';

/// A record type that represents the complete theme state of the application.
/// Contains the current theme mode and both light and dark theme data.
typedef ThemeState = ({
  ThemeMode mode,
  String brightnessValue,
  ThemeData lightTheme,
  ThemeData darkTheme
});

/// Provider for encrypted shared preferences instance.
/// This provider must be overridden with an actual implementation.
final sharedPreferencesProvider =
    Provider<EncryptedSharedPreferencesAsync>((ref) {
  throw UnimplementedError(
      'EncryptedSharedPreferencesAsync provider was not overridden');
});

/// StateNotifierProvider that manages the theme state of the application.
/// Provides access to the current theme mode and theme data.
final themeStateNotifierProvider =
    NotifierProvider<ThemeStateNotifier, ThemeState>(ThemeStateNotifier.new);

/// Manages the theme state and handles theme-related operations.
/// Provides functionality to load and change themes asynchronously.
class ThemeStateNotifier extends Notifier<ThemeState> {
  EncryptedSharedPreferencesAsync? _prefs;

  @override
  ThemeState build() {
    _prefs ??= ref.watch(sharedPreferencesProvider);
    // Watch secondary color to trigger theme reload when it changes
    ref.watch(secondaryColorProvider);
    Future.microtask(loadInitialTheme);
    return (
      mode: ThemeMode.system,
      brightnessValue: 'system',
      lightTheme: themeModifier(ThemeData.light()),
      darkTheme: themeModifier(ThemeData.dark())
    );
  }

  /// Loads the initial theme configuration from encrypted shared preferences.
  /// This includes theme mode and both light and dark theme data.
  Future<void> loadInitialTheme() async {
    final prefs = _prefs!;
    final brightnessValue = await themeBrightnessPreference(prefs);
    final mode = await _calculateThemeMode(prefs);
    final light = await themeLight(prefs);
    final dark = brightnessValue == 'oled'
        ? await themeOled(prefs)
        : await themeDark(prefs);
    state = (
      mode: mode,
      brightnessValue: brightnessValue,
      lightTheme: light,
      darkTheme: dark,
    );
  }

  /// Calculates the theme mode based on stored preferences.
  /// Returns a Future that resolves to the appropriate ThemeMode.
  static Future<ThemeMode> _calculateThemeMode(
      EncryptedSharedPreferencesAsync prefs) async {
    return await themeMode(prefs);
  }

  /// Updates the theme mode with the provided brightness value.
  /// Stores the new value in encrypted shared preferences and updates the state.
  Future<void> setThemeMode(String brightnessValue) async {
    await _prefs!.setString("brightness", brightnessValue);
    // Recalculate and update state
    await loadInitialTheme();
  }
}

/// The entry point of the application.
/// Initializes necessary services and runs the app with provider scope.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _configureLogging();
  // Initialize EncryptedSharedPreferencesAsync with CustomEncryptor
  final key = "UniDropUniDropUniDropUniDrop"; // 32 chars for AES-256
  await EncryptedSharedPreferencesAsync.initialize(key,
      encryptor: CustomEncryptor());
  // Also initialize the legacy API to potentially satisfy internal checks
  await EncryptedSharedPreferences.initialize(key,
      encryptor: CustomEncryptor());
  final prefsInstance = EncryptedSharedPreferencesAsync.getInstance();
  runApp(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefsInstance)],
    child: const MyApp(),
  ));
}

void _configureLogging() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    final errorText = record.error == null ? '' : ' | error: ${record.error}';
    final stackText = record.stackTrace == null ? '' : '\n${record.stackTrace}';
    debugPrint(
      '[${record.level.name}] ${record.loggerName}: ${record.time.toIso8601String()} ${record.message}$errorText$stackText',
    );
  });
}

/// The root widget of the application.
/// Handles theme configuration and initial routing based on authentication status.
class MyApp extends ConsumerWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the future provider to ensure settings are loaded
    final settingsAsyncValue = ref.watch(settingsFutureProvider);
    // Watch the theme state provider
    final themeState = ref.watch(themeStateNotifierProvider);
    // Use AsyncValue.when to handle loading/error states for settings
    return settingsAsyncValue.when(
      data: (settings) {
        // Settings loaded successfully
        final bool biometricsSupportedOnPlatform =
            !kIsWeb && defaultTargetPlatform != TargetPlatform.macOS;
        final bool useBiometrics =
            settings.useBiometricAuth && biometricsSupportedOnPlatform;
        return MaterialApp(
          title: 'UniDrop',
          theme: themeState.lightTheme,
          darkTheme: themeState.darkTheme,
          themeMode: themeState.mode,
          home: useBiometrics ? const AuthPage() : const HomePage(),
        );
      },
      loading: () {
        // Show a loading indicator while settings are loading
        return const MaterialApp(
          home: Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
        );
      },
      error: (err, stack) {
        // Show an error message if settings fail to load
        return MaterialApp(
          home: Scaffold(
            body: Center(child: Text('Error loading settings: $err')),
          ),
        );
      },
    );
  }
}
