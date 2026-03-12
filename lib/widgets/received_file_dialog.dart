import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:unidrop/features/receive/received_file_provider.dart';
import 'package:unidrop/models/received_file_info.dart';
import 'package:universal_html/html.dart' as html;
import 'package:mime/mime.dart';
import 'package:image/image.dart' as img;
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:logging/logging.dart';

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
  bool _isLoadingThumbnail = true;
  String? _mimeType;
  Uint8List? _thumbnailData;
  @override
  void initState() {
    super.initState();
    _mimeType = lookupMimeType(widget.fileInfo.path);
    _generateThumbnail();
  }

  /// Generates a thumbnail for the received file if it's an image or video.
  /// Updates the UI state during and after thumbnail generation.
  /// Handles different file types and potential errors during generation.
  Future<void> _generateThumbnail() async {
    setState(() {
      _isLoadingThumbnail = true;
    });
    Uint8List? data;
    try {
      if (_mimeType?.startsWith('image/') ?? false) {
        final fileBytes = await File(widget.fileInfo.path).readAsBytes();
        data = await _decodeAndResizeImage(fileBytes);
        _logger
            .info('Image thumbnail generated for ${widget.fileInfo.filename}');
      } else if (_mimeType?.startsWith('video/') ?? false) {
        final tempThumbPath =
            '${Directory.systemTemp.path}${Platform.pathSeparator}received_thumb_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final generated = await FcNativeVideoThumbnail().getVideoThumbnail(
          srcFile: widget.fileInfo.path,
          destFile: tempThumbPath,
          width: 100,
          height: 100,
          format: 'jpeg',
          quality: 75,
        );
        if (generated) {
          final thumbFile = File(tempThumbPath);
          if (await thumbFile.exists()) {
            data = await thumbFile.readAsBytes();
            await thumbFile.delete();
          }
        }
        _logger
            .info('Video thumbnail generated for ${widget.fileInfo.filename}');
      } else {
        _logger.info(
            'Thumbnail generation not supported for MIME type: $_mimeType');
      }
    } catch (e) {
      _logger.severe(
          'Error generating thumbnail for ${widget.fileInfo.filename}', e);
      data = null;
    } finally {
      if (mounted) {
        setState(() {
          _thumbnailData = data;
          _isLoadingThumbnail = false;
        });
      }
    }
  }

  /// Decodes and resizes an image from bytes to create a thumbnail.
  /// [fileBytes] The raw bytes of the image file.
  /// Returns a Uint8List containing the compressed thumbnail data, or null if processing fails.
  static Future<Uint8List?> _decodeAndResizeImage(Uint8List fileBytes) async {
    img.Image? image = img.decodeImage(fileBytes);
    if (image != null) {
      img.Image thumbnail = img.copyResize(image, width: 100);
      return img.encodeJpg(thumbnail, quality: 85);
    }
    return null;
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
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('File "${widget.fileInfo.filename}" deleted.')));
        }
      } else {
        _logger.warning('File not found for deletion: ${widget.fileInfo.path}');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('File "${widget.fileInfo.filename}" not found.')));
        }
      }
    } catch (e) {
      _logger.severe('Error deleting file ${widget.fileInfo.path}', e);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error deleting file: $e')));
      }
    } finally {
      ref.read(receivedFileProvider.notifier).clearReceivedFile();
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  /// Processes the file keeping operation based on platform and file type.
  /// For web: Initiates browser download
  /// For native platforms: Saves to gallery if image/video, or keeps in temp location
  /// Shows appropriate feedback messages and handles cleanup after operation.
  Future<void> _keepFile(BuildContext context) async {
    String message = 'File "${widget.fileInfo.filename}" kept.';
    bool deleteOriginal = false;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      if (kIsWeb) {
        _logger.info(
            'Web platform detected. Attempting browser download for ${widget.fileInfo.filename}');
        final file = File(widget.fileInfo.path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final blob = html.Blob([bytes], _mimeType);
          final url = html.Url.createObjectUrlFromBlob(blob);
          html.Url.revokeObjectUrl(url);
          message = 'Downloading "${widget.fileInfo.filename}"...';
          deleteOriginal = true;
          _logger.info(
              'Browser download initiated for ${widget.fileInfo.filename}');
        } else {
          message = 'Error: File not found for download.';
          _logger.warning(
              'File not found for web download: ${widget.fileInfo.path}');
        }
      } else {
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
            // On Windows, file is already saved to Downloads folder — just keep it there.
            message =
                '${_mimeType!.startsWith('image/') ? 'Photo' : 'Video'} "${widget.fileInfo.filename}" saved to Downloads.';
            // deleteOriginal stays false — do not delete from Downloads
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
        scaffoldMessenger.showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('File Received'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 100,
            width: 100,
            child: _isLoadingThumbnail
                ? const Center(child: CircularProgressIndicator())
                : _thumbnailData != null
                    ? Image.memory(
                        _thumbnailData!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Center(
                                child: Icon(Icons.error_outline,
                                    size: 50, color: Colors.red)),
                      )
                    : const Center(
                        child: Icon(Icons.insert_drive_file,
                            size: 50, color: Colors.grey)),
          ),
          const SizedBox(height: 16),
          Text(
              'Received file: "${widget.fileInfo.filename}".\nKeep it or delete it?',
              textAlign: TextAlign.center),
        ],
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
