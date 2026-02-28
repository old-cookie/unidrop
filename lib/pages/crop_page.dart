import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:video_editor/video_editor.dart';

/// A page for cropping videos using the video_editor package.
/// This page provides various aspect ratio options and a visual grid for precise cropping.
/// Note: Video cropping is not supported on web platforms.
class CropPage extends StatefulWidget {
  final VideoEditorController controller;
  const CropPage({super.key, required this.controller});
  @override
  State<CropPage> createState() => _CropPageState();
}

/// State class for the CropPage widget.
/// Manages the video cropping interface and user interactions.
class _CropPageState extends State<CropPage> {
  @override
  void initState() {
    // Check for web platform and show unsupported message
    super.initState();
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Video cropping is not supported on the web.')));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading indicator for web platforms
    if (kIsWeb) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator()));
    }

    // Main scaffold with video cropping interface
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0, // Remove shadow
        title: const Text("Crop Video"),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () {
              // Apply the crop changes
              widget.controller.applyCacheCrop();
              Navigator.pop(context);
            },
            tooltip: 'Apply crop',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(padding: const EdgeInsets.all(30), child: CropGridViewer.edit(controller: widget.controller, rotateCropArea: false)),
            ),
            Padding(padding: const EdgeInsets.symmetric(vertical: 15.0), child: _buildRatioButtons()),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  /// Builds a row of aspect ratio selection buttons.
  /// Available ratios:
  /// - Free: No aspect ratio constraint
  /// - Original: Uses the video's original aspect ratio
  /// - 1:1: Square aspect ratio
  /// - 16:9: Widescreen landscape
  /// - 9:16: Widescreen portrait
  /// - 4:3: Traditional landscape
  /// - 3:4: Traditional portrait
  ///
  /// @return Widget A wrapped row of ratio selection buttons
  Widget _buildRatioButtons() {
    final Map<String, double?> ratios = {
      'Free': null,
      'Original': widget.controller.video.value.aspectRatio == 0 ? null : widget.controller.video.value.aspectRatio,
      '1:1': 1.0,
      '16:9': 16 / 9,
      '9:16': 9 / 16,
      '4:3': 4 / 3,
      '3:4': 3 / 4,
    };
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10.0,
      runSpacing: 5.0,
      children: ratios.entries.map((entry) {
        final String label = entry.key;
        final double? value = entry.value;
        final bool isSelected = (widget.controller.preferredCropAspectRatio == null && value == null) ||
            (widget.controller.preferredCropAspectRatio != null &&
                value != null &&
                (widget.controller.preferredCropAspectRatio! - value).abs() < 0.01);
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              setState(() {
                widget.controller.preferredCropAspectRatio = value;
              });
            },
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? Colors.orange.withAlpha(204) : Colors.black.withAlpha(128),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: isSelected ? Colors.orange : Colors.grey[700]!, width: 1.5),
              ),
              child: Text(label, style: TextStyle(color: Colors.white, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
            ),
          ),
        );
      }).toList(),
    );
  }
}
