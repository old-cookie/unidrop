import 'package:flutter/foundation.dart';

/// A class that represents device information for network communication.
/// Contains IP address, port, device alias and optional device ID.
@immutable
class DeviceInfo {
  /// The IP address of the device.
  final String ip;

  /// The port number used for communication.
  final int port;

  /// A user-friendly name for the device.
  final String alias;

  /// Unique identifier for the device. Can be null.
  final String? deviceId;

  /// Creates a new [DeviceInfo] instance.
  /// Parameters:
  /// - [ip]: The IP address of the device
  /// - [port]: The port number for communication
  /// - [alias]: The display name of the device
  /// - [deviceId]: Optional unique identifier for the device
  const DeviceInfo({required this.ip, required this.port, required this.alias, this.deviceId});

  /// Creates a [DeviceInfo] instance from a JSON map.
  /// The JSON map must contain 'ip', 'port', and 'alias' keys.
  /// The 'deviceId' key is optional.
  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(ip: json['ip'] as String, port: json['port'] as int, alias: json['alias'] as String, deviceId: json['deviceId'] as String?);
  }

  /// Converts this [DeviceInfo] instance to a JSON map.
  /// Returns a map containing all the device information.
  Map<String, dynamic> toJson() {
    return {'ip': ip, 'port': port, 'alias': alias, 'deviceId': deviceId};
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceInfo &&
          runtimeType == other.runtimeType &&
          ip == other.ip &&
          port == other.port &&
          alias == other.alias &&
          deviceId == other.deviceId;
  @override
  int get hashCode => ip.hashCode ^ port.hashCode ^ alias.hashCode ^ deviceId.hashCode;
  @override
  String toString() {
    return 'DeviceInfo{ip: $ip, port: $port, alias: $alias, deviceId: $deviceId}'; // Removed fields
  }
}
