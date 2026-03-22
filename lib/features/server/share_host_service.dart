import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:unidrop/features/server/share_link_provider.dart';
import 'package:unidrop/features/server/share_page_template.dart';

class ShareHostService {
  ShareHostService(this._ref);

  static const int defaultPort = 2707;

  final Ref _ref;
  final Logger _logger = Logger('ShareHostService');
  HttpServer? _server;

  bool get isRunning => _server != null;

  int? get runningPort => _server?.port;

  Future<int> startHost({int port = defaultPort}) async {
    if (_server != null) {
      return _server!.port;
    }

    final router = Router()
      ..get('/', _handleRoot)
      ..get('/share', _handleSharePage)
      ..get('/share/download', _handleDownload);

    final handler = const Pipeline().addMiddleware(logRequests()).addHandler((
      request,
    ) {
      return router.call(request);
    });

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    _logger.info('Share host running on port ${_server!.port}');
    return _server!.port;
  }

  Future<void> stopHost() async {
    if (_server == null) {
      return;
    }
    await _server!.close(force: true);
    _logger.info('Share host stopped.');
    _server = null;
  }

  FutureOr<Response> _handleRoot(Request request) {
    return Response.ok('UniDrop Share Host');
  }

  FutureOr<Response> _handleSharePage(Request request) {
    final shareFile = _ref.read(shareFileProvider);
    if (shareFile == null || (!shareFile.hasBytes && !shareFile.hasPath)) {
      return Response.notFound('No file is currently shared.');
    }

    final normalizedMimeType = shareFile.mimeType.toLowerCase();
    final lowerName = shareFile.fileName.toLowerCase();
    final showImagePreview = normalizedMimeType.startsWith('image/') ||
      lowerName.endsWith('.jpg') ||
      lowerName.endsWith('.jpeg') ||
      lowerName.endsWith('.png') ||
      lowerName.endsWith('.gif') ||
      lowerName.endsWith('.bmp') ||
      lowerName.endsWith('.webp') ||
      lowerName.endsWith('.heic') ||
      lowerName.endsWith('.heif');
    final showVideoPreview = normalizedMimeType.startsWith('video/') ||
      lowerName.endsWith('.mp4') ||
      lowerName.endsWith('.mov') ||
      lowerName.endsWith('.m4v') ||
      lowerName.endsWith('.webm') ||
      lowerName.endsWith('.avi') ||
      lowerName.endsWith('.mkv') ||
      lowerName.endsWith('.wmv');
    final rawSharedText = shareFile.sharedText?.trim();
    final webLinkUrl = _extractWebLink(rawSharedText);

    final fileName =
        const HtmlEscape(HtmlEscapeMode.element).convert(shareFile.fileName);
    final mimeType =
        const HtmlEscape(HtmlEscapeMode.element).convert(shareFile.mimeType);
    final senderAlias = shareFile.senderAlias == null
        ? null
        : const HtmlEscape(HtmlEscapeMode.element)
            .convert(shareFile.senderAlias!);
    final sharedText = shareFile.sharedText == null
        ? null
        : const HtmlEscape(HtmlEscapeMode.element)
            .convert(shareFile.sharedText!);
    final fileSize = _formatSize(shareFile.fileSize);

    final html = buildSharePageHtml(
      fileName: fileName,
      mimeType: mimeType,
      fileSize: fileSize,
      senderAlias: senderAlias,
      sharedText: sharedText,
      webLinkUrl: webLinkUrl,
      showImagePreview: showImagePreview,
      showVideoPreview: showVideoPreview,
    );

    return Response.ok(
      html,
      headers: {'Content-Type': 'text/html; charset=utf-8'},
    );
  }

  Future<Response> _handleDownload(Request request) async {
    final shareFile = _ref.read(shareFileProvider);
    if (shareFile == null || (!shareFile.hasBytes && !shareFile.hasPath)) {
      return Response.notFound('No file is currently shared.');
    }

    final encodedName = Uri.encodeComponent(shareFile.fileName);
    final headers = <String, String>{
      'Content-Type': shareFile.mimeType,
      'Content-Disposition': "attachment; filename*=UTF-8''$encodedName",
      'Cache-Control': 'no-store',
    };

    if (shareFile.hasBytes) {
      headers['Content-Length'] = shareFile.fileBytes!.length.toString();
      return Response.ok(shareFile.fileBytes!, headers: headers);
    }

    final file = File(shareFile.filePath!);
    if (!await file.exists()) {
      return Response.notFound('Shared file is no longer available.');
    }

    final fileStat = await file.stat();
    headers['Content-Length'] = fileStat.size.toString();
    return Response.ok(file.openRead(), headers: headers);
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(1)} GB';
  }

  String? _extractWebLink(String? text) {
    if (text == null || text.isEmpty) return null;
    final parsed = Uri.tryParse(text);
    if (parsed == null || !parsed.hasScheme || !parsed.hasAuthority) {
      return null;
    }
    final scheme = parsed.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return null;
    }
    return const HtmlEscape(HtmlEscapeMode.attribute).convert(text);
  }
}

final shareHostServiceProvider = Provider<ShareHostService>((ref) {
  final service = ShareHostService(ref);
  ref.onDispose(() {
    unawaited(service.stopHost());
  });
  return service;
});
