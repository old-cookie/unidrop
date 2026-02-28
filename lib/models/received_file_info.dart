class ReceivedFileInfo {
  /// The name of the received file, including its extension.
  final String filename;

  /// The absolute path where the file is stored on the device.
  final String path;

  /// Creates a new [ReceivedFileInfo] instance.
  /// [filename] The name of the received file.
  /// [path] The storage location of the file.
  ReceivedFileInfo({required this.filename, required this.path});
}
