import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void showCopyableSnackBar(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      action: SnackBarAction(
        label: 'Copy',
        onPressed: () {
          Clipboard.setData(ClipboardData(text: message));
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            const SnackBar(content: Text('Message copied.')),
          );
        },
      ),
    ),
  );
}

void showCopyableErrorSnackBar(BuildContext context, String message) {
  showCopyableSnackBar(context, message);
}