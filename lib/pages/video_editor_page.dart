import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:pro_video_editor/pro_video_editor.dart';
import 'package:unidrop/widgets/copyable_error_snackbar.dart';
import 'package:video_player/video_player.dart';

class ExportConfig {
  final String outputPath;
  final String taskId;

  const ExportConfig({required this.outputPath, required this.taskId});
}

// A screen for editing videos with features like trimming, cropping, and rotation
// Supports basic video manipulation operations through an intuitive UI
class VideoEditorScreen extends StatefulWidget {
  final File file;
  const VideoEditorScreen({super.key, required this.file});
  @override
  State<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends State<VideoEditorScreen> {
  final _editorKey = GlobalKey<ProImageEditorState>();
  final _taskId = DateTime.now().microsecondsSinceEpoch.toString();
  final _thumbnailCount = 7;
  final _proVideoEditor = ProVideoEditor.instance;

  ProVideoController? _proVideoController;
  VideoPlayerController? _videoController;
  VideoMetadata? _videoMetadata;
  List<ImageProvider>? _thumbnails;
  String? _outputPath;

  bool _isSeeking = false;
  TrimDurationSpan? _durationSpan;
  TrimDurationSpan? _pendingDurationSpan;

  late final ProImageEditorConfigs _configs = ProImageEditorConfigs(
    videoEditor: const VideoEditorConfigs(
      initialMuted: false,
      initialPlay: false,
      isAudioSupported: true,
      playTimeSmoothingDuration: Duration(milliseconds: 500),
    ),
  );

  @override
  void initState() {
    super.initState();
    _initializeEditor();
  }

  @override
  void dispose() {
    _videoController?.removeListener(_onDurationChange);
    _videoController?.dispose();
    _proVideoController?.dispose();
    super.dispose();
  }

  Future<void> _initializeEditor() async {
    try {
      final video = EditorVideo.file(widget.file.path);
      final metadata = await _proVideoEditor.getMetadata(video);
      final controller = VideoPlayerController.file(widget.file);

      await Future.wait([
        controller.initialize(),
        controller.setLooping(false),
        controller.setVolume(_configs.videoEditor.initialMuted ? 0 : 1),
        _configs.videoEditor.initialPlay
            ? controller.play()
            : controller.pause(),
      ]);

      if (!mounted) return;

      _videoMetadata = metadata;
      _videoController = controller;
      _videoController!.addListener(_onDurationChange);

      unawaited(_generateThumbnails(video));

      _proVideoController = ProVideoController(
        videoPlayer: _buildVideoPlayer(),
        initialResolution: metadata.resolution,
        videoDuration: metadata.duration,
        fileSize: metadata.fileSize,
        thumbnails: _thumbnails,
      );

      setState(() {});
    } catch (error) {
      if (!mounted) return;
      _showErrorSnackBar('Error initializing video editor: $error');
      Navigator.pop(context, null);
    }
  }

  // Display error messages to user via SnackBar
  void _showErrorSnackBar(String message) {
    if (mounted) {
      showCopyableSnackBar(context, message);
    }
  }

  Future<void> _generateVideo(CompleteParameters parameters) async {
    if (_videoController == null) return;
    try {
      unawaited(_videoController!.pause());
      final tempDir = await getTemporaryDirectory();
      final now = DateTime.now().millisecondsSinceEpoch;
      final outputPath =
          '${tempDir.path}${Platform.pathSeparator}edited_video_$now.mp4';

      final data = VideoRenderData(
        id: _taskId,
        video: EditorVideo.file(widget.file.path),
        outputFormat: VideoOutputFormat.mp4,
        startTime: parameters.startTime,
        endTime: parameters.endTime,
        enableAudio: _proVideoController?.isAudioEnabled ?? true,
        imageBytes: parameters.layers.isNotEmpty ? parameters.image : null,
        blur: parameters.blur,
        colorMatrixList: parameters.colorFilters,
        transform: parameters.isTransformed
            ? null
            : ExportTransform(
                width: parameters.cropWidth,
                height: parameters.cropHeight,
                rotateTurns: parameters.rotateTurns,
                x: parameters.cropX,
                y: parameters.cropY,
                flipX: parameters.flipX,
                flipY: parameters.flipY,
              ),
      );

      _outputPath = await _proVideoEditor.renderVideoToFile(outputPath, data);
    } catch (e) {
      _outputPath = null;
      _showErrorSnackBar('Error creating video export: $e');
    }
  }

  Future<void> _generateThumbnails(EditorVideo video) async {
    if (_videoMetadata == null) return;
    final imageWidth = MediaQuery.sizeOf(context).width /
        _thumbnailCount *
        MediaQuery.devicePixelRatioOf(context);

    final duration = _videoMetadata!.duration;
    final segmentDuration = duration.inMilliseconds / _thumbnailCount;
    final thumbnails = await _proVideoEditor.getThumbnails(
      ThumbnailConfigs(
        video: video,
        outputSize: Size.square(imageWidth),
        boxFit: ThumbnailBoxFit.cover,
        outputFormat: ThumbnailFormat.jpeg,
        timestamps: List.generate(
          _thumbnailCount,
          (index) => Duration(
              milliseconds: (((index + 0.5) * segmentDuration).round())),
        ),
      ),
    );

    if (!mounted) return;
    _thumbnails = thumbnails.map(MemoryImage.new).toList();
    _proVideoController?.thumbnails = _thumbnails;
  }

  void _onDurationChange() {
    if (_videoController == null ||
        _videoMetadata == null ||
        _proVideoController == null) {
      return;
    }

    final totalDuration = _videoMetadata!.duration;
    final position = _videoController!.value.position;
    _proVideoController!.setPlayTime(position);

    if (_durationSpan != null && position >= _durationSpan!.end) {
      unawaited(_seekToPosition(_durationSpan!));
    } else if (position >= totalDuration) {
      unawaited(_seekToPosition(
        TrimDurationSpan(start: Duration.zero, end: totalDuration),
      ));
    }
  }

  Future<void> _seekToPosition(TrimDurationSpan span) async {
    if (_videoController == null || _proVideoController == null) return;

    _durationSpan = span;
    if (_isSeeking) {
      _pendingDurationSpan = span;
      return;
    }
    _isSeeking = true;

    _proVideoController!.pause();
    _proVideoController!.setPlayTime(span.start);
    await _videoController!.pause();
    await _videoController!.seekTo(span.start);

    _isSeeking = false;
    if (_pendingDurationSpan != null) {
      final next = _pendingDurationSpan!;
      _pendingDurationSpan = null;
      await _seekToPosition(next);
    }
  }

  Future<void> _handleCloseEditor(EditorMode editorMode) async {
    if (editorMode != EditorMode.main) {
      Navigator.pop(context);
      return;
    }

    if (_outputPath == null) {
      Navigator.pop(context, null);
      return;
    }

    Navigator.pop(
      context,
      ExportConfig(outputPath: _outputPath!, taskId: _taskId),
    );
  }

  Widget _buildEditor() {
    return ProImageEditor.video(
      _proVideoController!,
      key: _editorKey,
      callbacks: ProImageEditorCallbacks(
        onCompleteWithParameters: _generateVideo,
        onCloseEditor: (mode) {
          unawaited(_handleCloseEditor(mode));
        },
        videoEditorCallbacks: VideoEditorCallbacks(
          onPause: _videoController?.pause,
          onPlay: _videoController?.play,
          onMuteToggle: (isMuted) {
            _videoController?.setVolume(isMuted ? 0 : 1);
          },
          onTrimSpanUpdate: (span) {
            if (_videoController?.value.isPlaying ?? false) {
              _proVideoController?.pause();
            }
          },
          onTrimSpanEnd: _seekToPosition,
        ),
      ),
      configs: _configs,
    );
  }

  Widget _buildVideoPlayer() {
    return Center(
      child: _videoController == null || !_videoController!.value.isInitialized
          ? const CircularProgressIndicator.adaptive()
          : AspectRatio(
              aspectRatio: _videoController!.value.size.aspectRatio,
              child: VideoPlayer(_videoController!),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: _proVideoController == null
          ? const Scaffold(
              body: Center(child: CircularProgressIndicator.adaptive()),
            )
          : _buildEditor(),
    );
  }
}
