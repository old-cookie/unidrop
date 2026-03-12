import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:encrypt_shared_preferences/provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:unidrop/main.dart' show sharedPreferencesProvider;
import 'package:logging/logging.dart';

final _logger = Logger('SettingsProvider');

// --- Settings State and Notifier ---

const String _prefDeviceAlias = 'pref_device_alias';
const String _prefDestinationDir = 'pref_destination_dir';
const String _prefUseBiometricAuth = 'pref_use_biometric_auth';
const String _prefFavoriteDevices =
    'pref_favorite_devices'; // Key for favorites
const String _prefSecondaryColor =
    'pref_secondary_color'; // Key for secondary color

/// Represents the complete state of application settings
/// Contains device alias, destination directory, biometric auth setting, favorite devices, and secondary color
class SettingsState {
  final String alias;
  final String? destinationDir;
  final bool useBiometricAuth;
  final List<Map<String, String>>
      favoriteDevices; // List of {ip: '...', name: '...'}
  final int secondaryColor; // Color as ARGB integer

  SettingsState({
    required this.alias,
    this.destinationDir,
    required this.useBiometricAuth,
    required this.favoriteDevices,
    required this.secondaryColor,
  });

  SettingsState copyWith({
    String? alias,
    String? destinationDir,
    bool? useBiometricAuth,
    List<Map<String, String>>? favoriteDevices,
    int? secondaryColor,
    bool clearDestinationDir =
        false, // Flag to explicitly set destinationDir to null
  }) {
    return SettingsState(
      alias: alias ?? this.alias,
      destinationDir:
          clearDestinationDir ? null : destinationDir ?? this.destinationDir,
      useBiometricAuth: useBiometricAuth ?? this.useBiometricAuth,
      favoriteDevices: favoriteDevices ?? this.favoriteDevices,
      secondaryColor: secondaryColor ?? this.secondaryColor,
    );
  }
}

/// Manages the application settings state and persistence
/// Handles loading, saving and updating all settings
class SettingsNotifier extends Notifier<SettingsState> {
  EncryptedSharedPreferencesAsync? _prefs;
  static final DeviceInfoPlugin _deviceInfoPlugin =
      DeviceInfoPlugin(); // Instance for device info

  @override
  SettingsState build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    final asyncInitialState = ref.watch(settingsFutureProvider);
    return asyncInitialState.when(
      data: (initialState) => initialState,
      loading: () {
        _logger.info(
            "Settings loading... Initializing notifier with fallback state.");
        return SettingsState(
          alias: SettingsNotifier._generateDefaultAliasSyncFallback(),
          useBiometricAuth: false,
          favoriteDevices: [],
          destinationDir: null,
          secondaryColor: 0xFF2196F3,
        );
      },
      error: (err, stack) {
        _logger.severe("Error loading initial settings: $err", err, stack);
        return SettingsState(
          alias: SettingsNotifier._generateDefaultAliasSyncFallback(),
          useBiometricAuth: false,
          favoriteDevices: [],
          destinationDir: null,
          secondaryColor: 0xFF2196F3,
        );
      },
    );
  }

  // Load all settings asynchronously
  static Future<SettingsState> loadInitialState(
      EncryptedSharedPreferencesAsync prefs) async {
    // Load existing alias or generate default if null
    String? alias = await prefs.getString(_prefDeviceAlias);
    if (alias == null) {
      alias = await _generateDefaultAlias();
      // Save the newly generated default alias
      await prefs.setString(_prefDeviceAlias, alias);
    }

    final destinationDir = await prefs.getString(_prefDestinationDir);
    final useBiometricAuth =
        await prefs.getBool(_prefUseBiometricAuth, defaultValue: false);

    // Load favorite devices
    final favoritesJson =
        await prefs.getString(_prefFavoriteDevices, defaultValue: '[]');
    List<Map<String, String>> favoriteDevices = [];
    try {
      List<dynamic> decodedList =
          jsonDecode(favoritesJson!); // Non-null due to defaultValue
      favoriteDevices = decodedList
          .whereType<Map<dynamic, dynamic>>() // Ensure items are maps
          .map((item) => item.map((key, value) => MapEntry(key.toString(),
              value.toString()))) // Convert keys/values to strings
          .toList();
    } catch (e) {
      _logger.warning("Error decoding favorite devices: $e");
      // If decoding fails, start with an empty list and save it
      await prefs.setString(_prefFavoriteDevices, '[]');
    }

    final secondaryColorInt =
        await prefs.getInt(_prefSecondaryColor, defaultValue: 0xFF2196F3);

    return SettingsState(
      alias: alias, // Now guaranteed non-null
      destinationDir: destinationDir,
      useBiometricAuth: useBiometricAuth!, // Non-null due to defaultValue
      favoriteDevices: favoriteDevices,
      secondaryColor: secondaryColorInt!,
    );
  }

  // Now async to fetch device info
  static Future<String> _generateDefaultAlias() async {
    try {
      if (kIsWeb) {
        return 'Web Browser';
      } else if (Platform.isAndroid) {
        final androidInfo = await _deviceInfoPlugin.androidInfo;
        return androidInfo.model; // Use device model name
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfoPlugin.iosInfo;
        return iosInfo.name; // Use user-assigned device name
      } else if (Platform.isLinux) {
        return Platform.localHostname;
      } else if (Platform.isMacOS) {
        return Platform.localHostname;
      } else if (Platform.isWindows) {
        return Platform.localHostname;
      }
    } catch (e) {
      _logger.warning("Error getting device name for default alias: $e", e);
    }
    // Fallback
    return 'UniDrop Device';
  }

  // Static method for synchronous fallback (used for initial provider state)
  // This avoids making the StateNotifierProvider setup async, which is complex.
  // The actual loaded state comes from settingsFutureProvider.
  static String _generateDefaultAliasSyncFallback() {
    try {
      if (kIsWeb) return 'Web Browser';
      if (Platform.isAndroid) return 'Android Device';
      if (Platform.isIOS) return 'iOS Device';
      if (Platform.isLinux) return Platform.localHostname;
      if (Platform.isMacOS) return Platform.localHostname;
      if (Platform.isWindows) return Platform.localHostname;
    } catch (e) {
      // Ignore error in sync fallback
    }
    return 'UniDrop Device';
  }

  /// Sets a new device alias
  /// [newAlias] The new alias to set. Must not be empty.
  Future<void> setAlias(String newAlias) async {
    if (newAlias.isNotEmpty) {
      await _prefs!.setString(_prefDeviceAlias, newAlias);
      state = state.copyWith(alias: newAlias);
    }
  }

  /// Sets or clears the destination directory for file downloads
  /// [newDir] The new directory path, or null to clear
  Future<void> setDestinationDirectory(String? newDir) async {
    if (newDir == null) {
      await _prefs!.remove(_prefDestinationDir);
      state = state.copyWith(clearDestinationDir: true);
    } else {
      await _prefs!.setString(_prefDestinationDir, newDir);
      state = state.copyWith(destinationDir: newDir);
    }
  }

  /// Enables or disables biometric authentication
  /// [enabled] Whether biometric auth should be enabled
  Future<void> setBiometricAuth(bool enabled) async {
    await _prefs!.setBool(_prefUseBiometricAuth, enabled);
    state = state.copyWith(useBiometricAuth: enabled);
  }

  /// Adds a device to favorites if not already present
  /// [deviceData] Map containing device info with 'ip' and 'name' keys
  Future<void> addFavoriteDevice(Map<String, String> deviceData) async {
    // Avoid duplicates based on IP (or a combination if needed)
    if (state.favoriteDevices.any((fav) => fav['ip'] == deviceData['ip'])) {
      _logger.info("Device already in favorites.");
      return; // Or update existing? For now, just skip duplicates.
    }

    final updatedFavorites =
        List<Map<String, String>>.from(state.favoriteDevices)..add(deviceData);
    await _prefs!.setString(_prefFavoriteDevices, jsonEncode(updatedFavorites));
    state = state.copyWith(favoriteDevices: updatedFavorites);
  }

  /// Removes a device from favorites by matching IP
  /// [deviceData] Map containing device info, must include 'ip' key
  Future<void> removeFavoriteDevice(Map<String, String> deviceData) async {
    // Ensure deviceData has an 'ip' key before proceeding
    if (!deviceData.containsKey('ip')) {
      _logger.warning("Attempted to remove favorite without an IP address.");
      return;
    }
    final updatedFavorites = List<Map<String, String>>.from(
        state.favoriteDevices)
      ..removeWhere(
          (fav) => fav['ip'] == deviceData['ip']); // Match only IP for removal
    await _prefs!.setString(_prefFavoriteDevices, jsonEncode(updatedFavorites));
    state = state.copyWith(favoriteDevices: updatedFavorites);
    _logger.fine(
        "Notifier state updated. New favorites list: ${state.favoriteDevices}");
  }

  /// Sets the secondary color for buttons and accents
  /// [colorValue] The color as an ARGB integer
  Future<void> setSecondaryColor(int colorValue) async {
    await _prefs!.setInt(_prefSecondaryColor, colorValue);
    state = state.copyWith(secondaryColor: colorValue);
  }
}

