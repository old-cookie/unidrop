// QR Scanner page that handles scanning QR codes using the device's camera
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:logging/logging.dart';

// StatefulWidget that represents the QR scanner screen
class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});
  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

// State class that manages the QR scanner functionality
class _QrScannerPageState extends State<QrScannerPage> with WidgetsBindingObserver {
  // Controller for the mobile scanner with auto start disabled
  final MobileScannerController controller = MobileScannerController(
    autoStart: false,
  );

  // Subscription for handling barcode detection events
  StreamSubscription<Object?>? _subscription;
  // Flag to prevent multiple processing of the same QR code
  bool _isProcessing = false;

  // Initialize the state and start listening for QR codes
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = controller.barcodes.listen(_handleBarcode);
    unawaited(controller.start());
  }

  // Handle app lifecycle changes to manage camera resources
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!controller.value.isInitialized) {
      return;
    }
    switch (state) {
      // Stop scanner when app is not in foreground
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        unawaited(_subscription?.cancel());
        _subscription = null;
        unawaited(controller.stop());
        break;
      // Resume scanner when app comes back to foreground
      case AppLifecycleState.resumed:
        _subscription = controller.barcodes.listen(_handleBarcode);
        unawaited(controller.start());
        break;
      case AppLifecycleState.inactive:
        break;
    }
  }

  // Process detected QR codes
  void _handleBarcode(BarcodeCapture capture) {
    // Prevent multiple processing of the same QR code
    if (_isProcessing) return;

    if (capture.barcodes.isNotEmpty) {
      final String? scannedValue = capture.barcodes.first.rawValue;
      if (scannedValue != null) {
        setState(() {
          _isProcessing = true;
        });
        Logger('QrScannerPage').info('QR Code Detected: $scannedValue');
        // Stop scanning and return the detected value
        unawaited(controller.stop());
        Navigator.of(context).pop(scannedValue);
      }
    }
  }

  // Clean up resources when widget is disposed
  @override
  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    _subscription = null;
    super.dispose();
    await controller.dispose();
  }

  // Build the UI for the QR scanner
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR Code')),
      body: Stack(
        children: [
          // Mobile scanner widget that handles camera preview and QR detection
          MobileScanner(
            controller: controller,
            onDetect: (capture) {},
          ),
        ],
      ),
    );
  }
}
