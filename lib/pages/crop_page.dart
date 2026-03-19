import 'package:flutter/material.dart';

/// Legacy crop page placeholder.
///
/// Cropping is now handled in `VideoEditorScreen` using `pro_video_editor`.
class CropPage extends StatelessWidget {
  const CropPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crop Video')),
      body: const Center(
        child: Text('Cropping is available in the new pro_video_editor flow.'),
      ),
    );
  }
}
