import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:unidrop/features/receive/received_file_provider.dart';
import 'package:unidrop/features/receive/received_text_provider.dart';
import 'package:unidrop/models/received_file_info.dart';
import 'package:path_provider/path_provider.dart';
import 'package:unidrop/features/server/server_provider.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_multipart/shelf_multipart.dart';

const int _defaultPort = 2706;

class ServerService {
  final Ref _ref;
  HttpServer? _server;
  final _logger = Logger('ServerService');

  /// Constructs a [ServerService] instance
  ///
  /// [_ref] - Riverpod reference for state management
  /// [initialPort] - Initial port number for the server (defaults to 2706)
  ServerService(this._ref, {int initialPort = _defaultPort});

  /// Starts the HTTP server with file and text receiving capabilities
  ///
  /// Sets up routes for:
  /// - `/` - Basic server health check
  /// - `/info` - Server information endpoint
  /// - `/receive` - File upload endpoint
  /// - `/receive-text` - Text receiving endpoint
  Future<void> startServer() async {
    if (_server != null) {
      _logger.info('Server already running on port ${_server!.port}');
      return;
    }
    try {
      final router = Router();
      router.get('/', (Request request) {
        return Response.ok('Hello from LocalSend Plus Server!');
      });
      router.get('/info', _handleInfoRequest);
      router.post('/receive',
          (Request request) => _handleReceiveRequest(request, _ref));
      router.post('/receive-text',
          (Request request) => _handleReceiveTextRequest(request, _ref));
      final handler =
          const Pipeline().addMiddleware(logRequests()).addHandler(router.call);
      _logger.info('Starting HTTP server...');
      const int fixedPort = 2706;
      _logger.info('Starting HTTP server on fixed port $fixedPort...');
      int? actualPort;
      if (!kIsWeb) {
        _server =
            await shelf_io.serve(handler, InternetAddress.anyIPv4, fixedPort);
        _logger.info('HTTP Server started');
        actualPort = _server!.port;
        _logger.info('Server listening on port $actualPort (HTTP only)');
        _ref.read(serverStateProvider.notifier).setRunning(actualPort);
      } else {
        _logger.warning(
            'Warning: Full HTTP server functionality is not available on the web platform.');
        _ref
            .read(serverStateProvider.notifier)
            .setError('Server not supported on web');
        return;
      }
    } catch (e) {
      _logger.severe('Error starting server: $e');
      _ref.read(serverStateProvider.notifier).setError(e.toString());
      await stopServer();
    }
  }

  /// Stops the running server instance
  ///
  /// Forces the server to close and updates the server state
  Future<void> stopServer() async {
    if (_server == null) return;
    _logger.info('Stopping server...');
    await _server!.close(force: true);
    _server = null;
    _ref.read(serverStateProvider.notifier).setStopped();
    _logger.info('Server stopped.');
  }

  /// Returns the current port number of the running server
  /// Returns null if server is not running
  int? get runningPort => _server?.port;

  /// Handles server information requests
  ///
  /// Returns JSON containing:
  /// - alias: Device name
  /// - version: Server version
  /// - deviceModel: Operating system or 'web'
  /// - https: SSL status
  Future<Response> _handleInfoRequest(Request request) async {
    final deviceModel = kIsWeb ? 'web' : Platform.operatingSystem;
    final deviceInfo = {
      'alias': 'MyDevice',
      'version': '1.0.0',
      'deviceModel': deviceModel,
      'https': false
    };
    return Response.ok(jsonEncode(deviceInfo),
        headers: {'Content-Type': 'application/json'});
  }

