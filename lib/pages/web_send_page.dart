import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:cross_platform_video_thumbnails/cross_platform_video_thumbnails.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_editor_plus/image_editor_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unidrop/features/send/send_service.dart';
import 'package:unidrop/models/device_info.dart';
import 'package:unidrop/widgets/copyable_error_snackbar.dart';

class _TargetEntry {
  _TargetEntry({required this.alias, required this.ip, required this.port})
    : selected = true;

  final String alias;
  final String ip;
  final int port;
  bool selected;

  DeviceInfo toDeviceInfo() => DeviceInfo(ip: ip, port: port, alias: alias);
}

class WebSendPage extends ConsumerStatefulWidget {
  const WebSendPage({super.key});

  @override
  ConsumerState<WebSendPage> createState() => _WebSendPageState();
}

class _WebSendPageState extends ConsumerState<WebSendPage> {
  static const String _storageKey = 'unidrop_web_targets';
  static const int _defaultPort = 2706;

  final TextEditingController _aliasController = TextEditingController();
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _textController = TextEditingController();

  final List<_TargetEntry> _targets = [];
  Uint8List? _selectedFileBytes;
  String? _selectedFileName;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadTargetsFromLocalStorage());
  }

  @override
  void dispose() {
    _aliasController.dispose();
    _ipController.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _addTarget() {
    final inputAlias = _aliasController.text.trim();
    final ip = _ipController.text.trim();
    final port = _defaultPort;
    final alias = inputAlias.isEmpty
        ? 'Device ${_targets.length + 1}'
        : inputAlias;

    if (ip.isEmpty) {
      showCopyableSnackBar(context, 'Please enter valid IP.');
      return;
    }

    final ipRegex = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');
    if (!ipRegex.hasMatch(ip)) {
      showCopyableSnackBar(context, 'Invalid IPv4 format.');
      return;
    }

    final duplicate = _targets.any(
      (target) => target.ip == ip && target.port == port,
    );
    if (duplicate) {
      showCopyableSnackBar(context, 'Target already exists.');
      return;
    }

    setState(() {
      _targets.add(_TargetEntry(alias: alias, ip: ip, port: port));
      _aliasController.clear();
      _ipController.clear();
    });
    unawaited(_saveTargetsToLocalStorage());
  }

  void _removeTargetAt(int index) {
    setState(() {
      _targets.removeAt(index);
    });
    unawaited(_saveTargetsToLocalStorage());
  }

  Future<void> _loadTargetsFromLocalStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;

      final loadedTargets = <_TargetEntry>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final alias = item['alias']?.toString();
        final ip = item['ip']?.toString();
        final portValue = item['port'];
        final port = portValue is int
            ? portValue
            : int.tryParse(portValue?.toString() ?? '');

        if (alias == null || alias.isEmpty || ip == null || ip.isEmpty) {
          continue;
        }
        if (port == null || port <= 0 || port > 65535) {
          continue;
        }

        loadedTargets.add(_TargetEntry(alias: alias, ip: ip, port: port));
      }

      if (!mounted) return;
      setState(() {
        _targets
          ..clear()
          ..addAll(loadedTargets);
      });
    } catch (_) {
      // Ignore malformed localStorage data and keep runtime list empty.
    }
  }

  Future<void> _saveTargetsToLocalStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      _targets
          .map(
            (target) => {
              'alias': target.alias,
              'ip': target.ip,
              'port': target.port,
            },
          )
          .toList(growable: false),
    );
    await prefs.setString(_storageKey, encoded);
  }

  void _clearSelectedFile() {
    if (_selectedFileBytes == null && _selectedFileName == null) {
      return;
    }
    setState(() {
      _selectedFileBytes = null;
      _selectedFileName = null;
    });
    showCopyableSnackBar(context, 'Selected file removed.');
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(withData: true);

      if (!mounted || result == null || result.files.isEmpty) return;

      final file = result.files.single;
      if (file.bytes == null || file.bytes!.isEmpty) {
        showCopyableSnackBar(context, 'Cannot read selected file bytes.');
        return;
      }

      setState(() {
        _selectedFileBytes = file.bytes;
        _selectedFileName = file.name;
      });

      if (_isImageFile(file.name)) {
        await _showImageEditDialog(file.bytes!, file.name);
      } else if (_isVideoFile(file.name)) {
        await _showVideoEditDialog(file.bytes!, file.name);
      } else {
        showCopyableSnackBar(context, 'Selected file: ${file.name}');
      }
    } catch (e) {
      if (!mounted) return;
      showCopyableSnackBar(context, 'Error picking file: $e');
    }
  }

  bool _isImageFile(String fileName) {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.webp');
  }

  bool _isVideoFile(String fileName) {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mkv');
  }

  Future<void> _showImageEditDialog(Uint8List bytes, String fileName) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Send Photo'),
          content: const Text('Do you want to edit the photo before sending?'),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _editImage(bytes, fileName);
              },
              child: const Text('Edit Photo'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                showCopyableSnackBar(context, 'Selected file: $fileName');
              },
              child: const Text('Send Directly'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showVideoEditDialog(Uint8List bytes, String fileName) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Send Video'),
          content: const Text('Do you want to edit the video before sending?'),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _editVideo(bytes, fileName);
              },
              child: const Text('Edit Video'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                showCopyableSnackBar(context, 'Selected file: $fileName');
              },
              child: const Text('Send Directly'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editImage(Uint8List bytes, String fileName) async {
    if (!mounted) return;
    final editedBytes = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(builder: (context) => ImageEditor(image: bytes)),
    );
    if (!mounted) return;
    if (editedBytes == null) {
      showCopyableSnackBar(context, 'Photo editing cancelled.');
      return;
    }
    setState(() {
      _selectedFileBytes = editedBytes;
      _selectedFileName = 'edited_$fileName';
    });
    showCopyableSnackBar(context, 'Edited photo ready: edited_$fileName');
  }

  Future<void> _editVideo(Uint8List bytes, String fileName) async {
    if (!mounted) return;
    showCopyableSnackBar(
      context,
      'Video editing is not supported on web and linux.',
    );
    setState(() {
      _selectedFileBytes = bytes;
      _selectedFileName = fileName;
    });
  }

  Future<bool> _sendToTarget(_TargetEntry target) async {
    final hasFile = _selectedFileBytes != null && _selectedFileName != null;
    final textToSend = _textController.text.trim();

    if (!hasFile && textToSend.isEmpty) {
      showCopyableSnackBar(
        context,
        'Please select a file or enter text first.',
      );
      return false;
    }

    try {
      if (hasFile) {
        await ref
            .read(sendServiceProvider)
            .sendFile(
              target.toDeviceInfo(),
              _selectedFileName!,
              fileBytes: _selectedFileBytes,
            );
      } else {
        await ref
            .read(sendServiceProvider)
            .sendText(target.toDeviceInfo(), textToSend);
      }
      return true;
    } catch (e) {
      if (!mounted) return false;
      final errorText = e.toString();
      if (errorText.contains('receiver may still have received the file') ||
          errorText.contains('The receiver may still have received the file')) {
        showCopyableSnackBar(
          context,
          'Sent to ${target.alias} may already be delivered. Verify on receiver.',
        );
        return true;
      }
      showCopyableSnackBar(
        context,
        'Failed ${target.alias} (${target.ip}:${target.port}): $e',
      );
      return false;
    }
  }

  Future<void> _sendSelectedTargets() async {
    if (_isSending) return;
    final hasFile = _selectedFileBytes != null && _selectedFileName != null;
    final textToSend = _textController.text.trim();
    if (!hasFile && textToSend.isEmpty) {
      showCopyableSnackBar(
        context,
        'Please select a file or enter text first.',
      );
      return;
    }

    final selectedTargets = _targets
        .where((target) => target.selected)
        .toList();
    if (selectedTargets.isEmpty) {
      showCopyableSnackBar(context, 'Please select at least one target.');
      return;
    }

    setState(() {
      _isSending = true;
    });

    int successCount = 0;
    int failCount = 0;

    for (final target in selectedTargets) {
      final ok = await _sendToTarget(target);
      if (ok) {
        successCount++;
      } else {
        failCount++;
      }
    }

    if (!mounted) return;
    setState(() {
      _isSending = false;
    });

    if (!hasFile && failCount == 0) {
      _textController.clear();
    }

    showCopyableSnackBar(
      context,
      'Batch completed. Success: $successCount, Failed: $failCount',
    );
  }

  Future<Uint8List?> _generateVideoThumbnailFromBytes(
    Uint8List videoBytes, {
    int maxWidth = 360,
    int quality = 40,
  }) async {
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

  Widget _buildSelectedFilePreview() {
    if (_selectedFileName == null || _selectedFileBytes == null) {
      return const SizedBox.shrink();
    }

    final isImage = _isImageFile(_selectedFileName!);
    final isVideo = _isVideoFile(_selectedFileName!);

    Widget child;
    if (isImage) {
      child = Image.memory(_selectedFileBytes!, fit: BoxFit.contain);
    } else if (isVideo) {
      child = FutureBuilder<Uint8List?>(
        future: _generateVideoThumbnailFromBytes(_selectedFileBytes!),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasData && snapshot.data != null) {
            return Image.memory(snapshot.data!, fit: BoxFit.contain);
          }
          return const Center(child: Text('Video thumbnail unavailable'));
        },
      );
    } else {
      child = const Center(
        child: Icon(Icons.insert_drive_file_outlined, size: 56),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        height: 220,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('UniDrop Web Sender')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double listHeight = (constraints.maxHeight - 320).clamp(
            180.0,
            420.0,
          );
          final double minContentWidth = constraints.maxWidth >= 720
              ? 720.0
              : constraints.maxWidth;
          final double minContentHeight = constraints.maxHeight >= 560
              ? 560.0
              : constraints.maxHeight;
          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: minContentWidth,
                    minHeight: minContentHeight,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Manual Targets',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          SizedBox(
                            width: 180,
                            child: TextField(
                              controller: _aliasController,
                              decoration: const InputDecoration(
                                labelText: 'Alias',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: TextField(
                              controller: _ipController,
                              decoration: const InputDecoration(
                                labelText: 'IP Address',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          ElevatedButton(
                            onPressed: _addTarget,
                            child: const Text('Add'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _isSending ? null : _pickFile,
                            icon: const Icon(Icons.attach_file),
                            label: const Text('Pick File'),
                          ),
                          const SizedBox(width: 8),
                          if (_selectedFileName != null)
                            OutlinedButton.icon(
                              onPressed: _isSending ? null : _clearSelectedFile,
                              icon: const Icon(Icons.close),
                              label: const Text('Cancel File'),
                            ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _selectedFileName == null
                                  ? 'No file selected'
                                  : 'Selected: $_selectedFileName',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      _buildSelectedFilePreview(),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _textController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Text Message (optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _isSending ? null : _sendSelectedTargets,
                            icon: _isSending
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.send),
                            label: const Text('Send File/Text to Selected'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: listHeight,
                        child: _targets.isEmpty
                            ? const Center(
                                child: Text(
                                  'No targets yet. Add a target above.',
                                ),
                              )
                            : ListView.builder(
                                itemCount: _targets.length,
                                itemBuilder: (context, index) {
                                  final target = _targets[index];
                                  return CheckboxListTile(
                                    value: target.selected,
                                    onChanged: _isSending
                                        ? null
                                        : (value) {
                                            setState(() {
                                              target.selected = value ?? false;
                                            });
                                          },
                                    title: Text(target.alias),
                                    subtitle: Text(
                                      '${target.ip}:${target.port}',
                                    ),
                                    secondary: IconButton(
                                      icon: const Icon(Icons.delete),
                                      onPressed: _isSending
                                          ? null
                                          : () {
                                              _removeTargetAt(index);
                                            },
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
