import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:unidrop/models/device_info.dart';
import 'package:logging/logging.dart';

/// Core service class that provides file and text transmission functionality.
/// Handles HTTP communication with target devices for file uploads and text message delivery.
class SendService {
  SendService() {
    _logger = Logger('SendService');
  }

  late final Logger _logger;

  /// Sends a file to the target device.
  ///
  /// Parameters:
  /// - [targetDevice]: Target device information containing IP and port
  /// - [fileName]: Name of the file to be sent
  /// - [filePath]: Optional, local path to the file
  /// - [fileBytes]: Optional, binary content of the file
  ///
  /// Notes:
  /// - Either [filePath] or [fileBytes] must be provided
  /// - If both are provided, [fileBytes] takes precedence
  ///
  /// Throws:
  /// - [ArgumentError]: When neither filePath nor fileBytes is provided
  /// - [Exception]: When file transmission fails
  Future<void> sendFile(DeviceInfo targetDevice, String fileName,
      {String? filePath, Uint8List? fileBytes}) async {
    if (filePath == null && fileBytes == null) {
      throw ArgumentError('sendFile requires either a filePath or fileBytes.');
    }
    if (filePath != null && fileBytes != null) {
      _logger.warning(
          'Both filePath and fileBytes provided to sendFile. Using fileBytes.');
      filePath = null;
    }

    final url =
        Uri.parse('http://${targetDevice.ip}:${targetDevice.port}/receive');
    final client = http.Client();
    const timeoutDuration = Duration(seconds: 15);
    int retryCount = 0;
    const maxRetries = 1;
    try {
      int? bytesLength;
      while (retryCount <= maxRetries) {
        try {
          final request = http.MultipartRequest('POST', url);
          request.fields['fileName'] = fileName;
          http.MultipartFile multipartFile;
          if (fileBytes != null) {
            bytesLength = fileBytes.length;
            multipartFile = http.MultipartFile.fromBytes('file', fileBytes,
                filename: fileName);
            _logger.info(
                'Preparing to send $fileName ($bytesLength bytes) from memory...');
          } else {
            final file = File(filePath!);
            bytesLength = await file.length();
            multipartFile = await http.MultipartFile.fromPath('file', filePath,
                filename: fileName);
            _logger.info(
                'Preparing to send $fileName ($bytesLength bytes) from path $filePath...');
          }

          request.files.add(multipartFile);
          request.fields['fileSize'] = bytesLength.toString();
          _logger.info(
              'Sending $fileName ($bytesLength bytes) to ${targetDevice.alias} at $url...');

          final response = await client.send(request).timeout(timeoutDuration);
          if (response.statusCode == 200) {
            _logger.info('File sent successfully to ${targetDevice.alias}.');
            return;
          }

          final responseBody = await response.stream.bytesToString();
          _logger.severe(
              'File send failed to ${targetDevice.alias}. Status code: ${response.statusCode}');
          _logger.severe('Server error response: $responseBody');
          throw Exception(
              'Failed to send file: Server responded with status ${response.statusCode}');
        } on TimeoutException {
          final error =
              'Connection timed out after ${timeoutDuration.inSeconds}s to ${targetDevice.ip}:${targetDevice.port}';
          if (retryCount == maxRetries) {
            throw Exception(_buildNetworkHelpMessage(targetDevice, error));
          }
          _logger.warning('Attempt ${retryCount + 1} failed: $error');
        } on SocketException catch (e) {
          final error = 'Socket error: ${e.message}';
          if (retryCount == maxRetries) {
            throw Exception(_buildNetworkHelpMessage(targetDevice, error));
          }
          _logger.warning('Attempt ${retryCount + 1} failed: $error');
        }

        retryCount++;
        if (retryCount <= maxRetries) {
          final waitDuration = Duration(milliseconds: 500 * (1 << retryCount));
          _logger.info(
              'Retrying file send in ${waitDuration.inMilliseconds}ms...');
          await Future.delayed(waitDuration);
        }
      }
      throw Exception('Failed to send file after $maxRetries retries.');
    } catch (e) {
      _logger.severe('Error sending file to ${targetDevice.alias}: $e');
      throw Exception('Error sending file: $e');
    } finally {
      client.close();
      _logger.info(
          "HTTP Client closed for sendFile request to ${targetDevice.alias}.");
    }
  }

  String _buildNetworkHelpMessage(DeviceInfo targetDevice, String reason) {
    return '$reason. Cannot reach ${targetDevice.alias} (${targetDevice.ip}:${targetDevice.port}). '
        'Please ensure both devices are on the same LAN and allow UniDrop through firewall on port ${targetDevice.port}.';
  }

  String _truncateText(String text, [int maxLength = 50]) {
    return text.length > maxLength
        ? '${text.substring(0, maxLength)}...'
        : text;
  }

  /// Sends a text message to the target device.
  ///
  /// Parameters:
  /// - [targetDevice]: Target device information containing IP and port
  /// - [text]: Text content to be sent
  ///
  /// Features:
  /// - Includes automatic retry mechanism with up to 2 retries
  /// - Uses exponential backoff algorithm for retry intervals
  /// - Request timeout of 10 seconds per attempt
  ///
  /// Throws:
  /// - [Exception]: When text transmission fails after all retry attempts
  Future<void> sendText(DeviceInfo targetDevice, String text) async {
    // Use a specific endpoint for text messages for clarity on the server-side
    final url = Uri.parse(
        'http://${targetDevice.ip}:${targetDevice.port}/receive-text');
    final client = http.Client();
    const timeoutDuration = Duration(seconds: 10);
    int retryCount = 0;
    const maxRetries = 2;
    try {
      _logger.info(
          'Sending text "${_truncateText(text)}" to ${targetDevice.alias} at $url...');
      while (retryCount <= maxRetries) {
        try {
          final response = await client
              .post(url,
                  headers: {'Content-Type': 'text/plain; charset=utf-8'},
                  body: text,
                  encoding: utf8)
              .timeout(timeoutDuration);
          if (response.statusCode == 200) {
            _logger.info('Text sent successfully to ${targetDevice.alias}.');
            return; // Success - exit the method
          } else {
            final error =
                'Server responded with status ${response.statusCode}: ${response.body}';
            if (retryCount == maxRetries) {
              throw Exception(error);
            }
            _logger.warning('Attempt ${retryCount + 1} failed: $error');
          }
        } on TimeoutException {
          final error =
              'Request timed out after ${timeoutDuration.inSeconds} seconds';
          if (retryCount == maxRetries) {
            throw Exception(error);
          }
          _logger.warning('Attempt ${retryCount + 1} failed: $error');
        } on SocketException catch (e) {
          final error = 'Network error: ${e.message}';
          if (retryCount == maxRetries) {
            throw Exception(error);
          }
          _logger.warning('Attempt ${retryCount + 1} failed: $error');
        }
        retryCount++;
        if (retryCount <= maxRetries) {
          // Wait before retrying, with exponential backoff
          final waitDuration = Duration(milliseconds: 500 * (1 << retryCount));
          _logger.info('Retrying in ${waitDuration.inMilliseconds}ms...');
          await Future.delayed(waitDuration);
        }
      }
      throw Exception('Failed to send text after $maxRetries retries');
    } catch (e) {
      _logger.severe('Error sending text to ${targetDevice.alias}: $e');
      rethrow;
    } finally {
      client.close();
      _logger.info(
          "HTTP Client closed for sendText request to ${targetDevice.alias}.");
    }
  }
}

/// Provider that offers global access to SendService instance
final sendServiceProvider = Provider<SendService>((ref) {
  return SendService();
});
