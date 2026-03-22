import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cross_platform_video_thumbnails/cross_platform_video_thumbnails.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:unidrop/features/receive/received_file_provider.dart';
import 'package:unidrop/models/received_file_info.dart';
import 'package:mime/mime.dart';
import 'package:logging/logging.dart';
import 'package:unidrop/widgets/copyable_error_snackbar.dart';

/// A dialog widget that displays received file information and provides options to keep or delete the file.
/// Shows a thumbnail preview for images and videos, and handles file operations across different platforms.
class ReceivedFileDialog extends ConsumerStatefulWidget {
  final ReceivedFileInfo fileInfo;

  /// Creates a ReceivedFileDialog instance.
  /// [fileInfo] contains information about the received file including path and filename.
  const ReceivedFileDialog({super.key, required this.fileInfo});

  @override
  ConsumerState<ReceivedFileDialog> createState() => _ReceivedFileDialogState();
}

class _ReceivedFileDialogState extends ConsumerState<ReceivedFileDialog> {
  static final _logger = Logger('ReceivedFileDialog');
  String? _mimeType;

  @override
  void initState() {
    super.initState();
    _mimeType = lookupMimeType(widget.fileInfo.path);
  }

  bool get _isImageFile => _mimeType?.startsWith('image/') ?? false;

  bool get _isVideoFile => _mimeType?.startsWith('video/') ?? false;

  Future<Uint8List?> _generateVideoThumbnailData(
    String videoPath, {
    int maxWidth = 360,
    int quality = 40,
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

  Widget _buildFilePreview() {
    if (_isImageFile) {
      return SizedBox(
        height: 220,
        width: 320,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(widget.fileInfo.path),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Center(
              child: Text('Preview unavailable'),
            ),
          ),
        ),
      );
    }

    if (_isVideoFile) {
      return SizedBox(
        height: 220,
        width: 320,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: FutureBuilder<Uint8List?>(
            future: _generateVideoThumbnailData(widget.fileInfo.path),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasData && snapshot.data != null) {
                return Image.memory(snapshot.data!, fit: BoxFit.contain);
              }
              return const Center(child: Text('Preview unavailable'));
            },
          ),
        ),
      );
    }

    return SizedBox(
      height: 220,
      width: 320,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.insert_drive_file, size: 50, color: Colors.grey),
              SizedBox(height: 8),
              Text('No preview for this file type'),
            ],
          ),
        ),
      ),
    );
  }

  /// Deletes the received file from the file system.
  /// Shows appropriate feedback messages based on the operation result.
  /// Clears the received file state and closes the dialog after operation.
  Future<void> _deleteFile(BuildContext context) async {
    try {
      final file = File(widget.fileInfo.path);
      if (await file.exists()) {
        await file.delete();
        _logger.info('File deleted: ${widget.fileInfo.path}');
        if (context.mounted) {
          showCopyableSnackBar(
              context, 'File "${widget.fileInfo.filename}" deleted.');
        }
      } else {
        _logger.warning('File not found for deletion: ${widget.fileInfo.path}');
        if (context.mounted) {
          showCopyableSnackBar(
              context, 'File "${widget.fileInfo.filename}" not found.');
        }
      }
    } catch (e) {
      _logger.severe('Error deleting file ${widget.fileInfo.path}', e);
      if (context.mounted) {
        showCopyableSnackBar(context, 'Error deleting file: $e');
      }
    } finally {
      ref.read(receivedFileProvider.notifier).clearReceivedFile();
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  /// Processes the file keeping operation based on platform and file type.
  /// For native platforms: Saves to gallery if image/video, or keeps in temp location
  /// Shows appropriate feedback messages and handles cleanup after operation.
  Future<void> _keepFile(BuildContext context) async {
    String message = 'File "${widget.fileInfo.filename}" kept.';
    bool deleteOriginal = false;
    final navigator = Navigator.of(context);
    try {
      _logger.info(
          'Native platform detected. Keep action for ${widget.fileInfo.filename}');
      message = Platform.isWindows
          ? 'File "${widget.fileInfo.filename}" saved to Downloads.'
          : 'File "${widget.fileInfo.filename}" kept in temporary location.'; // Default message
      if (_mimeType != null &&
          (_mimeType!.startsWith('image/') ||
              _mimeType!.startsWith('video/'))) {
        _logger.info(
            'Attempting to save ${widget.fileInfo.filename} to gallery...');
        if (Platform.isWindows) {
          message =
              '${_mimeType!.startsWith('image/') ? 'Photo' : 'Video'} "${widget.fileInfo.filename}" saved to Downloads.';
        } else {
          final result =
              await ImageGallerySaverPlus.saveFile(widget.fileInfo.path);
          _logger.info('Gallery save result: $result');
          if (result != null && result['isSuccess'] == true) {
            message =
                '${_mimeType!.startsWith('image/') ? 'Photo' : 'Video'} "${widget.fileInfo.filename}" saved to gallery.';
            deleteOriginal = true; // Delete original if saved to gallery
          } else {
            message =
                'Failed to save "${widget.fileInfo.filename}" to gallery. Kept in temporary location.';
            _logger.warning(
                'Gallery save failed or returned unexpected result: $result');
          }
        }
      } else {
        _logger.info(
            'File type ($_mimeType) is not an image or video. Keeping in temporary location.');
      }
      if (deleteOriginal) {
        try {
          final originalFile = File(widget.fileInfo.path);
          if (await originalFile.exists()) {
            await originalFile.delete();
            _logger.info('Deleted temporary file: ${widget.fileInfo.path}');
          }
        } catch (e) {
          _logger.severe(
              'Error deleting temporary file ${widget.fileInfo.path}', e);
        }
      }
    } catch (e) {
      _logger.severe(
          'Error during keep/save operation for ${widget.fileInfo.path}', e);
      message = 'Error processing file: $e.';
    } finally {
      ref.read(receivedFileProvider.notifier).clearReceivedFile();
      if (context.mounted) {
        navigator.pop();
        showCopyableSnackBar(context, message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('File Received'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: _buildFilePreview()),
            const SizedBox(height: 12),
            Text(
              'Detected MIME type: ${_mimeType ?? 'Unknown'}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'Received file: "${widget.fileInfo.filename}".\nKeep it or delete it?',
              textAlign: TextAlign.left,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
            child: const Text('Delete'), onPressed: () => _deleteFile(context)),
        TextButton(
            child: const Text('Keep'), onPressed: () => _keepFile(context)),
      ],
    );
  }
}
