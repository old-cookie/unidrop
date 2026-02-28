import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

class PermissionManager {
  /// Requests permission to access photos and videos on the device
  /// For Android 13 (API 33) and above, requests both photos and videos permissions separately
  /// For Android below 13, requests storage permission
  /// For iOS, requests photos permission only
  /// Returns true if permission is granted, false otherwise
  static Future<bool> requestPhotosPermission() async {
    PermissionStatus status;
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        status = await Permission.photos.request();
        if (status.isGranted) {
          status = await Permission.videos.request();
        }
      } else {
        status = await Permission.storage.request();
      }
    } else if (Platform.isIOS) {
      status = await Permission.photos.request();
    } else {
      return true;
    }
    return status.isGranted;
  }

  /// Requests permission to access device storage
  /// Only applicable for Android devices below Android 13 (API 33)
  /// For Android 13 and above, returns true without requesting permission
  /// For other platforms, returns true by default
  /// Returns true if permission is granted, false otherwise
  static Future<bool> requestStoragePermission() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      if (androidInfo.version.sdkInt < 33) {
        final status = await Permission.storage.request();
        return status.isGranted;
      } else {
        return true;
      }
    } else {
      return true;
    }
  }

  /// Opens the app settings page in device settings
  /// Useful when permissions need to be granted manually by the user
  /// Returns true if the settings page was successfully opened
  static Future<bool> openPermissionSettings() async {
    return await openAppSettings();
  }
}
