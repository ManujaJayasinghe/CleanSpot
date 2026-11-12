import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import 'ai_config.dart';
import 'ai_prompts.dart';
import 'validation_result.dart';

/// Talks to Gemini through Firebase AI Logic (Gemini Developer API).
///
/// App Check tokens are attached automatically once App Check has been
/// activated in main.dart, so no App Check instance is passed here.
class AiValidationService {
  AiValidationService({GenerativeModel? model}) : _modelOverride = model;

  final GenerativeModel? _modelOverride;

  // Models are created on first use so constructing the service never touches
  // the network.
  late final GenerativeModel _model = _modelOverride ??
      FirebaseAI.googleAI().generativeModel(model: kAiModelName);

  late final GenerativeModel _validationModel = _modelOverride ??
      FirebaseAI.googleAI().generativeModel(
        model: kAiModelName,
        systemInstruction: Content.system(kValidationSystemInstruction),
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
          responseSchema: _validationSchema,
          temperature: 0,
        ),
      );

  /// Structured output: every field is required.
  static final Schema _validationSchema = Schema.object(
    properties: {
      'isBreedingSite': Schema.boolean(
        description: 'True only if the photo clearly shows a breeding site.',
      ),
      'category': Schema.enumString(
        enumValues: [for (final c in SiteCategory.values) c.wireValue],
      ),
      'confidence': Schema.number(
        description: 'Certainty in isBreedingSite, from 0 to 1.',
        minimum: 0,
        maximum: 1,
      ),
      'looksFake': Schema.boolean(
        description: 'Screen photo, printout, stock image or heavy edit.',
      ),
      'reason': Schema.string(
        description: 'One short, friendly sentence for the user.',
      ),
    },
    propertyOrdering: [
      'isBreedingSite',
      'category',
      'confidence',
      'looksFake',
      'reason',
    ],
  );

  /// Sends a tiny text prompt and returns the model's reply. Used only to check
  /// that Firebase AI Logic, App Check and the model name are all working.
  ///
  /// Throws on any failure (network, timeout, quota, App Check rejection).
  Future<String> ping() async {
    final response = await _model
        .generateContent([Content.text('Reply with exactly one word: pong')])
        .timeout(kAiRequestTimeout);
    return response.text ?? '';
  }

  /// Asks the model whether [jpegBytes] shows a mosquito breeding site.
  ///
  /// Never throws: every failure (network, timeout, quota, App Check
  /// rejection, blocked or malformed reply) returns [ValidationResult.error],
  /// which is never eligible.
  Future<ValidationResult> validatePhoto(Uint8List jpegBytes) async {
    if (jpegBytes.isEmpty) {
      return const ValidationResult.error('The photo is empty.');
    }
    try {
      if (kDebugMode) {
        // Debug-only timing: fetch the App Check token on its own first so its
        // cost shows up separately from the Gemini call (the token is cached
        // afterwards, so the Gemini call below does not pay for it again).
        final sw = Stopwatch()..start();
        try {
          await FirebaseAppCheck.instance.getToken();
          debugPrint('AI TIMING: appCheckToken=${sw.elapsedMilliseconds} ms');
        } catch (e) {
          debugPrint('AI TIMING: appCheckToken failed after '
              '${sw.elapsedMilliseconds} ms: $e');
        }
      }
      final geminiTimer = Stopwatch()..start();
      final response = await _validationModel.generateContent([
        Content.multi([
          TextPart(kValidationUserPrompt),
          InlineDataPart('image/jpeg', jpegBytes),
        ]),
      ]).timeout(kAiRequestTimeout);
      if (kDebugMode) {
        debugPrint('AI TIMING: gemini=${geminiTimer.elapsedMilliseconds} ms '
            '(photo ${jpegBytes.length} bytes)');
      }
      return ValidationResult.parse(response.text);
    } catch (e) {
      // Includes TimeoutException and FirebaseAIException.
      return ValidationResult.error('$e');
    }
  }
}
