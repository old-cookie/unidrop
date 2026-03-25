import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, MethodCall, MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unidrop/features/discovery/discovery_provider.dart';
import 'package:unidrop/features/discovery/discovery_service.dart';
import 'package:unidrop/features/server/server_service.dart';
import 'dart:io';
import 'package:unidrop/features/send/send_service.dart';
import 'package:unidrop/models/device_info.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:unidrop/features/receive/received_file_provider.dart';
import 'package:unidrop/features/receive/received_text_provider.dart';
import 'package:unidrop/widgets/received_file_dialog.dart';
import 'package:unidrop/widgets/received_text_dialog.dart';
import 'package:unidrop/models/received_file_info.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:image_editor_plus/image_editor_plus.dart';
import 'package:unidrop/pages/video_editor_page.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'package:cross_platform_video_thumbnails/cross_platform_video_thumbnails.dart';
import 'package:unidrop/pages/settings_page.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:unidrop/providers/device_selection_provider.dart';
import 'package:unidrop/providers/settings_provider.dart';
import 'package:unidrop/features/server/server_provider.dart';
import 'package:unidrop/features/server/share_link_provider.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:unidrop/pages/qr_scanner_page.dart';
import 'package:unidrop/pages/share_link_page.dart';
import 'package:logging/logging.dart'; // Import the logging package
import 'package:mime/mime.dart';
import 'package:unidrop/widgets/copyable_error_snackbar.dart';
import 'package:unidrop/utils/ip_address_utils.dart';

class _DiscoveredDeviceGroup {
  const _DiscoveredDeviceGroup({
    required this.key,
    required this.alias,
    required this.port,
    required this.devices,
  });

  final String key;
  final String alias;
  final int port;
  final List<DeviceInfo> devices;

  bool get hasMultipleIps => devices.length > 1;

