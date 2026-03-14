import 'dart:async';
import 'package:flutter/foundation.dart'
  show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:logging/logging.dart';

/// Service responsible for handling security features, primarily biometric authentication.
class SecurityService {
  // ignore: unused_field
  final Ref _ref; // Riverpod reference for accessing other providers.
  final LocalAuthentication
      _localAuth; // Instance of the local authentication plugin.
  final _logger = Logger('SecurityService');

  /// Error code for unknown errors during authentication.
  static const String errorUnknown = 'Unknown';

  /// Error code when biometric authentication is not available on the device.
  static const String errorNotAvailable = 'NotAvailable';

  /// Error code when no biometrics are enrolled on the device.
  static const String errorNotEnrolled = 'NotEnrolled';

  /// Error code when the device passcode is not set (required for some biometric setups).
  static const String errorPasscodeNotSet = 'PasscodeNotSet';

  /// Error code when the user is temporarily locked out due to too many failed attempts.
  static const String errorLockedOut = 'LockedOut';

  /// Error code when the user is permanently locked out due to too many failed attempts.
  static const String errorPermanentlyLockedOut = 'PermanentlyLockedOut';

  /// Creates an instance of [SecurityService].
  /// Requires a [Ref] from Riverpod to potentially interact with other services.
  SecurityService(this._ref) : _localAuth = LocalAuthentication();

  /// Initializes the security service.
  /// Currently, this method is a placeholder as security features are primarily
  /// handled on demand (e.g., during authentication). It prints a message
  /// indicating that no specific security features are enabled by default.
  Future<void> initialize() async {
    _logger.info(
        'SecurityService initialize: No security features enabled (HTTP only).');
    // No async operations needed for initialization in this version.
    await Future.value();
  }

  /// Attempts to authenticate the user using biometrics (e.g., fingerprint, face ID).
  /// [localizedReason] is the message displayed to the user explaining why
  /// authentication is needed.
  /// Returns a `Map<String, dynamic>` containing:
  /// - `success`: A boolean indicating whether authentication was successful.
  /// - `errorCode`: A string code representing the error if authentication failed (e.g., 'NotAvailable', 'LockedOut'). Empty if successful.
  /// - `errorMessage`: A user-friendly message describing the outcome or error.
  Future<Map<String, dynamic>> authenticateWithBiometrics(
      String localizedReason) async {
    // Default result indicating failure.
    Map<String, dynamic> result = {
      'success': false,
      'errorCode': errorUnknown,
      'errorMessage': 'An unknown error occurred.'
    };

    // Biometric authentication is not supported on web platforms.
    if (kIsWeb) {
      _logger.info('Biometric authentication is not available on the web.');
      result['errorCode'] = errorNotAvailable;
      result['errorMessage'] =
          'Biometric authentication is not available on the web.';
      return result;
    }

    try {
      // Check if the device hardware supports biometric authentication.
      final bool deviceSupported = await _localAuth.isDeviceSupported();
      if (!deviceSupported) {
        result['errorCode'] = errorNotAvailable;
        result['errorMessage'] =
            'Authentication is not supported on this device.';
        _logger.warning(result['errorMessage']);
        return result;
      }

      // Check if biometric authentication is currently available (e.g., enabled in settings).
      final bool canCheckBiometrics = await _localAuth.canCheckBiometrics;
      if (!canCheckBiometrics) {
        _logger.warning(
            'Biometrics currently unavailable. Falling back to device credentials.');
        return _authenticateWithDeviceCredentials(localizedReason,
            fallbackReason: 'Biometrics currently unavailable.');
      }

      // Get the list of biometric types enrolled by the user.
      final List<BiometricType> availableBiometrics =
          await _localAuth.getAvailableBiometrics();
      if (availableBiometrics.isEmpty) {
        _logger.warning(
            'No biometrics enrolled on this device. Falling back to device credentials.');
        return _authenticateWithDeviceCredentials(localizedReason,
            fallbackReason: 'No biometrics enrolled on this device.');
      }

      _logger.info("Available biometrics: $availableBiometrics");

        final supportsBiometricOnly =
          defaultTargetPlatform != TargetPlatform.windows;
        if (!supportsBiometricOnly) {
        _logger.info(
          'Windows detected. Using device credentials flow because biometricOnly is not supported.');
        return _authenticateWithDeviceCredentials(localizedReason,
          fallbackReason:
            'Windows platform does not support biometricOnly parameter.');
        }

      // Attempt the actual biometric authentication.
      final bool didAuthenticate = await _localAuth.authenticate(
        localizedReason: localizedReason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );

      // Update result based on authentication outcome.
      if (didAuthenticate) {
        result['success'] = true;
        result['errorCode'] = '';
        result['errorMessage'] = 'Authentication successful.';
      } else {
        // Authentication failed or was cancelled by the user.
        result['success'] = false;
        // Keep default error code unless a specific PlatformException is caught later.
        result['errorCode'] = errorUnknown;
        result['errorMessage'] = 'Authentication failed or was cancelled.';
      }
      return result;
    } on LocalAuthException catch (e) {
      // Handle specific errors thrown by the local_auth plugin.
      _logger.severe(
          'Biometric authentication error: ${e.code} - ${e.description}');
      result['success'] = false;
      result['errorCode'] = e.code.name;
      result['errorMessage'] =
          e.description ?? 'An authentication error occurred.';

      // Map platform exception codes to predefined error constants for consistency.
      switch (e.code) {
        case LocalAuthExceptionCode.temporaryLockout:
          result['errorCode'] = errorLockedOut;
          return _authenticateWithDeviceCredentials(localizedReason,
              fallbackReason:
                  'Biometric authentication temporarily locked. Use device credentials.');
        case LocalAuthExceptionCode.biometricLockout:
          result['errorCode'] = errorPermanentlyLockedOut;
          return _authenticateWithDeviceCredentials(localizedReason,
              fallbackReason:
                  'Biometric authentication locked. Use device credentials.');
        case LocalAuthExceptionCode.noBiometricHardware:
        case LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable:
          result['errorCode'] = errorNotAvailable;
          return _authenticateWithDeviceCredentials(localizedReason,
              fallbackReason:
                  'Biometric hardware unavailable. Use device credentials.');
        case LocalAuthExceptionCode.noBiometricsEnrolled:
          result['errorCode'] = errorNotEnrolled;
          return _authenticateWithDeviceCredentials(localizedReason,
              fallbackReason: 'No biometrics enrolled. Use device credentials.');
        case LocalAuthExceptionCode.noCredentialsSet:
          result['errorCode'] = errorPasscodeNotSet;
          break;
        // Keep the original e.code if it doesn't match known cases.
        default:
          break;
      }
      return result;
    } catch (e) {
      // Catch any other unexpected errors.
      _logger.severe('Unexpected error during biometric authentication: $e');
      result['success'] = false;
      result['errorCode'] = errorUnknown;
      result['errorMessage'] = 'An unexpected error occurred: $e';
      return result;
    }
  }

