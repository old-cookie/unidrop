import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unidrop/providers/settings_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:unidrop/main.dart';
import 'package:logging/logging.dart';

final _logger = Logger('SettingsPage');

/// Helper function to provide haptic feedback on selection
void selectionHaptic() {
  HapticFeedback.selectionClick();
}

/// Settings page widget that displays and manages all app settings
/// Uses ConsumerWidget to access app state through Riverpod
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  /// Builds a segmented button for theme selection
  /// [context] - BuildContext for the widget
  /// [ref] - WidgetRef for state management
  /// Returns a SegmentedButton widget for theme selection
  Widget _buildBrightnessSegmentedButton(BuildContext context, WidgetRef ref) {
    // Watch the theme state provider synchronously
    final themeState = ref.watch(themeStateNotifierProvider);
    final currentMode = themeState.mode;

    // Convert ThemeMode enum to string for SegmentedButton
    String currentBrightnessString = "system";
    switch (currentMode) {
      case ThemeMode.dark:
        currentBrightnessString = "dark";
        break;
      case ThemeMode.light:
        currentBrightnessString = "light";
        break;
      case ThemeMode.system:
        currentBrightnessString = "system";
        break;
    }

    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(
            value: "dark",
            label: Text("Dark"),
            icon: Icon(Icons.brightness_4_rounded)),
        ButtonSegment(
            value: "system",
            label: Text("System"),
            icon: Icon(Icons.brightness_auto_rounded)),
        ButtonSegment(
            value: "light",
            label: Text("Light"),
            icon: Icon(Icons.brightness_high_rounded)),
      ],
      selected: {currentBrightnessString}, // Use the converted string
      onSelectionChanged: (Set<String> newSelection) async {
        selectionHaptic();
        final newBrightness = newSelection.first;
        // Use the renamed provider
        await ref
            .read(themeStateNotifierProvider.notifier)
            .setThemeMode(newBrightness);
      },
    );
  }

  /// Shows a dialog to edit the device alias
  /// [context] - BuildContext for the dialog
  /// [ref] - WidgetRef for state management
  /// [currentAlias] - Current device alias to show in the dialog
  Future<void> _showEditAliasDialog(
      BuildContext context, WidgetRef ref, String currentAlias) async {
    final TextEditingController controller =
        TextEditingController(text: currentAlias);
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Edit Device Alias'),
          content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Enter new alias')),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Save'),
              onPressed: () async {
                final newAlias = controller.text.trim();
                if (newAlias.isNotEmpty) {
                  // Use the main settingsProvider notifier
                  await ref.read(settingsProvider.notifier).setAlias(newAlias);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Alias updated successfully!')));
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Alias cannot be empty.')));
                }
              },
            ),
          ],
        );
      },
    );
  }

  /// Opens a directory picker to select destination directory for downloads
  /// [context] - BuildContext for showing feedback
  /// [ref] - WidgetRef for state management
  Future<void> _pickDestinationDirectory(
      BuildContext context, WidgetRef ref) async {
    try {
      String? selectedDirectory = await FilePicker.platform
          .getDirectoryPath(dialogTitle: 'Select Destination Directory');
      if (selectedDirectory != null) {
        await ref
            .read(settingsProvider.notifier)
            .setDestinationDirectory(selectedDirectory);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:
                  Text('Destination directory set to: $selectedDirectory')));
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Directory selection cancelled.')));
        }
      }
    } catch (e) {
      _logger.severe('Error picking directory', e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error selecting directory: $e')));
      }
    }
  }

  /// Builds the settings page UI with all available options
  /// [context] - BuildContext for the widget
  /// [ref] - WidgetRef for accessing app state
  /// Returns a Scaffold containing the settings UI
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String currentAlias = ref.watch(deviceAliasProvider);
    final String? currentDestinationDir =
        ref.watch(destinationDirectoryProvider);
    final bool useBiometricAuth = ref.watch(biometricAuthProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Device Alias'),
            subtitle: Text(currentAlias),
            onTap: () {
              _showEditAliasDialog(context, ref, currentAlias);
            },
          ),
          // Conditionally hide Destination Directory on web
          if (!kIsWeb) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('Destination Directory'),
              subtitle: Text(
                  currentDestinationDir ?? 'Not set (Defaults to Downloads)'),
              onTap: () {
                _pickDestinationDirectory(context, ref);
              },
            ),
          ], // End of conditional block for Destination Directory
          const Divider(),
          if (!kIsWeb)
            SwitchListTile(
              secondary: const Icon(Icons.fingerprint),
              title: const Text('Use Biometric Authentication'),
              subtitle:
                  const Text('Require fingerprint/face ID to open the app'),
              value: useBiometricAuth,
              onChanged: (bool value) {
                // Use the main settingsProvider notifier
                ref.read(settingsProvider.notifier).setBiometricAuth(value);
              },
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Brightness'),
            // Call the synchronous widget directly
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: _buildBrightnessSegmentedButton(
                  context, ref), // Remove FutureBuilder
            ),
          ),
          const Divider(),
        ],
      ),
    );
  }
}