  String get subtitle => devices.map((device) => device.ip).join(', ');
}

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});
  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _log = Logger('HomePage'); // Create a logger instance
  static const MethodChannel _shareChannel = MethodChannel(
    'com.oldcokie.unidrop/share',
  );
  String? _selectedFilePath;
  String? _selectedFileName;
  Uint8List? _selectedFileBytes;
  bool _isSending = false;
  bool _isShareChannelInitialized = false;
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _textController = TextEditingController();
  // Remove local _favorites list - use provider directly
  // static const String _favoritesPrefKey = 'favorite_devices';
  ProviderSubscription<ReceivedFileInfo?>? _receivedFileSubscription;
  ProviderSubscription<String?>? _receivedTextSubscription;
  DiscoveryService? _discoveryService;
  ServerService? _serverService;
  String? _localIpAddress;
  String? _scanResult;
  bool _hasShownLongPressMultiSelectHint = false;

  bool _isImageFileName(String fileName) {
    final fileNameLower = fileName.toLowerCase();
    return fileNameLower.endsWith('.jpg') ||
        fileNameLower.endsWith('.jpeg') ||
        fileNameLower.endsWith('.png') ||
        fileNameLower.endsWith('.gif') ||
        fileNameLower.endsWith('.bmp') ||
        fileNameLower.endsWith('.webp');
  }

  bool _isVideoFileName(String fileName) {
    final fileNameLower = fileName.toLowerCase();
    return fileNameLower.endsWith('.mp4') ||
        fileNameLower.endsWith('.mov') ||
        fileNameLower.endsWith('.avi') ||
        fileNameLower.endsWith('.mkv') ||
        fileNameLower.endsWith('.wmv') ||
        fileNameLower.endsWith('.m4v') ||
        fileNameLower.endsWith('.webm');
  }

  Future<void> _initializeAndroidShareReceiver() async {
    if (!(Platform.isAndroid || Platform.isIOS) || _isShareChannelInitialized) {
      return;
    }

    _isShareChannelInitialized = true;
    _shareChannel.setMethodCallHandler(_handleShareMethodCall);

    try {
      final initialSharedMedia = await _shareChannel.invokeListMethod<dynamic>(
        'getInitialSharedMedia',
      );
      await _handleSharedMediaPayload(initialSharedMedia);

      if (initialSharedMedia != null && initialSharedMedia.isNotEmpty) {
        await _shareChannel.invokeMethod<void>('clearInitialSharedMedia');
      }
    } catch (e) {
      _log.warning('Failed to initialize share receiver', e);
    }
  }

  Future<dynamic> _handleShareMethodCall(MethodCall call) async {
    if (call.method == 'onSharedMedia') {
      await _handleSharedMediaPayload(call.arguments);
    }
    return null;
  }

  List<Map<String, String?>> _parseSharedMediaPayload(dynamic payload) {
    if (payload is! List) {
      return const [];
    }

    final parsed = <Map<String, String?>>[];
    for (final item in payload) {
      if (item is! Map) {
        continue;
      }

      final path = item['path']?.toString();
      final fileName = item['fileName']?.toString();
      final mimeType = item['mimeType']?.toString();

      if (path == null ||
          path.isEmpty ||
          fileName == null ||
          fileName.isEmpty) {
        continue;
      }

      parsed.add({'path': path, 'fileName': fileName, 'mimeType': mimeType});
    }

    return parsed;
  }

  Future<void> _handleSharedMediaPayload(dynamic payload) async {
    if (!mounted) return;

    final media = _parseSharedMediaPayload(payload);
    if (media.isEmpty) {
      return;
    }

    final first = media.first;
    final path = first['path'];
    final fileName = first['fileName'];

    if (path == null || fileName == null) {
      return;
    }

    final resolvedMimeType =
        (first['mimeType'] != null && first['mimeType']!.isNotEmpty)
        ? first['mimeType']
        : (lookupMimeType(path) ?? lookupMimeType(fileName));

    final isImage =
        (resolvedMimeType?.startsWith('image/') ?? false) ||
        _isImageFileName(fileName);
    final isVideo =
        (resolvedMimeType?.startsWith('video/') ?? false) ||
        _isVideoFileName(fileName);

    if (isImage) {
      _showPhotoSendDialog(fileName: fileName, filePath: path);
      return;
    }

    if (isVideo) {
      _showVideoSendDialog(fileName: fileName, filePath: path);
      return;
    }

    _setPickedFile(path: path, name: fileName);
  }

  void _showPhotoSendDialog({
    required String fileName,
    String? filePath,
    Uint8List? fileBytes,
  }) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Send Photo'),
          content: const Text('Do you want to edit the photo before sending?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Edit Photo'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                if (!mounted) return;
                _navigateToEditor(
                  bytes: fileBytes,
                  path: filePath,
                  fileName: fileName,
                );
              },
            ),
            TextButton(
              child: const Text('Send Directly'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                if (!mounted) return;
                _setPickedFile(
                  bytes: fileBytes,
                  path: filePath,
                  name: fileName,
                );
              },
            ),
          ],
        );
      },
    );
  }

  void _showVideoSendDialog({
    required String fileName,
    String? filePath,
    Uint8List? fileBytes,
  }) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Send Video'),
          content: const Text('Do you want to edit the video before sending?'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                if (!mounted) return;
                _navigateToVideoEditor(
                  bytes: filePath == null ? fileBytes : null,
                  path: filePath,
                  fileName: fileName,
                );
              },
              child: const Text('Edit Video'),
            ),
            TextButton(
              child: const Text('Send Directly'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                if (!mounted) return;
                _setPickedFile(
                  bytes: filePath == null ? fileBytes : null,
                  path: filePath,
                  name: fileName,
                );
              },
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    // Remove _loadFavorites(); - favorites are loaded via provider
    _fetchLocalIp();
    _initializeAndroidShareReceiver();
    Future.microtask(() async {
      if (!mounted) return;
      final localRef = ref;
      _serverService = localRef.read(serverServiceProvider(2706));
      _discoveryService = localRef.read(discoveryServiceProvider);
      await _serverService!.startServer();
      if (!mounted) return;
      await _discoveryService!.startDiscovery();
      if (!mounted) return;
      _receivedFileSubscription = localRef.listenManual<ReceivedFileInfo?>(
        receivedFileProvider,
        (previous, fileInfo) {
          if (fileInfo != null) {
            if (!mounted) return;
            // Removed context capture and route check before microtask
            Future.microtask(() {
              // Check mounted *inside* microtask before using context
              if (!mounted) return;
              showDialog(
                context: context, // Use context directly after mounted check
                barrierDismissible: false,
                builder: (BuildContext dialogContext) {
                  return ReceivedFileDialog(fileInfo: fileInfo);
                },
              ).then((_) {
                if (mounted) {
                  localRef
                      .read(receivedFileProvider.notifier)
                      .clearReceivedFile();
                }
              });
            });
          }
        },
      );
      _receivedTextSubscription = localRef.listenManual<String?>(
        receivedTextProvider,
        (previous, text) {
          if (text != null) {
            if (!mounted) return;
            // Removed context capture and route check before microtask
            Future.microtask(() {
              // Check mounted *inside* microtask before using context
              if (!mounted) return;
              showDialog(
                context: context, // Use context directly after mounted check
                barrierDismissible: false,
                builder: (BuildContext dialogContext) {
                  return ReceivedTextDialog(receivedText: text);
                },
              ).then((_) {
                if (mounted) {
                  localRef.read(receivedTextProvider.notifier).setText(null);
                }
              });
            });
          }
        },
      );
    });
  }

  @override
  void dispose() {
    if (_isShareChannelInitialized) {
      _shareChannel.setMethodCallHandler(null);
      _isShareChannelInitialized = false;
    }
    _discoveryService?.stopDiscovery();
    _serverService?.stopServer();
    _receivedFileSubscription?.close();
    _receivedTextSubscription?.close();
    _ipController.dispose();
    _nameController.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _fetchLocalIp() async {
    try {
      final ip = await _resolveLocalIpAddress();
      if (mounted) {
        setState(() {
          _localIpAddress = ip;
        });
      }
    } catch (e) {
      _log.warning("Failed to get local IP", e); // Use logger
      if (mounted) {
        // Optional: show a user-facing hint when local IP is unavailable.
      }
    }
  }

  Future<String?> _resolveLocalIpAddress() async {
    final wifiIp = await NetworkInfo().getWifiIP();
    if (IpAddressUtils.isUsableIpv4(wifiIp)) {
      return wifiIp;
    }
    return IpAddressUtils.findBestLocalIpv4();
  }

  Future<Uint8List?> _generateVideoThumbnailData(
    String videoPath, {
    int maxWidth = 150,
    int quality = 25,
  }) async {
    try {
      final qualityScale = (quality / 100).clamp(0.0, 1.0).toDouble();
      final result = await CrossPlatformVideoThumbnails.generateThumbnail(
        videoPath,
        ThumbnailOptions(
          timePosition: 0,
          width: maxWidth,
          height: maxWidth,
          quality: qualityScale,
        ),
      );
      return Uint8List.fromList(result.data);
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _generateVideoThumbnailFromBytes(
    Uint8List videoBytes, {
    int maxWidth = 150,
    int quality = 25,
  }) async {
    if (kIsWeb) {
      try {
        final qualityScale = (quality / 100).clamp(0.0, 1.0).toDouble();
        final dataUri = 'data:video/mp4;base64,${base64Encode(videoBytes)}';
        final result = await CrossPlatformVideoThumbnails.generateThumbnail(
          dataUri,
          ThumbnailOptions(
            timePosition: 0,
            width: maxWidth,
            height: maxWidth,
            quality: qualityScale,
          ),
        );
        return Uint8List.fromList(result.data);
      } catch (_) {
        return null;
      }
    }

    return null;
  }

  // Remove _loadFavorites and _saveFavorites - managed by SettingsNotifier

  Future<bool> _addFavoriteManually() async {
    // Renamed to avoid conflict if needed
    final String ip = _ipController.text.trim();
    final String name = _nameController.text.trim();
    if (!mounted) return false;
    if (ip.isEmpty || name.isEmpty) {
      showCopyableSnackBar(context, 'Please enter both IP address and name.');
      return false;
    }
    final ipRegex = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$');
    if (!ipRegex.hasMatch(ip)) {
      if (!mounted) return false;
      showCopyableSnackBar(context, 'Invalid IP address format.');
      return false;
    }
    // Use the SettingsNotifier to add the favorite
    final deviceData = {
      'ip': ip,
      'name': name,
    }; // Assuming port is fixed or handled elsewhere
    // Rely on the check within addFavoriteDevice in the provider

    _log.info("Attempting to add favorite: $deviceData"); // Use logger
    final focusScope = FocusScope.of(context); // Store before async gap
    try {
      await ref.read(settingsProvider.notifier).addFavoriteDevice(deviceData);
      _log.info(
        "Successfully called addFavoriteDevice for: $deviceData",
      ); // Use logger
      if (!mounted) return false; // Check after await
      // Clear fields and unfocus after successful add
      _ipController.clear();
      _nameController.clear();
      focusScope.unfocus(); // Use stored scope
      showCopyableSnackBar(context, 'Added $name to favorites.');
      return true; // Indicate success
    } catch (e) {
      _log.severe("Error calling addFavoriteDevice", e); // Use logger
      if (!mounted) {
        // Optional: show a user-facing hint when local IP is unavailable.
      }
      showCopyableSnackBar(context, 'Error adding favorite: $e');
      return false;
    }
  }

  Future<bool> _sendSelectionToDevice(
    DeviceInfo targetDevice, {
    required bool clearSelectedFileOnSuccess,
    bool showProgressSnackBar = true,
    bool showSuccessSnackBar = true,
    bool setSendingState = true,
  }) async {
    if (!mounted) return false;
    FocusManager.instance.primaryFocus?.unfocus();
    if (setSendingState) {
      setState(() {
        _isSending = true;
      });
    }

    String? errorMessage;
    var sentSuccessfully = false;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      if (_selectedFileName != null &&
          (_selectedFilePath != null || _selectedFileBytes != null)) {
        if (showProgressSnackBar) {
          showCopyableSnackBar(
            context,
            'Sending file $_selectedFileName to ${targetDevice.alias}...',
          );
        }
        await ref
            .read(sendServiceProvider)
            .sendFile(
              targetDevice,
              _selectedFileName!,
              filePath: _selectedFilePath,
              fileBytes: _selectedFileBytes,
            );
        if (!mounted) return false;
        if (showSuccessSnackBar) {
          showCopyableSnackBar(
            context,
            'Sent $_selectedFileName successfully!',
          );
        }
        sentSuccessfully = true;

        if (clearSelectedFileOnSuccess) {
          setState(() {
            _selectedFilePath = null;
            _selectedFileName = null;
            _selectedFileBytes = null;
          });
          ref.read(deviceSelectionProvider.notifier).clearSelection();
          _hasShownLongPressMultiSelectHint = false;
        }
      } else {
        final textToSend = _textController.text.trim();
        if (textToSend.isNotEmpty) {
          if (showProgressSnackBar) {
            scaffoldMessenger.hideCurrentSnackBar();
            showCopyableSnackBar(
              context,
              'Sending text to ${targetDevice.alias}...',
            );
          }
          try {
            await ref
                .read(sendServiceProvider)
                .sendText(targetDevice, textToSend);
            if (!mounted) return false;
            if (showSuccessSnackBar) {
              scaffoldMessenger.hideCurrentSnackBar();
              showCopyableSnackBar(context, 'Text sent successfully!');
            }
            _textController.clear();
            sentSuccessfully = true;
          } catch (e) {
            errorMessage = e.toString();
          }
        } else {
          showCopyableSnackBar(
            context,
            'Please enter text or select a file to send.',
          );
          return false;
        }
      }
    } catch (e) {
      errorMessage ??= e.toString();
    } finally {
      if (mounted) {
        if (errorMessage != null) {
          scaffoldMessenger.hideCurrentSnackBar();
          showCopyableSnackBar(context, 'Error sending: $errorMessage');
        }
        if (setSendingState) {
          setState(() {
            _isSending = false;
          });
        }
      }
    }
    return sentSuccessfully;
  }

  Future<void> _initiateSend(DeviceInfo targetDevice) async {
    await _sendSelectionToDevice(
      targetDevice,
      clearSelectedFileOnSuccess: true,
    );
  }

  Future<void> _handleBatchSend(
    List<_DiscoveredDeviceGroup> groupedDiscoveredDevices,
  ) async {
    if (!mounted || _isSending) return;
    if (_selectedFileName == null ||
        (_selectedFilePath == null && _selectedFileBytes == null)) {
      showCopyableSnackBar(context, 'Please select a file first.');
      return;
    }

    final selectedKeys = ref.read(deviceSelectionProvider);
    if (selectedKeys.isEmpty) {
      showCopyableSnackBar(context, 'Long press devices to select for batch.');
      return;
    }

    final targets = <DeviceInfo>[];
    for (final group in groupedDiscoveredDevices) {
      for (final device in group.devices) {
        if (selectedKeys.contains(_selectionKeyForDevice(device))) {
          targets.add(device);
        }
      }
    }

    if (targets.isEmpty) {
      ref.read(deviceSelectionProvider.notifier).clearSelection();
      showCopyableSnackBar(
        context,
        'Selected devices are no longer available.',
      );
      return;
    }

    final fileName = _selectedFileName;
    showCopyableSnackBar(
      context,
      'Sending $fileName to ${targets.length} devices...',
    );

    setState(() {
      _isSending = true;
    });

    var successCount = 0;
    var failedCount = 0;
    for (final target in targets) {
      final success = await _sendSelectionToDevice(
        target,
        clearSelectedFileOnSuccess: false,
        showProgressSnackBar: false,
        showSuccessSnackBar: false,
        setSendingState: false,
      );
      if (!mounted) return;
      if (success) {
        successCount++;
      } else {
        failedCount++;
      }
    }

    if (!mounted) return;
    setState(() {
      _selectedFilePath = null;
      _selectedFileName = null;
      _selectedFileBytes = null;
      _isSending = false;
    });
    ref.read(deviceSelectionProvider.notifier).clearSelection();
    _hasShownLongPressMultiSelectHint = false;

    if (failedCount == 0) {
      showCopyableSnackBar(
        context,
        'Sent to $successCount devices successfully!',
      );
    } else {
      showCopyableSnackBar(
        context,
        'Batch done. Success: $successCount, Failed: $failedCount.',
      );
    }
  }

  Future<void> _openShareLinkPage() async {
    if (!mounted) return;
    final textToShare = _textController.text.trim();
    final hasSelectedFile =
        _selectedFileName != null &&
        (_selectedFilePath != null || _selectedFileBytes != null);
    if (!hasSelectedFile && textToShare.isEmpty) {
      showCopyableSnackBar(context, 'Please select a file or enter text.');
      return;
    }

    final resolvedIp = _localIpAddress ?? await _resolveLocalIpAddress();
    if (!mounted) return;
    if (resolvedIp == null || resolvedIp.isEmpty) {
      showCopyableSnackBar(context, 'Cannot find local IP address.');
      return;
    }

    if (_localIpAddress != resolvedIp) {
      setState(() {
        _localIpAddress = resolvedIp;
      });
    }

    late final String fileName;
    late final String mimeType;
    String? sharedText;
    String? filePath;
    Uint8List? fileBytes;
    int fileSize;

    if (hasSelectedFile) {
      fileName = _selectedFileName!;
      filePath = _selectedFilePath;
      fileBytes = filePath == null ? _selectedFileBytes : null;
      if (fileBytes != null) {
        fileSize = fileBytes.length;
      } else {
        try {
          fileSize = await File(filePath!).length();
        } catch (e) {
          if (!mounted) return;
          showCopyableSnackBar(context, 'Cannot access selected file: $e');
          return;
        }
      }
      final detectedMime = lookupMimeType(
        filePath ?? fileName,
        headerBytes: fileBytes,
      );
      mimeType = _resolveShareMimeType(fileName, detectedMime);
    } else {
      fileName = 'unidrop_text_${DateTime.now().millisecondsSinceEpoch}.txt';
      sharedText = textToShare;
      fileBytes = Uint8List.fromList(utf8.encode(textToShare));
      filePath = null;
      fileSize = fileBytes.length;
      mimeType = 'text/plain; charset=utf-8';
    }

    ref
        .read(shareFileProvider.notifier)
        .setShareFile(
          fileName: fileName,
          mimeType: mimeType,
          fileSize: fileSize,
          senderAlias: ref.read(deviceAliasProvider).trim(),
          filePath: filePath,
          fileBytes: fileBytes,
          sharedText: sharedText,
        );

    if (!mounted) return;
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ShareLinkPage(localIpAddress: resolvedIp),
        ),
      );
    } finally {
      ref.read(shareFileProvider.notifier).clear();
    }
  }

  String _resolveShareMimeType(String fileName, String? detectedMime) {
    if (detectedMime != null && detectedMime != 'application/octet-stream') {
      return detectedMime;
    }

    final lower = fileName.toLowerCase();
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.heic') ||
        lower.endsWith('.heif')) {
      return 'image/*';
    }

    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.wmv')) {
      return 'video/*';
    }

    return detectedMime ?? 'application/octet-stream';
  }

  Future<void> _manualRefreshDiscovery() async {
    if (!mounted) return;
    showCopyableSnackBar(context, 'Refreshing devices...');

    try {
      await _fetchLocalIp();
      if (!mounted) return;
      final DiscoveryService? discoveryService =
          _discoveryService ?? ref.read(discoveryServiceProvider);
      if (discoveryService == null) {
        showCopyableSnackBar(context, 'Discovery service is not ready yet.');
        return;
      }
      await discoveryService.stopDiscovery();
      await discoveryService.startDiscovery();
      if (!mounted) return;
      showCopyableSnackBar(context, 'Device discovery refreshed.');
    } catch (e) {
      _log.severe('Error during manual device refresh', e);
      if (!mounted) return;
      showCopyableSnackBar(context, 'Refresh failed: $e');
    }
  }

  List<_DiscoveredDeviceGroup> _groupDiscoveredDevices(
    List<DeviceInfo> discoveredDevices,
  ) {
    final groups = <String, List<DeviceInfo>>{};

    for (final device in discoveredDevices) {
      final key = device.deviceId?.isNotEmpty == true
          ? 'id:${device.deviceId}'
          : 'alias:${device.alias}:port:${device.port}';
      groups.putIfAbsent(key, () => <DeviceInfo>[]).add(device);
    }

    final groupedDevices = groups.entries.map((entry) {
      final devices = [...entry.value]
        ..sort((left, right) => left.ip.compareTo(right.ip));
      final firstDevice = devices.first;
      return _DiscoveredDeviceGroup(
        key: entry.key,
        alias: firstDevice.alias,
        port: firstDevice.port,
        devices: devices,
      );
    }).toList()..sort((left, right) => left.alias.compareTo(right.alias));

    return groupedDevices;
  }

  String _selectionKeyForDevice(DeviceInfo device) {
    final normalizedDeviceId = device.deviceId?.isNotEmpty == true
        ? device.deviceId
        : '${device.alias}:${device.port}';
    return 'device:$normalizedDeviceId:ip:${device.ip}:port:${device.port}';
  }

  bool _groupContainsSelectedDevice(
    _DiscoveredDeviceGroup group,
    Set<String> selectedKeys,
  ) {
    for (final device in group.devices) {
      if (selectedKeys.contains(_selectionKeyForDevice(device))) {
        return true;
      }
    }
    return false;
  }

  int _selectedDeviceCountInGroup(
    _DiscoveredDeviceGroup group,
    Set<String> selectedKeys,
  ) {
    var count = 0;
    for (final device in group.devices) {
      if (selectedKeys.contains(_selectionKeyForDevice(device))) {
        count++;
      }
    }
    return count;
  }

  Future<DeviceInfo?> _pickDeviceFromGroup(
    _DiscoveredDeviceGroup group, {
    required String title,
  }) async {
    return showDialog<DeviceInfo>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 360,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: group.devices.length,
            itemBuilder: (dialogContext, index) {
              final device = group.devices[index];
              return ListTile(
                leading: const Icon(Icons.router),
                title: Text(device.ip),
                subtitle: Text('Port ${device.port}'),
                onTap: () => Navigator.of(dialogContext).pop(device),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _handleDiscoveredDeviceTap(_DiscoveredDeviceGroup group) async {
    if (group.devices.length == 1) {
      await _initiateSend(group.devices.first);
      return;
    }

    final selectedDevice = await _pickDeviceFromGroup(
      group,
      title: 'Choose IP for ${group.alias}',
    );

    if (!mounted || selectedDevice == null) return;
    await _initiateSend(selectedDevice);
  }

  Widget _buildSelectedFileThumbnail() {
    if (_selectedFileName == null) {
      return const SizedBox.shrink();
    }
    final fileNameLower = _selectedFileName!.toLowerCase();
    final isImage =
        fileNameLower.endsWith('.jpg') ||
        fileNameLower.endsWith('.jpeg') ||
        fileNameLower.endsWith('.png') ||
        fileNameLower.endsWith('.gif') ||
        fileNameLower.endsWith('.bmp') ||
        fileNameLower.endsWith('.webp');
    final isVideo =
        fileNameLower.endsWith('.mp4') ||
        fileNameLower.endsWith('.mov') ||
        fileNameLower.endsWith('.avi') ||
        fileNameLower.endsWith('.mkv') ||
        fileNameLower.endsWith('.wmv');
    Widget thumbnailWidget;
    if (isImage) {
      if (_selectedFileBytes != null) {
        thumbnailWidget = Image.memory(_selectedFileBytes!, fit: BoxFit.cover);
      } else if (_selectedFilePath != null) {
        thumbnailWidget = Image.file(
          File(_selectedFilePath!),
          fit: BoxFit.cover,
        );
      } else {
        thumbnailWidget = const Icon(Icons.image_not_supported, size: 50);
      }
    } else if (isVideo) {
      if (_selectedFilePath != null || _selectedFileBytes != null) {
        thumbnailWidget = FutureBuilder<Uint8List?>(
          future: _selectedFilePath != null
              ? _generateVideoThumbnailData(
                  _selectedFilePath!,
                  maxWidth: 150,
                  quality: 25,
                )
              : _generateVideoThumbnailFromBytes(
                  _selectedFileBytes!,
                  maxWidth: 150,
                  quality: 25,
                ),
          builder: (BuildContext context, AsyncSnapshot<Uint8List?> snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              _log.warning(
                'Error generating video thumbnail',
                snapshot.error,
              ); // Use logger
              return const Icon(Icons.video_file_outlined, size: 50);
            } else if (snapshot.hasData && snapshot.data != null) {
              return Image.memory(snapshot.data!, fit: BoxFit.cover);
            } else {
              return const Icon(Icons.video_file_outlined, size: 50);
            }
          },
        );
      } else {
        thumbnailWidget = const Icon(Icons.video_file_outlined, size: 50);
      }
    } else {
      // Add the missing else block for other file types
      thumbnailWidget = const Icon(Icons.insert_drive_file_outlined, size: 50);
    }
    // Move the return Padding inside the method
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Selected: $_selectedFileName',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Stack(
            children: [
              Container(
                height: 100,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(4.0),
                ),
                alignment: Alignment.center,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4.0),
                  child: thumbnailWidget,
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedFilePath = null;
                      _selectedFileName = null;
                      _selectedFileBytes = null;
                    });
                    ref.read(deviceSelectionProvider.notifier).clearSelection();
                    _hasShownLongPressMultiSelectHint = false;
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(2),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<DeviceInfo> discoveredDevices = ref.watch(
      discoveredDevicesProvider,
    );
    final groupedDiscoveredDevices = _groupDiscoveredDevices(discoveredDevices);
    final selectedDeviceKeys = ref.watch(deviceSelectionProvider);
    final alias = ref.watch(deviceAliasProvider);
    final serverState = ref.watch(serverStateProvider);
    String? qrData;
    if (serverState.isRunning &&
        serverState.port != null &&
        _localIpAddress != null) {
      final qrInfo = {
        'ip': _localIpAddress,
        'port': serverState.port,
        'alias': alias,
      };
      qrData = jsonEncode(qrInfo);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Unidrop'),
        actions: [
          IconButton(
            icon: const Icon(Icons.star),
            onPressed: _showFavoritesDialog,
            tooltip: 'Show Favorites',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _manualRefreshDiscovery,
            tooltip: 'Refresh Devices',
          ),
          if (Platform.isWindows)
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () {
                if (!mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SettingsPage()),
                );
              },
              tooltip: 'Settings',
            )
          else
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: 'More Options',
              onSelected: (String result) {
                switch (result) {
                  case 'scan_qr':
                    _scanQrCode();
                    break;
                  case 'settings':
                    if (!mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SettingsPage(),
                      ),
                    );
                    break;
                }
              },
              itemBuilder: (BuildContext context) {
                final List<PopupMenuEntry<String>> items = [];

                bool needsDivider = false;

                items.add(
                  const PopupMenuItem<String>(
                    value: 'scan_qr',
                    child: ListTile(
                      leading: Icon(Icons.qr_code_scanner),
                      title: Text('Scan QR'),
                    ),
                  ),
                );
                needsDivider = true;

                if (needsDivider) items.add(const PopupMenuDivider());
                items.add(
                  const PopupMenuItem<String>(
                    value: 'settings',
                    child: ListTile(
                      leading: Icon(Icons.settings),
                      title: Text('Settings'),
                    ),
                  ),
                );

                return items;
              },
            ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  if (qrData != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Center(
                        child: GestureDetector(
                          onLongPress: () {
                            final ipToCopy = _localIpAddress;
                            if (ipToCopy == null || ipToCopy.isEmpty) {
                              if (!mounted) return;
                              showCopyableSnackBar(
                                context,
                                'No IP available to copy.',
                              );
                              return;
                            }
                            Clipboard.setData(ClipboardData(text: ipToCopy));
                            showCopyableSnackBar(
                              context,
                              'Copied IP: $ipToCopy',
                            );
                          },
                          child: Container(
                            color: Colors.white,
                            padding: const EdgeInsets.all(8.0),
                            child: SizedBox(
                              width: 150,
                              height: 150,
                              child: PrettyQrView.data(
                                data: qrData,
                                decoration: const PrettyQrDecoration(
                                  shape: PrettyQrSmoothSymbol(
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Visibility(
                    // Hide text field when a file is selected
                    visible: _selectedFileName == null,
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _textController,
                            maxLines: null,
                            onChanged: (_) {
                              if (!mounted) return;
                              setState(() {});
                            },
                            onTapOutside: (_) =>
                                FocusManager.instance.primaryFocus?.unfocus(),
                            decoration: const InputDecoration(
                              labelText: 'Enter Text to Send',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: 4.0,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Discovered Devices (${groupedDiscoveredDevices.length}):',
                ),
              ),
            ),
            Expanded(
              child: discoveredDevices.isEmpty
                  ? const Center(child: Text('Searching for devices...'))
                  : ListView.builder(
                      itemCount: groupedDiscoveredDevices.length,
                      itemBuilder: (context, index) {
                        final deviceGroup = groupedDiscoveredDevices[index];
                        final isSelected = _groupContainsSelectedDevice(
                          deviceGroup,
                          selectedDeviceKeys,
                        );
                        final selectedCount = _selectedDeviceCountInGroup(
                          deviceGroup,
                          selectedDeviceKeys,
                        );
                        return ListTile(
                          leading: _isSending
                              ? const CircularProgressIndicator()
                              : const Icon(Icons.devices),
                          selected: isSelected,
                          title: Text(deviceGroup.alias),
                          subtitle: Text(
                            deviceGroup.hasMultipleIps
                                ? '${deviceGroup.subtitle} (${deviceGroup.devices.length} IPs)'
                                : '${deviceGroup.devices.first.ip}:${deviceGroup.port}',
                          ),
                          trailing: (isSelected || deviceGroup.hasMultipleIps)
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (selectedCount > 0) ...[
                                      const Icon(
                                        Icons.check_circle,
                                        color: Colors.green,
                                      ),
                                      const SizedBox(width: 4),
                                      Text('$selectedCount'),
                                    ],
                                    if (deviceGroup.hasMultipleIps)
                                      const Icon(Icons.arrow_drop_down),
                                  ],
                                )
                              : null,
                          onTap: _isSending
                              ? null
                              : () => _handleDiscoveredDeviceTap(deviceGroup),
                          onLongPress: (_isSending || _selectedFileName == null)
                              ? null
                              : () async {
                                  DeviceInfo? target;
                                  if (deviceGroup.devices.length == 1) {
                                    target = deviceGroup.devices.first;
                                  } else {
                                    target = await _pickDeviceFromGroup(
                                      deviceGroup,
                                      title:
                                          'Choose IP to select for ${deviceGroup.alias}',
                                    );
                                  }
                                  if (!mounted ||
                                      !this.context.mounted ||
                                      target == null) {
                                    return;
                                  }
                                  final key = _selectionKeyForDevice(target);
                                  final notifier = ref.read(
                                    deviceSelectionProvider.notifier,
                                  );
                                  notifier.toggleSelection(key);

                                  final isNowSelected = ref
                                      .read(deviceSelectionProvider)
                                      .contains(key);
                                  showCopyableSnackBar(
                                    this.context,
                                    isNowSelected
                                        ? 'Selected ${target.alias} (${target.ip}) for batch.'
                                        : 'Removed ${target.alias} (${target.ip}) from batch.',
                                  );
                                  if (!_hasShownLongPressMultiSelectHint) {
                                    _hasShownLongPressMultiSelectHint = true;
                                    showCopyableSnackBar(
                                      this.context,
                                      'Device selected. Tap "Send to N" for batch send.',
                                    );
                                  }
                                },
                        );
                      },
                    ),
            ),
            _buildSelectedFileThumbnail(),
            Visibility(
              // Hide when keyboard is visible
              visible: MediaQuery.of(context).viewInsets.bottom == 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  16.0,
                  16.0,
                  16.0,
                  48.0,
                ), // Adjusted bottom padding if needed when hidden
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.send),
                      label: const Text('Send'),
                      onPressed: () async {
                        if (!mounted) return;
                        if (Platform.isWindows || Platform.isMacOS) {
                          await _pickFile(context, FileType.any);
                          return;
                        }

                        showModalBottomSheet(
                          context: context,
                          builder: (BuildContext bc) {
                            return SafeArea(
                              child: Wrap(
                                children: <Widget>[
                                  ListTile(
                                    leading: const Icon(Icons.photo),
                                    title: const Text('Photo'),
                                    onTap: () async {
                                      Navigator.pop(context);
                                      await _pickFile(context, FileType.image);
                                    },
                                  ),
                                  if (!Platform.isMacOS)
                                    ListTile(
                                      leading: const Icon(Icons.videocam),
                                      title: const Text('Video'),
                                      onTap: () async {
                                        Navigator.pop(context);
                                        await _pickFile(
                                          context,
                                          FileType.video,
                                        );
                                      },
                                    ),
                                  ListTile(
                                    leading: const Icon(Icons.attach_file),
                                    title: const Text('File'),
                                    onTap: () async {
                                      Navigator.pop(context);
                                      await _pickFile(context, FileType.any);
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                    if (selectedDeviceKeys.isNotEmpty &&
                        _selectedFileName != null)
                      ElevatedButton.icon(
                        icon: const Icon(Icons.send_to_mobile),
                        label: Text('Send to ${selectedDeviceKeys.length}'),
                        onPressed: _isSending
                            ? null
                            : () => _handleBatchSend(groupedDiscoveredDevices),
                      ),
                    if (_selectedFileName != null ||
                        _textController.text.trim().isNotEmpty)
                      ElevatedButton.icon(
                        icon: const Icon(Icons.link),
                        label: const Text('Send with link'),
                        onPressed: _isSending ? null : _openShareLinkPage,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showFavoritesDialog() async {
    // No need to await _loadFavorites(); - read directly from provider
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        // Use Consumer instead of StatefulBuilder to react to provider changes
        return Consumer(
          builder: (context, ref, child) {
            // Read the current favorites list from the provider
            final favoritesList = ref.watch(favoriteDevicesProvider);
            _log.fine(
              "Favorites Dialog Consumer rebuilt. Received list: $favoritesList",
            ); // Use logger (fine level for rebuilds)
            // Convert List<Map<String, String>> to List<DeviceInfo> for compatibility
            // Assuming a fixed port or handle differently if port varies
            final favorites = favoritesList
                .map(
                  (fav) => DeviceInfo(
                    ip: fav['ip']!,
                    port: 2706,
                    alias: fav['name']!,
                  ),
                )
                .toList();

            return AlertDialog(
              title: const Text('Favorite Devices'),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: _ipController,
                        decoration: const InputDecoration(
                          labelText: 'IP Address',
                          hintText: 'e.g., 192.168.1.100',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Device Name',
                          hintText: 'e.g., My Laptop',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Add Favorite'),
                        onPressed: () async {
                          // Call the updated manual add method
                          await _addFavoriteManually();
                          // No need for setDialogState, Consumer rebuilds automatically
                        },
                      ),
                      const Divider(height: 24),
                      favorites
                              .isEmpty // Use the list from the provider
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 16.0),
                                child: Text('No favorites added yet.'),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: favorites
                                  .length, // Use the list from the provider
                              itemBuilder: (context, index) {
                                if (index < 0 || index >= favorites.length) {
                                  // Use the list from the provider
                                  return const SizedBox.shrink();
                                }
                                final device =
                                    favorites[index]; // Use the list from the provider
                                // Convert DeviceInfo back to Map for removal function if needed
                                final deviceData = {
                                  'ip': device.ip,
                                  'name': device.alias,
                                };
                                return ListTile(
                                  leading: const Icon(Icons.star),
                                  title: Text(device.alias),
                                  subtitle: Text('${device.ip}:${device.port}'),
                                  trailing: IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                    ),
                                    tooltip: 'Remove Favorite',
                                    onPressed: () async {
                                      _log.info(
                                        "Attempting to remove favorite with data: $deviceData",
                                      ); // Use logger
                                      final removedDeviceAlias = device.alias;
                                      // No need for mounted check here before await
                                      try {
                                        // Call the provider's remove method
                                        await ref
                                            .read(settingsProvider.notifier)
                                            .removeFavoriteDevice(deviceData);
                                        _log.info(
                                          "Successfully called removeFavoriteDevice for: $deviceData",
                                        ); // Use logger
                                        if (!context.mounted) {
                                          return; // Check after await
                                        }
                                        showCopyableSnackBar(
                                          context,
                                          'Removed $removedDeviceAlias from favorites.',
                                        );
                                      } catch (e) {
                                        _log.severe(
                                          "Error calling removeFavoriteDevice",
                                          e,
                                        ); // Use logger
                                        if (!context.mounted) {
                                          return; // Check after await (though technically before context use here)
                                        }
                                        showCopyableSnackBar(
                                          context,
                                          'Error removing favorite: $e',
                                        );
                                      }
                                      // No need for setDialogState
                                    },
                                  ),
                                  onTap: _isSending
                                      ? null
                                      : () {
                                          Navigator.of(context).pop();
                                          if (!mounted) return;
                                          _initiateSend(device);
                                        },
                                );
                              },
                            ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Close'),
                  onPressed: () {
                    _ipController.clear();
                    _nameController.clear();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          }, // End Consumer builder
        );
      },
    );
  }

  Future<void> _pickFile(BuildContext context, FileType fileType) async {
    bool permissionGranted = false;
    String? permissionTypeDenied;
    if (Platform.isAndroid) {
      if (!mounted) return;
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (!mounted) return;
      final sdkInt = androidInfo.version.sdkInt;
      List<Permission> permissionsToRequest = [];
      if (sdkInt >= 33) {
        if (fileType == FileType.image) {
          permissionsToRequest.add(Permission.photos);
        }
        if (fileType == FileType.video) {
          permissionsToRequest.add(Permission.videos);
        }
        if (permissionsToRequest.isEmpty) {
          permissionGranted = true;
        }
      } else {
        permissionsToRequest.add(Permission.storage);
      }
      if (permissionsToRequest.isNotEmpty) {
        if (!mounted) return;
        Map<Permission, PermissionStatus> statuses = await permissionsToRequest
            .request();
        if (!mounted) return;
        permissionGranted = statuses.values.every((status) => status.isGranted);
        if (!permissionGranted) {
          permissionTypeDenied = statuses.entries
              .firstWhere((entry) => !entry.value.isGranted)
              .key
              .toString()
              .split('.')
              .last;
        }
      }
    } else if (Platform.isIOS) {
      if (fileType == FileType.image || fileType == FileType.video) {
        if (!mounted) return;
        var status = await Permission.photos.request();
        if (!mounted) return;
        permissionGranted = status.isGranted || status.isLimited;
        if (!permissionGranted) permissionTypeDenied = 'photos';
      } else {
        permissionGranted = true;
      }
    } else {
      permissionGranted = true;
    }

    if (!mounted) return; // Check mounted *after* async permission requests
    if (!context.mounted) return;

    // Removed ScaffoldMessenger capture here.

    if (!permissionGranted) {
      // Use context directly here, guarded by the 'mounted' check above.
      showCopyableSnackBar(
        context,
        '${permissionTypeDenied ?? 'Required'} permission denied',
      );
      return;
    }

    // ScaffoldMessenger will be captured inside the catch block if needed, after its own mounted check.
    try {
      // No context use before await here
      setState(() {
        _selectedFilePath = null;
        _selectedFileName = null;
        _selectedFileBytes = null;
      });
      ref.read(deviceSelectionProvider.notifier).clearSelection();
      _hasShownLongPressMultiSelectHint = false;
      if (!mounted) return;
      final bool shouldLoadBytes = kIsWeb || fileType == FileType.image;
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: fileType,
        withData: shouldLoadBytes,
      );
      if (!mounted) return;
      if (!context.mounted) return;
      if (result != null && result.files.isNotEmpty) {
        PlatformFile file = result.files.single;
        _log.info(
          'FilePicker result on native: Name: ${file.name}, Path: ${file.path}, Bytes: ${file.bytes?.length}',
        ); // Use logger
        final String fileName = file.name;
        final Uint8List? fileBytes = file.bytes;
        final String? filePath = file.path;
        final bool isDetectedImage = _isImageFileName(fileName);
        final bool isDetectedVideo = _isVideoFileName(fileName);
        final bool shouldHandleAsImage =
            fileType == FileType.image ||
            (fileType == FileType.any && isDetectedImage);
        final bool shouldHandleAsVideo =
            fileType == FileType.video ||
            (fileType == FileType.any && isDetectedVideo);

        if (shouldHandleAsImage && (fileBytes != null || filePath != null)) {
          _showPhotoSendDialog(
            fileName: fileName,
            filePath: filePath,
            fileBytes: fileBytes,
          );
        } else if (shouldHandleAsVideo &&
            (fileBytes != null || filePath != null)) {
          _showVideoSendDialog(
            fileName: fileName,
            filePath: filePath,
            fileBytes: fileBytes,
          );
        } else if (fileBytes != null) {
          _setPickedFile(bytes: fileBytes, path: null, name: fileName);
        } else if (filePath != null) {
          _setPickedFile(bytes: null, path: filePath, name: fileName);
        } else {
          _log.warning(
            'File picking failed: No bytes or path available.',
          ); // Use logger
          if (!mounted) return;
          showCopyableSnackBar(context, 'Failed to access selected file.');
        }
      } else {
        _log.info('File picking cancelled.'); // Use logger
      }
    } catch (e) {
      _log.severe('Error picking file', e); // Use logger
      // Check mounted *after* the async gap and *before* using context.
      if (!mounted) return;
      if (!context.mounted) return;
      // Capture ScaffoldMessenger *after* the await and mounted check.
      showCopyableSnackBar(context, 'Error picking file: $e');
    }
  }

  Future<void> _navigateToEditor({
    Uint8List? bytes,
    String? path,
    required String fileName,
  }) async {
    Uint8List? imageBytes = bytes;
    if (imageBytes == null && path != null) {
      try {
        // No context use before await
        imageBytes = await File(path).readAsBytes();
      } catch (e) {
        _log.severe('Error reading image file from path', e); // Use logger
        if (!mounted) return; // Check after await
        showCopyableSnackBar(context, 'Error reading image file: $e');
        return;
      }
    }
    if (!mounted) return;
    // No await before this context use
    if (imageBytes == null) {
      showCopyableSnackBar(
        context,
        'Cannot edit photo: No image data available.',
      );
      return;
    }
    if (!mounted) return;
    final Uint8List? editedImageBytes = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(builder: (context) => ImageEditor(image: imageBytes!)),
    );
    if (!mounted) return;
    if (editedImageBytes != null) {
      _log.info(
        'Image editing complete. Got ${editedImageBytes.length} bytes.',
      ); // Use logger
      final editedFileName = 'edited_$fileName';
      _setPickedFile(bytes: editedImageBytes, path: null, name: editedFileName);
    } else {
      _log.info('Image editing cancelled.'); // Use logger
      setState(() {
        _selectedFilePath = null;
        _selectedFileName = null;
        _selectedFileBytes = null;
      });
      ref.read(deviceSelectionProvider.notifier).clearSelection();
      _hasShownLongPressMultiSelectHint = false;
    }
  }

  Future<void> _navigateToVideoEditor({
    Uint8List? bytes,
    String? path,
    required String fileName,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      _log.warning(
        'Video editing is currently only supported on Android and iOS.',
      );
      showCopyableSnackBar(
        context,
        'Video editing is currently only supported on Android and iOS.',
      );
      return;
    }

    String? videoPath = path;
    File? tempFile;
    // setState is safe here
    setState(() {
      _isSending = true;
    });
    if (videoPath == null && bytes != null) {
      try {
        // No context use before await
        final tempDir = await getTemporaryDirectory();
        final String tempFileName =
            '${DateTime.now().millisecondsSinceEpoch}_$fileName';
        tempFile = File('${tempDir.path}/$tempFileName');
        await tempFile.writeAsBytes(bytes);
        videoPath = tempFile.path;
        _log.info(
          'Saved video bytes to temporary file: $videoPath',
        ); // Use logger
      } catch (e) {
        _log.severe(
          'Error saving video bytes to temporary file',
          e,
        ); // Use logger
        if (!mounted) return; // Check after await
        showCopyableSnackBar(context, 'Error preparing video for editing: $e');
        // Ensure _isSending is reset on error before returning
        setState(() {
          _isSending = false;
        });
        return;
      }
    }
    if (!mounted) return;
    // No await before this context use
    if (videoPath == null) {
      showCopyableSnackBar(
        context,
        'Cannot edit video: No video file path available.',
      );
      setState(() {
        _isSending = false;
      }); // Reset sending state
      return;
    }

    final File videoFile = File(videoPath);
    if (!mounted) return;
    final ExportConfig? exportConfig = await Navigator.push<ExportConfig?>(
      context,
      MaterialPageRoute(
        builder: (context) => VideoEditorScreen(file: videoFile),
      ),
    );

    // Handle temp file deletion after navigation completes
    if (tempFile != null) {
      try {
        await tempFile.delete();
        _log.info(
          'Deleted temporary video file: ${tempFile.path}',
        ); // Use logger
      } catch (e) {
        _log.warning('Error deleting temporary video file', e); // Use logger
        // Decide if this error needs user notification
      }
    }

    if (!mounted) return; // Check after Navigator.push and tempFile.delete

    if (exportConfig != null) {
      _log.info('Video editing confirmed via pro_video_editor.');
      _log.info('Task ID: ${exportConfig.taskId}');
      _log.info('Output Path: ${exportConfig.outputPath}');
      setState(() {
        _isSending = false;
      });
      _setPickedFile(
        bytes: null,
        path: exportConfig.outputPath,
        name: 'edited_$fileName',
      );
    } else {
      // This block runs if Navigator.push returned null (editing cancelled)
      _log.info('Video editing cancelled.'); // Use logger
      setState(() {
        _isSending = false;
      });
    }
  }

  void _setPickedFile({Uint8List? bytes, String? path, required String name}) {
    if (!mounted) return;
    setState(() {
      _selectedFileBytes = path == null ? bytes : null;
      _selectedFilePath = path;
      _selectedFileName = name;
    });
    ref.read(deviceSelectionProvider.notifier).clearSelection();
    _hasShownLongPressMultiSelectHint = false;
    _log.info(
      'Selected file: $name ${bytes != null ? "(from bytes)" : "(from path)"}',
    ); // Use logger
    if (!mounted) return; // Check before using context
    showCopyableSnackBar(
      context,
      'Selected: $name. Tap a device to send. Long press to multi-select devices.',
    );
  }

  Future<void> _scanQrCode() async {
    if (!mounted) return;
    if (Platform.isWindows) {
      showCopyableSnackBar(
        context,
        'QR Code scanning via camera is not supported on Windows.',
      );
      return;
    }
    try {
      if (!mounted) return;
      final currentContext = context;
      final String? scanResult = await Navigator.push<String>(
        currentContext,
        MaterialPageRoute(builder: (context) => const QrScannerPage()),
      );
      if (!mounted) return; // Check after await
      if (scanResult == null) {
        _log.info('QR Code scan cancelled or failed.'); // Use logger
        return;
      }
      setState(() {
        _scanResult = scanResult;
      });
      _log.info('QR Code Scanned: $_scanResult'); // Use logger
      try {
        final Map<String, dynamic> data = jsonDecode(_scanResult!);
        final String? ip = data['ip'] as String?;
        final int? port = data['port'] as int?; // Keep port if available in QR
        final String? alias = data['alias'] as String?;
        if (ip != null && alias != null) {
          // Port might be optional or fixed
          final scannedDevice = DeviceInfo(
            ip: ip,
            port: port ?? 2706,
            alias: alias,
          ); // Use default port if missing
          final deviceData = {'ip': ip, 'name': alias}; // Data for provider
          if (!mounted) return;
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('Device Found: ${scannedDevice.alias}'),
              content: Text(
                'IP: ${scannedDevice.ip}:${scannedDevice.port}\n\nSend current selection or add to favorites?',
              ),
              actions: [
                TextButton(
                  child: const Text('Add Favorite'),
                  onPressed: () async {
                    // Store context before async operations
                    final dialogContext = context;
                    Navigator.of(dialogContext).pop();
                    // Use provider to add favorite
                    await ref
                        .read(settingsProvider.notifier)
                        .addFavoriteDevice(deviceData);
                    if (!mounted) return; // Check after await
                    if (!currentContext.mounted) return;
                    showCopyableSnackBar(
                      currentContext,
                      'Added ${scannedDevice.alias} to favorites.',
                    );
                  },
                ),
                TextButton(
                  child: const Text('Send'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    _initiateSend(scannedDevice);
                  },
                ),
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          );
        } else {
          throw const FormatException(
            'Invalid QR code data format (missing ip, port, or alias).',
          );
        }
      } catch (e) {
        _log.severe('Error processing scanned QR code', e); // Use logger
        if (!mounted) return; // Check before context use
        showCopyableSnackBar(
          context,
          'Invalid QR data. Scanned: "$_scanResult"',
        );
      }
    } catch (e) {
      _log.severe('Error during QR scan or processing', e); // Use logger
      if (!mounted) return; // Check before context use
      showCopyableSnackBar(context, 'Error scanning QR code: $e');
    }
  }
}