  Future<Map<String, dynamic>> _authenticateWithDeviceCredentials(
    String localizedReason, {
    required String fallbackReason,
  }) async {
    final result = <String, dynamic>{
      'success': false,
      'errorCode': errorUnknown,
      'errorMessage': 'Authentication failed.'
    };

    try {
      _logger.info('Fallback to device credentials. Reason: $fallbackReason');
      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: localizedReason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );

      if (didAuthenticate) {
        result['success'] = true;
        result['errorCode'] = '';
        result['errorMessage'] = 'Authentication successful.';
      } else {
        result['success'] = false;
        result['errorCode'] = errorUnknown;
        result['errorMessage'] =
            'Authentication failed or was cancelled.';
      }
      return result;
    } on LocalAuthException catch (e) {
      _logger.severe(
          'Device credential authentication error: ${e.code} - ${e.description}');
      result['success'] = false;
      result['errorCode'] = e.code.name;
      result['errorMessage'] =
          e.description ?? 'Device credential authentication failed.';
      if (e.code == LocalAuthExceptionCode.noCredentialsSet) {
        result['errorCode'] = errorPasscodeNotSet;
      }
      return result;
    } catch (e) {
      _logger.severe(
          'Unexpected error during device credential authentication: $e');
      result['success'] = false;
      result['errorCode'] = errorUnknown;
      result['errorMessage'] = 'An unexpected error occurred: $e';
      return result;
    }
  }
}

/// Provider for the [SecurityService].
///
/// This provides the raw instance of the service.
final securityServiceProvider = Provider<SecurityService>((ref) {
  final service = SecurityService(ref);
  return service;
});

/// FutureProvider that initializes the [SecurityService] before providing it.
///
/// This ensures that the `initialize` method is called and awaited.
/// Useful if initialization involves asynchronous operations.
final initializedSecurityServiceProvider =
    FutureProvider<SecurityService>((ref) async {
  // Watch the raw provider.
  final service = ref.watch(securityServiceProvider);
  // Call the initialize method.
  await service.initialize();
  // Return the initialized service.
  return service;
});
