import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unidrop/features/discovery/discovery_provider.dart';
import 'package:unidrop/models/device_info.dart';
import 'package:unidrop/providers/settings_provider.dart';
import 'package:logging/logging.dart';

// Provides the DiscoveryService instance.
final discoveryServiceProvider = Provider<DiscoveryService>((ref) {
  return DiscoveryService(ref);
});

/// Handles network discovery of other UniDrop devices using UDP multicast.
///
class DiscoveryService {
  final _logger = Logger('DiscoveryService');
  final Ref _ref; // Riverpod ref for accessing other providers.
  RawDatagramSocket?
      _socket; // The UDP socket used for multicast communication.
  Timer? _discoveryTimer; // Timer for periodically sending discovery packets.
  bool _isDiscovering =
      false; // Flag indicating if discovery is currently active.
  final Set<String> _localIPs =
      {}; // Set of local IP addresses to filter self-discovery.
  final Map<String, Timer> _deviceExpiryTimers =
      {}; // Timers to track device timeouts.
  final Duration _deviceTimeout = const Duration(
      seconds: 15); // Duration after which a device is considered offline.
  final Duration _discoveryInterval =
      const Duration(seconds: 5); // Interval for sending discovery packets.
  final String _multicastAddress =
      '224.0.0.1'; // Multicast address for discovery.
  static const int _listenPort = 2706; // Port used for discovery communication.

  /// Creates a DiscoveryService instance.
  ///
  /// Requires a [Ref] to interact with other Riverpod providers.
  DiscoveryService(this._ref);

  /// Starts the discovery process.
  ///
  /// Binds a UDP socket, joins the multicast group, and starts sending
  /// discovery packets periodically. Does nothing if discovery is already active
  /// or if running on the web platform.
  Future<void> startDiscovery() async {
    if (kIsWeb) {
      _logger.info('Discovery service is not supported on the web platform.');
      return;
    }
    // Do nothing if discovery is already running.
    if (_isDiscovering) return;

    // Update the list of local IP addresses before starting.
    await _updateLocalIPs();
    // Warn if local IPs couldn't be determined, as self-discovery filtering might fail.
    if (_localIPs.isEmpty && !kIsWeb) {
      _logger.warning(
          "Could not determine local IP addresses. Self-discovery filtering might not work.");
    }

    try {
      // Bind the UDP socket to listen on any IPv4 address and the specified port.
      _socket =
          await RawDatagramSocket.bind(InternetAddress.anyIPv4, _listenPort);
      // Join the multicast group to receive discovery packets.
      _socket!.joinMulticast(InternetAddress(_multicastAddress));
      // Listen for incoming datagrams.
      _socket!.listen(
        _handleResponse,
        onError: (error) {
          _logger.severe('Discovery socket error: $error');
          stopDiscovery();
        },
        onDone: () {
          _logger.info('Discovery socket closed.');
          _isDiscovering = false;
        },
      );

      _isDiscovering = true;
      _logger.info(
          'Discovery started on port $_listenPort, joined multicast group $_multicastAddress');

      // Send the initial discovery packet immediately.
      await _sendDiscoveryPacket();

      // Start a timer to send discovery packets periodically.
      _discoveryTimer = Timer.periodic(_discoveryInterval, (timer) async {
        // Stop the timer if discovery is no longer active.
        if (!_isDiscovering) {
          timer.cancel();
          return;
        }
        // Send a discovery packet.
        await _sendDiscoveryPacket();
      });
    } catch (e) {
      // Handle errors during discovery startup.
      _logger.severe('Failed to start discovery: $e');
      _isDiscovering = false; // Ensure discovery state is updated.
      await stopDiscovery(); // Clean up resources.
    }
  }

  /// Stops the discovery process.
  ///
  /// Cancels the discovery timer, closes the socket, clears device expiry timers,
  /// and clears the list of discovered devices.
  Future<void> stopDiscovery() async {
    // Do nothing if discovery is not running or already stopped.
    if (!_isDiscovering && _socket == null && _discoveryTimer == null) return;

    _logger.info('Stopping discovery...');
    _isDiscovering = false; // Mark discovery as inactive.

    // Cancel the periodic discovery timer.
    _discoveryTimer?.cancel();
    _discoveryTimer = null;

    // Close the UDP socket.
    _socket?.close();
    _socket = null;

    // Cancel all active device expiry timers
    for (final timer in _deviceExpiryTimers.values) {
      timer.cancel();
    }
    _deviceExpiryTimers.clear();

    // Clear the list of discovered devices in the provider.
    _ref.read(discoveredDevicesProvider.notifier).clearDevices();

    _logger.info('Discovery stopped.');
  }

