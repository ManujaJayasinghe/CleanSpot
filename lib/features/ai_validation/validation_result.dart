import 'dart:convert';

/// What kind of breeding site the AI saw. [wireValue] is the string used in
/// the JSON schema sent to Gemini.
enum SiteCategory {
  stagnantWater('stagnant_water'),
  tire('tire'),
  blockedDrain('blocked_drain'),
  container('container'),
  other('other'),
  none('none');

  const SiteCategory(this.wireValue);

  final String wireValue;

  static SiteCategory? fromWire(Object? value) {
    for (final c in values) {
      if (c.wireValue == value) return c;
    }
    return null;
  }
}

/// The AI's verdict on one photo.
///
/// Any failure (network, timeout, quota, App Check, malformed or partial JSON)
/// is represented by [ValidationResult.error], which is never a breeding site
/// and so can never lead to a verified report.
class ValidationResult {
  const ValidationResult({
    required this.isBreedingSite,
    required this.category,
    required this.confidence,
    required this.looksFake,
    required this.reason,
  }) : error = null;

  /// A failed check. [message] is for logs; [reason] is safe to show the user.
  const ValidationResult.error(String message)
      : isBreedingSite = false,
        category = SiteCategory.none,
        confidence = 0,
        looksFake = false,
        reason = retryMessage,
        error = message;

  static const retryMessage =
      'We could not check your photo. Please try again.';

  final bool isBreedingSite;
  final SiteCategory category;

  /// 0.0 (not sure at all) to 1.0 (certain).
  final double confidence;

  /// Photo of a screen or printout, a stock image, or heavily edited.
  final bool looksFake;

  /// Short, user-friendly explanation.
  final String reason;

  /// Non-null only for failed checks.
  final String? error;

  bool get isError => error != null;

  /// Parses the model's raw text reply. Never throws: anything that is not a
  /// complete, valid verdict becomes a [ValidationResult.error].
  factory ValidationResult.parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const ValidationResult.error('Empty response from the model.');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(_stripCodeFence(raw));
    } on FormatException catch (e) {
      return ValidationResult.error('Malformed JSON: ${e.message}');
    }
    if (decoded is! Map<String, Object?>) {
      return const ValidationResult.error('Expected a JSON object.');
    }
    return ValidationResult.fromJson(decoded);
  }

  /// Builds a result from decoded JSON. Missing, mistyped or out-of-range
  /// fields give a [ValidationResult.error]; this never throws.
  factory ValidationResult.fromJson(Map<String, Object?> json) {
    final isBreedingSite = json['isBreedingSite'];
    final category = SiteCategory.fromWire(json['category']);
    final confidence = json['confidence'];
    final looksFake = json['looksFake'];
    final reason = json['reason'];

    if (isBreedingSite is! bool) {
      return const ValidationResult.error('isBreedingSite missing or not bool.');
    }
    if (category == null) {
      return const ValidationResult.error('category missing or unknown.');
    }
    if (confidence is! num || confidence < 0 || confidence > 1) {
      return const ValidationResult.error(
        'confidence missing or outside 0..1.',
      );
    }
    if (looksFake is! bool) {
      return const ValidationResult.error('looksFake missing or not bool.');
    }
    if (reason is! String || reason.trim().isEmpty) {
      return const ValidationResult.error('reason missing or empty.');
    }
    if (isBreedingSite && category == SiteCategory.none) {
      return const ValidationResult.error(
        'Contradiction: breeding site with category none.',
      );
    }

    return ValidationResult(
      isBreedingSite: isBreedingSite,
      category: category,
      confidence: confidence.toDouble(),
      looksFake: looksFake,
      reason: reason.trim(),
    );
  }

  /// Removes a ```json ... ``` wrapper if the model added one.
  static String _stripCodeFence(String raw) {
    final match = RegExp(r'^\s*```(?:json)?\s*([\s\S]*?)\s*```\s*$').firstMatch(raw);
    return match != null ? match.group(1)! : raw;
  }

  @override
  String toString() => isError
      ? 'ValidationResult.error($error)'
      : 'ValidationResult(isBreedingSite: $isBreedingSite, '
          'category: ${category.wireValue}, confidence: $confidence, '
          'looksFake: $looksFake, reason: "$reason")';
}