/// Provider that ensures settings are fully loaded before access
/// Returns a Future [SettingsState] that completes when settings are loaded
final settingsFutureProvider = FutureProvider<SettingsState>((ref) async {
  // Assuming sharedPreferencesProvider is Provider<EncryptedSharedPreferencesAsync>
  // If it's FutureProvider<EncryptedSharedPreferencesAsync>, use .future
  final prefs = ref.watch(sharedPreferencesProvider);
  // If sharedPreferencesProvider IS a FutureProvider, uncomment the line below and comment the line above
  // final prefs = await ref.watch(sharedPreferencesProvider.future);
  final initialState = await SettingsNotifier.loadInitialState(prefs);
  return initialState;
});

/// Main settings provider that maintains the current settings state
/// Provides access to settings values and methods to modify them
final settingsProvider =
    NotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);

/// Provides convenient access to just the device alias
final deviceAliasProvider = Provider<String>((ref) {
  // Watch the main StateNotifierProvider to get live updates
  final settingsState = ref.watch(settingsProvider);
  return settingsState.alias;
  // Note: Initial loading state might need handling in the UI
  // if accessed before settingsFutureProvider completes.
});

/// Provides convenient access to just the destination directory
final destinationDirectoryProvider = Provider<String?>((ref) {
  // Watch the main StateNotifierProvider to get live updates
  final settingsState = ref.watch(settingsProvider);
  return settingsState.destinationDir;
});

/// Provides convenient access to just the biometric auth setting
final biometricAuthProvider = Provider<bool>((ref) {
  // Watch the main StateNotifierProvider to get live updates
  final settingsState = ref.watch(settingsProvider);
  return settingsState.useBiometricAuth;
});

/// Provides convenient access to just the secondary color
final secondaryColorProvider = Provider<int>((ref) {
  // Watch the main StateNotifierProvider to get live updates
  final settingsState = ref.watch(settingsProvider);
  return settingsState.secondaryColor;
});

/// Provides convenient access to just the list of favorite devices
final favoriteDevicesProvider = Provider<List<Map<String, String>>>((ref) {
  // Watch the StateNotifierProvider directly to get live updates
  final settingsState = ref.watch(settingsProvider);
  return settingsState.favoriteDevices;
});