  /// Sends a discovery packet over the multicast network.
  ///
  /// The packet contains the device's alias and listening port.
  Future<void> _sendDiscoveryPacket() async {
    // Ensure the socket is available and discovery is active.
    if (_socket == null || !_isDiscovering) return;

    // Get the device alias from settings.
    final String alias = _ref.read(deviceAliasProvider);
    // Prepare the discovery message payload.
    final message = jsonEncode(
        {'alias': alias, 'port': _listenPort, 'type': 'discovery_request'});
    final data = utf8.encode(message); // Encode the message to UTF-8 bytes.

    try {
      // Send the packet to the multicast address and port.
      _socket!.send(data, InternetAddress(_multicastAddress), _listenPort);
    } catch (e) {
      // Log errors during packet sending.
      _logger.warning('Error sending discovery packet: $e');
    }
  }

  /// Handles incoming UDP datagrams.
  ///
  /// Parses the received packet, extracts device information, filters out
  /// packets from the local device, updates the discovered devices list,
  /// and resets the device expiry timer.
  void _handleResponse(RawSocketEvent event) {
    // Process only read events.
    if (event == RawSocketEvent.read) {
      // Receive the datagram from the socket.
      final datagram = _socket?.receive();
      if (datagram == null) return; // Ignore if no datagram is received.

      try {
        // Decode the message from UTF-8 bytes.
        final message = utf8.decode(datagram.data);
        // Parse the JSON payload.
        final data = jsonDecode(message);

        // Extract sender information.
        final String senderIp = datagram.address.address;
        final int senderPort = data['port'];
        final String senderAlias = data['alias'];

        // Ignore packets sent from the same IP and port as this device (self-discovery).
        if (senderPort == _listenPort && _isOwnIp(senderIp)) {
          return; // Skip processing self-sent packets.
        }

        // Process only discovery request or response packets.
        if (data['type'] == 'discovery_request' ||
            data['type'] == 'discovery_response') {
          // Create a DeviceInfo object for the discovered device.
          final deviceInfo =
              DeviceInfo(ip: senderIp, port: senderPort, alias: senderAlias);
          // Generate a unique key for the device based on IP and port.
          final deviceKey = '${deviceInfo.ip}:${deviceInfo.port}';

          // Cancel any existing expiry timer for this device.
          _deviceExpiryTimers[deviceKey]?.cancel();
          // Add or update the device in the discovered devices list.
          _ref.read(discoveredDevicesProvider.notifier).addDevice(deviceInfo);

          // Start a new expiry timer for the device.
          _deviceExpiryTimers[deviceKey] = Timer(_deviceTimeout, () {
            // Executed when the timer expires (device timed out).
            _logger.info('Device ${deviceInfo.alias} ($deviceKey) timed out.');
            // Remove the device from the discovered list.
            _ref
                .read(discoveredDevicesProvider.notifier)
                .removeDevice(deviceInfo);
            // Remove the timer from the map.
            _deviceExpiryTimers.remove(deviceKey);
          });
        }
      } catch (e) {
        // Log errors during packet processing.
        _logger.warning(
            'Error processing received packet from ${datagram.address.address}: $e');
      }
    }
  }

  /// Checks if the given IP address belongs to the local device.
  ///
  /// Uses the cached list of local IP addresses (`_localIPs`).
  bool _isOwnIp(String ip) {
    return _localIPs.contains(ip);
  }

  /// Updates the set of local IP addresses.
  ///
  /// Fetches network interfaces and extracts IPv4 addresses. Not supported on web.
  Future<void> _updateLocalIPs() async {
    // IP fetching is not supported on the web platform.
    if (kIsWeb) {
      _localIPs.clear(); // Ensure the set is empty on web.
      _logger.info(
          "Local IP address fetching is not supported on the web platform.");
      return;
    }

    _localIPs.clear(); // Clear the existing list before updating.
    try {
      // List all network interfaces (excluding loopback, IPv4 only).
      for (var interface in await NetworkInterface.list(
          includeLoopback: false, type: InternetAddressType.IPv4)) {
        // Add all IPv4 addresses associated with the interface to the set.
        for (var addr in interface.addresses) {
          _localIPs.add(addr.address);
        }
      }
      _logger.info("Local IPs updated: $_localIPs");
    } catch (e) {
      // Log errors during IP fetching.
      _logger.severe("Error fetching local IPs: $e");
      _localIPs
          .clear(); // Clear the list on error to avoid incorrect filtering.
    }
  }
}
