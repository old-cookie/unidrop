import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

class ShareFileState {
  const ShareFileState({
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
    this.senderAlias,
    this.filePath,
    this.fileBytes,
    this.sharedText,
    required this.createdAt,
  });

  final String fileName;
  final String mimeType;
  final int fileSize;
  final String? senderAlias;
  final String? filePath;
  final Uint8List? fileBytes;
  final String? sharedText;
  final DateTime createdAt;

  bool get hasPath => filePath != null && filePath!.isNotEmpty;
  bool get hasBytes => fileBytes != null && fileBytes!.isNotEmpty;
}

class ShareFileNotifier extends Notifier<ShareFileState?> {
  @override
  ShareFileState? build() => null;

  void setShareFile({
    required String fileName,
    required String mimeType,
    required int fileSize,
    String? senderAlias,
    String? filePath,
    Uint8List? fileBytes,
    String? sharedText,
  }) {
    state = ShareFileState(
      fileName: fileName,
      mimeType: mimeType,
      fileSize: fileSize,
      senderAlias: senderAlias,
      filePath: filePath,
      fileBytes: fileBytes,
      sharedText: sharedText,
      createdAt: DateTime.now(),
    );
  }

  void clear() {
    state = null;
  }
}

final shareFileProvider =
    NotifierProvider<ShareFileNotifier, ShareFileState?>(ShareFileNotifier.new);
