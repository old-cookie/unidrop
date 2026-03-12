import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_link_previewer/flutter_link_previewer.dart';
import 'dart:developer' as developer;

/// A dialog widget that displays received text content with link preview functionality.
/// This widget allows users to view the received text and copy it to the clipboard.
class ReceivedTextDialog extends StatefulWidget {
  /// The text content that was received and will be displayed in the dialog.
  final String receivedText;

  /// Creates a [ReceivedTextDialog] with the specified received text.
  /// Parameters:
  /// - [receivedText]: The text content to be displayed in the dialog.
  /// - [key]: An optional key to uniquely identify this widget.
  const ReceivedTextDialog({super.key, required this.receivedText});

  @override
  State<ReceivedTextDialog> createState() => _ReceivedTextDialogState();
}

/// The state for the [ReceivedTextDialog] widget.
/// Handles the preview data state and builds the dialog UI.
class _ReceivedTextDialogState extends State<ReceivedTextDialog> {
  static const platform = MethodChannel('com.example.unidrop/browser');

  String? _extractPreviewUrl(String input) {
    final match = RegExp(r'((https?:\/\/)|(www\.))[^\s]+').firstMatch(input);
    if (match == null) return null;

    var url = match.group(0)!;
    url = url.replaceFirst(RegExp(r'[),.!?;:]+$'), '');
    if (url.startsWith('www.')) {
      url = 'https://$url';
    }
    return url;
  }

  Future<void> _openInBrowser(String url) async {
    try {
      await platform.invokeMethod('openUrl', {'url': url});
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error opening link: ${e.message}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogMaxWidth = screenWidth * 0.85;
    final previewWidth = dialogMaxWidth - 48;
    final previewUrl = _extractPreviewUrl(widget.receivedText);
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dialogMaxWidth, maxHeight: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Text Received',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        widget.receivedText,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (previewUrl != null) ...[
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () {
                            _openInBrowser(previewUrl);
                          },
                          child: LinkPreview(
                            enableAnimation: true,
                            onLinkPreviewDataFetched: (_) {},
                            text: previewUrl,
                            minWidth: previewWidth,
                            maxWidth: previewWidth,
                            insidePadding: const EdgeInsets.all(8),
                            descriptionTextStyle:
                                Theme.of(context).textTheme.bodyMedium,
                            titleTextStyle: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    child: const Text('Cancel'),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  ),
                  TextButton(
                    child: const Text('Copy to Clipboard'),
                    onPressed: () async {
                      final scaffoldMessenger = ScaffoldMessenger.of(context);
                      final navigator = Navigator.of(context);
                      try {
                        await Clipboard.setData(
                          ClipboardData(text: widget.receivedText),
                        );
                        if (!mounted) return;
                        scaffoldMessenger.showSnackBar(
                          const SnackBar(
                            content: Text('Text copied to clipboard!'),
                          ),
                        );
                        navigator.pop();
                      } catch (error) {
                        developer
                            .log('Error copying text to clipboard: $error');
                        if (!mounted) return;
                        scaffoldMessenger.showSnackBar(
                          const SnackBar(
                            content: Text('Error copying text.'),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
