/// Represents a set of transformations to apply during video export.
///
/// This includes resizing, rotation, flipping, and positional offsets.
class ExportTransform {
  /// Creates an [ExportTransform] with optional transformations.
  const ExportTransform({
    this.width,
    this.height,
    this.rotateTurns = 0,
    this.x,
    this.y,
    this.flipX = false,
    this.flipY = false,
    this.scaleX,
    this.scaleY,
  });

  /// Output width in pixels. If null, original width is used.
  final int? width;

  /// Output height in pixels. If null, original height is used.
  final int? height;

  /// Number of clockwise 90° rotations to apply (0 = no rotation).
  final int rotateTurns;

  /// Horizontal offset
  final int? x;

  /// Vertical offset
  final int? y;

  /// Horizontal scale factor for resizing the video or overlay image.
  ///
  /// A value of `1.0` means no scaling. Values greater than `1.0` enlarge
  /// the content, while values between `0.0` and `1.0` shrink it.
  final double? scaleX;

  /// Vertical scale factor for resizing the video or overlay image.
  ///
  /// A value of `1.0` means no scaling. Values greater than `1.0` enlarge
  /// the content, while values between `0.0` and `1.0` shrink it.
  final double? scaleY;

  /// Whether to flip horizontally.
  final bool flipX;

  /// Whether to flip vertically.
  final bool flipY;

  /// Returns a copy of this config with the given fields replaced.
  ExportTransform copyWith({
    int? width,
    int? height,
    int? rotateTurns,
    int? x,
    int? y,
    bool? flipX,
    bool? flipY,
  }) {
    return ExportTransform(
      width: width ?? this.width,
      height: height ?? this.height,
      rotateTurns: rotateTurns ?? this.rotateTurns,
      x: x ?? this.x,
      y: y ?? this.y,
      flipX: flipX ?? this.flipX,
      flipY: flipY ?? this.flipY,
    );
  }

  /// Returns `true` if this [ExportTransform] has no transformations applied.
  bool get isEmpty => this == const ExportTransform();

  /// Returns `true` if this [ExportTransform] contains at least one
  /// transformation.
  bool get isNotEmpty => !isEmpty;

  /// Converts this [ExportTransform] into a [Map] representation.
  Map<String, dynamic> toMap() {
    return {
      'rotateTurns': rotateTurns,
      'flipX': flipX,
      'flipY': flipY,
      'cropWidth': width,
      'cropHeight': height,
      'cropX': x,
      'cropY': y,
      'scaleX': scaleX,
      'scaleY': scaleY,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ExportTransform &&
        other.width == width &&
        other.height == height &&
        other.rotateTurns == rotateTurns &&
        other.x == x &&
        other.y == y &&
        other.flipX == flipX &&
        other.flipY == flipY;
  }

  @override
  int get hashCode {
    return width.hashCode ^
        height.hashCode ^
        rotateTurns.hashCode ^
        x.hashCode ^
        y.hashCode ^
        flipX.hashCode ^
        flipY.hashCode;
  }
}
