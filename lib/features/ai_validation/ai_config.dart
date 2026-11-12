/// Gemini model used by the AI photo validation. This is the only place the
/// model name appears, so changing models is a one-line edit.
const String kAiModelName = 'gemini-3.5-flash-lite';

/// How long a single AI request may take before it counts as a failure.
const Duration kAiRequestTimeout = Duration(seconds: 30);

/// A photo must be judged a breeding site with at least this confidence.
const double kMinConfidence = 0.7;
