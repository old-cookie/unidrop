import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the last received text message.
/// This provider is used to display the received text in the UI.
/// It is initialized to null and updated when a new text message is received.
class ReceivedTextNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setText(String? text) {
    state = text;
  }
}

final receivedTextProvider =
    NotifierProvider<ReceivedTextNotifier, String?>(ReceivedTextNotifier.new);
