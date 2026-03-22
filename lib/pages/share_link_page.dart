import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:unidrop/features/server/share_host_service.dart';
import 'package:unidrop/features/server/share_link_provider.dart';
import 'package:unidrop/utils/ip_address_utils.dart';
import 'package:unidrop/widgets/copyable_error_snackbar.dart';

class ShareLinkPage extends ConsumerStatefulWidget {
  const ShareLinkPage({
    super.key,
    required this.localIpAddress,
  });

  final String localIpAddress;

  @override
  ConsumerState<ShareLinkPage> createState() => _ShareLinkPageState();
}

class _ShareLinkPageState extends ConsumerState<ShareLinkPage> {
  bool _isStarting = true;
  String? _error;
  String? _shareUrl;
  int _currentQrIndex = 0;
  List<String> _allShareUrls = const [];
  late final ShareHostService _shareHostService;

  @override
  void initState() {
    super.initState();
    _shareHostService = ref.read(shareHostServiceProvider);
    unawaited(_startHost());
  }

  Future<void> _startHost() async {
    try {
      final port = await _shareHostService.startHost(port: 2707);
      final allIps = await _collectUsableLocalIps();
      final allUrls = allIps.map((ip) => 'http://$ip:$port/share').toList();
      final primaryUrl = allUrls.isNotEmpty
          ? allUrls.first
          : 'http://${widget.localIpAddress}:$port/share';
      if (!mounted) return;
      setState(() {
        _shareUrl = primaryUrl;
        _allShareUrls = allUrls.isNotEmpty ? allUrls : [primaryUrl];
        _currentQrIndex = 0;
        _isStarting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to start share host: $e';
        _isStarting = false;
      });
    }
  }

  Future<List<String>> _collectUsableLocalIps() async {
    final ips = <String>{};
    if (IpAddressUtils.isUsableIpv4(widget.localIpAddress)) {
      ips.add(widget.localIpAddress);
    }

    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      for (final networkInterface in interfaces) {
        for (final address in networkInterface.addresses) {
          final ip = address.address;
          if (IpAddressUtils.isUsableIpv4(ip)) {
            ips.add(ip);
          }
        }
      }
    } catch (_) {}

