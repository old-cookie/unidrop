import 'package:flutter_riverpod/flutter_riverpod.dart';

class DeviceSelectionNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => <String>{};

  void toggleSelection(String key) {
    final next = Set<String>.from(state);
    if (next.contains(key)) {
      next.remove(key);
    } else {
      next.add(key);
    }
    state = next;
  }

  bool isSelected(String key) => state.contains(key);

  int get selectedCount => state.length;

  void clearSelection() {
    if (state.isEmpty) return;
    state = <String>{};
  }
}

final deviceSelectionProvider =
    NotifierProvider<DeviceSelectionNotifier, Set<String>>(
  DeviceSelectionNotifier.new,
);