  /// Handles file upload requests
  ///
  /// Processes multipart form data to save received files
  /// Updates the [receivedFileProvider] with file information
  ///
  /// Returns success/error response based on upload result
  Future<Response> _handleReceiveRequest(Request request, Ref ref) async {
    if (request.multipart() case var multipart?) {
      String? receivedFileName;
      String? finalFilePath;
      try {
        final downloadsDir = await getDownloadsDirectory();
        if (downloadsDir == null) {
          _logger.severe('Error: Could not access downloads directory.');
          return Response.internalServerError(
              body: 'Could not access downloads directory.');
        }
        final targetDirectory = downloadsDir.path;
        _logger.info('Saving received files to: $targetDirectory');
        await for (final part in multipart.parts) {
          final contentDisposition = part.headers['content-disposition'];
          final filenameRegExp = RegExp(r'filename="([^"]*)"');
          final match = filenameRegExp.firstMatch(contentDisposition ?? '');
          receivedFileName = match?.group(1);
          if (receivedFileName != null) {
            receivedFileName = receivedFileName
                .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
                .trim();
            if (receivedFileName.isEmpty) {
              _logger.warning('Skipping part with empty sanitized filename.');
              continue;
            }
            finalFilePath =
                '$targetDirectory${Platform.pathSeparator}$receivedFileName';
            final outputFile = File(finalFilePath);
            _logger.info('Receiving file: $receivedFileName to $finalFilePath');
            try {
              await outputFile.parent.create(recursive: true);
            } catch (dirError) {
              _logger.severe(
                  'Error creating directory ${outputFile.parent.path}: $dirError');
              return Response.internalServerError(
                  body: 'Could not create target directory.');
            }
            try {
              final fileSink = outputFile.openWrite();
              await part.pipe(fileSink);
            } catch (writeError) {
              _logger.severe('Error writing file $finalFilePath: $writeError');
              try {
                if (await outputFile.exists()) await outputFile.delete();
              } catch (_) {}
              return Response.internalServerError(body: 'Error writing file.');
            }
            _logger.info('File received successfully: $receivedFileName');
            final fileInfo = ReceivedFileInfo(
                filename: receivedFileName, path: finalFilePath);
            ref.read(receivedFileProvider.notifier).setReceivedFile(fileInfo);
            break;
          } else {
            _logger.warning(
                'Skipping part with no filename in content-disposition header.');
          }
        }
        if (receivedFileName == null) {
          return Response.badRequest(
              body: 'No valid file part found in the request.');
        }
        return Response.ok('File "$receivedFileName" received successfully.');
      } catch (e) {
        _logger.severe('Error processing multipart request: $e');
        if (finalFilePath != null) {
          try {
            final tempFile = File(finalFilePath);
            if (await tempFile.exists()) {
              await tempFile.delete();
              _logger.info('Cleaned up partially written file: $finalFilePath');
            }
          } catch (cleanupError) {
            _logger
                .severe('Error cleaning up file $finalFilePath: $cleanupError');
          }
        }
        return Response.internalServerError(
            body: 'Error processing request: $e');
      }
    } else {
      return Response.badRequest(
          body: 'Expected a multipart/form-data request.');
    }
  }

  /// Handles incoming text message requests
  ///
  /// Processes plain text content and updates [receivedTextProvider]
  ///
  /// Returns success/error response based on text processing result
  Future<Response> _handleReceiveTextRequest(Request request, Ref ref) async {
    try {
      final contentType = request.headers['content-type'];
      if (contentType == null || !contentType.startsWith('text/plain')) {
        _logger.warning(
            'Received text request with unexpected content type: $contentType');
      }
      final receivedText = await request.readAsString(utf8);
      if (receivedText.isEmpty) {
        _logger.info('Received empty text message.');
        return Response.badRequest(body: 'Received empty text.');
      }
      _logger.info('Received text: "$receivedText"');
      ref.read(receivedTextProvider.notifier).setText(receivedText);
      return Response.ok('Text received successfully.');
    } catch (e) {
      _logger.severe('Error processing text request: $e');
      return Response.internalServerError(
          body: 'Error processing text request: $e');
    }
  }
}

final serverServiceProvider =
    Provider.family<ServerService, int>((ref, initialPort) {
  return ServerService(ref, initialPort: initialPort);
});
