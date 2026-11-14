// lib/features/symptoms/symptom_questions.dart
import 'package:flutter/material.dart';

/// App colour palette (shared by all three symptom files).
class AppColors {
  static const Color button = Color(0xFF00851B); // green  - buttons
  static const Color background = Color(0xFFFFFFFF); // white  - background
  static const Color alertCard = Color(0xFFE8F1E5); // sage   - alert cards
  static const Color heading = Color(0xFF222222); // charcoal - headings

  // Risk accents (used only for the badge/icon next to the text label,
  // so colour is never the only signal).
  static const Color riskHigh = Color(0xFFC62828);
  static const Color riskMedium = Color(0xFFEF6C00);
  static const Color riskLow = Color(0xFF00851B);
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