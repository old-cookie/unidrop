final RegExp _urlTokenPattern = RegExp(
  r'((?:https?:\/\/|www\.)[^\s]+|(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}[^\s]*)',
);

final RegExp _trailingPunctuationPattern = RegExp(r'[),.!?;:]+$');

class UrlCleanerPreviewSegment {
  const UrlCleanerPreviewSegment({required this.text, required this.isRemoved});

  final String text;
  final bool isRemoved;
}

class UrlCleanerPreviewResult {
  const UrlCleanerPreviewResult({
    required this.segments,
    required this.cleanedText,
  });

  final List<UrlCleanerPreviewSegment> segments;
  final String cleanedText;

  bool get hasRemovedSegments =>
      segments.any((segment) => segment.isRemoved && segment.text.isNotEmpty);
}

/// Builds rich preview data for URL cleaning.
///
/// Segments marked with [UrlCleanerPreviewSegment.isRemoved] are the parts
/// that will be removed from the final sent text.
UrlCleanerPreviewResult buildUrlCleanerPreview({
  required String input,
  required bool enabled,
  required List<String> keywords,
}) {
  if (!enabled || input.isEmpty) {
    return UrlCleanerPreviewResult(
      segments: [UrlCleanerPreviewSegment(text: input, isRemoved: false)],
      cleanedText: input,
    );
  }

  final normalizedKeywords = keywords
      .map((keyword) => keyword.trim())
      .where((keyword) => keyword.isNotEmpty)
      .toList();

  if (normalizedKeywords.isEmpty) {
    return UrlCleanerPreviewResult(
      segments: [UrlCleanerPreviewSegment(text: input, isRemoved: false)],
      cleanedText: input,
    );
  }

  final segments = <UrlCleanerPreviewSegment>[];
  var currentIndex = 0;

  for (final match in _urlTokenPattern.allMatches(input)) {
    if (match.start > currentIndex) {
      segments.add(
        UrlCleanerPreviewSegment(
          text: input.substring(currentIndex, match.start),
          isRemoved: false,
        ),
      );
    }

    final token = match.group(0) ?? '';
    if (token.isEmpty) {
      currentIndex = match.end;
      continue;
    }

    final trailingMatch = _trailingPunctuationPattern.firstMatch(token);
    final trailingPunctuation = trailingMatch?.group(0) ?? '';
    final coreToken = trailingPunctuation.isEmpty
        ? token
        : token.substring(0, token.length - trailingPunctuation.length);

    final cutIndex = _findFirstKeywordIndex(coreToken, normalizedKeywords);
    if (cutIndex < 0) {
      segments.add(UrlCleanerPreviewSegment(text: token, isRemoved: false));
      currentIndex = match.end;
      continue;
    }

    final preservedCore = coreToken.substring(0, cutIndex);
    final removedCore = coreToken.substring(cutIndex);

    if (preservedCore.isEmpty) {
      segments.add(UrlCleanerPreviewSegment(text: token, isRemoved: false));
      currentIndex = match.end;
      continue;
    }

    segments.add(
      UrlCleanerPreviewSegment(text: preservedCore, isRemoved: false),
    );
    segments.add(UrlCleanerPreviewSegment(text: removedCore, isRemoved: true));
    if (trailingPunctuation.isNotEmpty) {
      segments.add(
        UrlCleanerPreviewSegment(text: trailingPunctuation, isRemoved: false),
      );
    }

    currentIndex = match.end;
  }

  if (currentIndex < input.length) {
    segments.add(
      UrlCleanerPreviewSegment(
        text: input.substring(currentIndex),
        isRemoved: false,
      ),
    );
  }

  final cleanedBuffer = StringBuffer();
  for (final segment in segments) {
    if (!segment.isRemoved) {
      cleanedBuffer.write(segment.text);
    }
  }

  return UrlCleanerPreviewResult(
    segments: segments,
    cleanedText: cleanedBuffer.toString(),
  );
}

/// Cleans URL tokens in [input] by removing each URL's content from the
/// earliest matched keyword onward.
///
/// Non-URL text is never modified.
String cleanUrlsInText({
  required String input,
  required bool enabled,
  required List<String> keywords,
}) {
  return buildUrlCleanerPreview(
    input: input,
    enabled: enabled,
    keywords: keywords,
  ).cleanedText;
}

int _findFirstKeywordIndex(String token, List<String> keywords) {
  final lowerToken = token.toLowerCase();
  int firstIndex = -1;

  for (final keyword in keywords) {
    final index = lowerToken.indexOf(keyword.toLowerCase());
    if (index >= 0 && (firstIndex == -1 || index < firstIndex)) {
      firstIndex = index;
    }
  }

  return firstIndex;
}