    final results = ips.toList();
    results.sort((left, right) {
      if (left == widget.localIpAddress) return -1;
      if (right == widget.localIpAddress) return 1;
      return left.compareTo(right);
    });
    return results;
  }

  String _extractIpFromUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri?.host ?? '';
  }

  void _showNextQr() {
    if (_allShareUrls.isEmpty) return;
    final nextIndex = (_currentQrIndex + 1) % _allShareUrls.length;
    setState(() {
      _currentQrIndex = nextIndex;
      _shareUrl = _allShareUrls[nextIndex];
    });
  }

  @override
  void dispose() {
    unawaited(_shareHostService.stopHost());
    super.dispose();
  }

  Uri? _extractWebLinkUri(String? text) {
    if (text == null) return null;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return null;
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return null;
    }
    return uri;
  }

  Future<Uint8List?> _generateVideoThumbnailData(String videoPath,
      {int maxWidth = 400, int quality = 40}) async {
    final tempFile = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}share_thumb_${DateTime.now().millisecondsSinceEpoch}.jpg');
    try {
      final generated = await FcNativeVideoThumbnail().getVideoThumbnail(
        srcFile: videoPath,
        destFile: tempFile.path,
        width: maxWidth,
        height: maxWidth,
        format: 'jpeg',
        quality: quality,
      );
      if (!generated || !await tempFile.exists()) {
        return null;
      }
      return await tempFile.readAsBytes();
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  Future<Uint8List?> _generateVideoThumbnailFromBytes(Uint8List videoBytes,
      {int maxWidth = 400, int quality = 40}) async {
    final tempVideoFile = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}share_video_${DateTime.now().millisecondsSinceEpoch}.mp4');
    try {
      await tempVideoFile.writeAsBytes(videoBytes, flush: true);
      return await _generateVideoThumbnailData(
        tempVideoFile.path,
        maxWidth: maxWidth,
        quality: quality,
      );
    } finally {
      if (await tempVideoFile.exists()) {
        await tempVideoFile.delete();
      }
    }
  }

  Widget _buildInAppPreview(ShareFileState shareFile) {
    final mime = shareFile.mimeType.toLowerCase();
    final lowerName = shareFile.fileName.toLowerCase();
    final isImage = mime.startsWith('image/') ||
      lowerName.endsWith('.jpg') ||
      lowerName.endsWith('.jpeg') ||
      lowerName.endsWith('.png') ||
      lowerName.endsWith('.gif') ||
      lowerName.endsWith('.bmp') ||
      lowerName.endsWith('.webp') ||
      lowerName.endsWith('.heic') ||
      lowerName.endsWith('.heif');
    final isVideo = mime.startsWith('video/') ||
      lowerName.endsWith('.mp4') ||
      lowerName.endsWith('.mov') ||
      lowerName.endsWith('.m4v') ||
      lowerName.endsWith('.webm') ||
      lowerName.endsWith('.avi') ||
      lowerName.endsWith('.mkv') ||
      lowerName.endsWith('.wmv');
    final webLink = _extractWebLinkUri(shareFile.sharedText);

    if (webLink != null) {
      final text = webLink.toString();
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Web link preview'),
              const SizedBox(height: 8),
              SelectableText(text),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  unawaited(Clipboard.setData(ClipboardData(text: text)));
                  showCopyableSnackBar(context, 'Copied link: $text');
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy web link'),
              ),
            ],
          ),
        ),
      );
    }

    if (isImage) {
      Widget imageWidget;
      if (shareFile.hasBytes) {
        imageWidget = Image.memory(shareFile.fileBytes!, fit: BoxFit.contain);
      } else if (shareFile.hasPath) {
        imageWidget =
            Image.file(File(shareFile.filePath!), fit: BoxFit.contain);
      } else {
        imageWidget = const Text('Image preview unavailable.');
      }
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Photo preview'),
              const SizedBox(height: 8),
              SizedBox(height: 220, child: Center(child: imageWidget)),
            ],
          ),
        ),
      );
    }

    if (isVideo) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Video thumbnail'),
              const SizedBox(height: 8),
              if (shareFile.hasPath || shareFile.hasBytes)
                FutureBuilder<Uint8List?>(
                  future: shareFile.hasPath
                      ? _generateVideoThumbnailData(shareFile.filePath!)
                      : _generateVideoThumbnailFromBytes(shareFile.fileBytes!),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox(
                        height: 200,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasData && snapshot.data != null) {
                      return SizedBox(
                        height: 220,
                        child: Center(
                          child:
                              Image.memory(snapshot.data!, fit: BoxFit.contain),
                        ),
                      );
                    }
                    return const SizedBox(
                      height: 200,
                      child:
                          Center(child: Text('Video thumbnail unavailable.')),
                    );
                  },
                )
              else
                const SizedBox(
                  height: 200,
                  child: Center(
                    child: Text('Video thumbnail unavailable.'),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final shareFile = ref.watch(shareFileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Send with link'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _isStarting
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : shareFile == null || _shareUrl == null
                    ? const Center(
                        child: Text('No file available for sharing.'))
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('File: ${shareFile.fileName}'),
                            const SizedBox(height: 8),
                            const Text('Available links:'),
                            const SizedBox(height: 6),
                            ..._allShareUrls.map(
                              (url) => Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: Row(
                                  children: [
                                    Expanded(child: SelectableText(url)),
                                    const SizedBox(width: 8),
                                    OutlinedButton.icon(
                                      onPressed: () {
                                        unawaited(Clipboard.setData(
                                            ClipboardData(text: url)));
                                        showCopyableSnackBar(
                                            context, 'Copied: $url');
                                      },
                                      icon: const Icon(Icons.copy),
                                      label: const Text('Copy'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildInAppPreview(shareFile),
                            const SizedBox(height: 16),
                            Center(
                              child: Column(
                                children: [
                                  GestureDetector(
                                    onTap: _allShareUrls.length > 1
                                        ? _showNextQr
                                        : null,
                                    child: Container(
                                      color: Colors.white,
                                      padding: const EdgeInsets.all(8.0),
                                      child: SizedBox(
                                        width: 220,
                                        height: 220,
                                        child: PrettyQrView.data(
                                          data: _shareUrl!,
                                          decoration: const PrettyQrDecoration(
                                            shape: PrettyQrSmoothSymbol(
                                                color: Colors.black),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'QR IP: ${_extractIpFromUrl(_shareUrl!)}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  if (_allShareUrls.length > 1)
                                    Text(
                                      'Tap QR to switch IP (${_currentQrIndex + 1}/${_allShareUrls.length})',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
      ),
    );
  }
}
