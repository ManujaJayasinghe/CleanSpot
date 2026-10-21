/// lib/features/symptoms/symptom_questions.dart
import 'package:flutter/material.dart';

/// App colour palette (shared by all three symptom files).
class AppColors {
  static const Color button = Color(0xFF00851B); // green  - buttons
  static const Color background = Color(0xFFFFFFFF); // white  - background
  static const Color alertCard = Color(0xFFE8F1E5); // sage   - alert cards
  static const Color heading = Color(0xFF222222); // charcoal - headings

  // Extra shades used by the redesigned screens.
  static const Color body = Color(0xFF5F6670); // secondary text
  static const Color border = Color(0xFFD9DEE3); // tile / button outline
  static const Color cardBorder = Color(0xFFE5E7EB); // white card outline
  static const Color softBackground = Color(0xFFF4F8F3); // result screen bg
  static const Color bannerBorder = Color(0xFFCFE3CB); // sage card outline
  static const Color selectedBorder = Color(0xFF3DA866); // selected tile
  static const Color disabledButton = Color(0xFFEDEDED); // Back (disabled)
  static const Color disabledText = Color(0xFF8A8F96);
  static const Color nextDisabled = Color(0xFF99CDA3); // Next (no answer yet)

  // Risk accents (used for the pill next to the text label,
  // so colour is never the only signal).
  static const Color riskHigh = Color(0xFFC62828);
  static const Color riskMedium = Color(0xFFEF6C00);
  static const Color riskLow = Color(0xFF00851B);

  // Risk pill backgrounds and text.
  static const Color riskHighTint = Color(0xFFFDECEA);
  static const Color riskMediumTint = Color(0xFFFDEBD9);
  static const Color riskLowTint = Color(0xFFE8F1E5);
  static const Color riskHighText = Color(0xFFB71C1C);
  static const Color riskMediumText = Color(0xFFB45309);
  static const Color riskLowText = Color(0xFF006B16);
}

class SymptomQuestion {
  final String question;
  final bool isFever; // used by the Medium-risk rule

  const SymptomQuestion({required this.question, this.isFever = false});
}

// Exactly 4 questions.
const List<SymptomQuestion> symptomQuestions = [
  SymptomQuestion(
    question: "Have you had a fever for two or more days?",
    isFever: true,
  ),
  SymptomQuestion(
    question: "Do you have a severe headache or pain behind your eyes?",
  ),
  SymptomQuestion(
    question: "Do you have muscle or joint pain?",
  ),
  SymptomQuestion(
    question: "Are you experiencing nausea or vomiting?",
  ),
];

// Shown AFTER the 4 questions as a tick-list (not a question).
// Ticking any one of these gives a High result.
// Starting example only - not medically validated.
const List<String> warningSigns = [
  "Severe stomach pain",
  "Bleeding from gums or nose",
  "Persistent vomiting",
  "Extreme tiredness",
];