import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:unidrop/pages/auth_page.dart';
import 'package:unidrop/pages/home_page.dart';
import 'package:unidrop/providers/settings_provider.dart';

Widget buildAppHome(SettingsState settings) {
  final bool biometricsSupportedOnPlatform =
      defaultTargetPlatform != TargetPlatform.macOS;
  final bool useBiometrics =
      settings.useBiometricAuth && biometricsSupportedOnPlatform;
  return useBiometrics ? const AuthPage() : const HomePage();
}
