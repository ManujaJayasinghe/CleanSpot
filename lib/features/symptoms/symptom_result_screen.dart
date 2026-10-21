// lib/features/symptoms/symptom_result_screen.dart
import 'package:flutter/material.dart';
import 'symptom_questions.dart';

enum RiskLevel { high, medium, low }

class SymptomResultScreen extends StatelessWidget {
  final RiskLevel level;
  final VoidCallback onRestart;

  /// Called when "Find medical care" is pressed. Connect this to your
  /// clinic / hospital finder. If null, a placeholder message is shown.
  final VoidCallback? onFindCare;

  const SymptomResultScreen({
    super.key,
    required this.level,
    required this.onRestart,
    this.onFindCare,
  });

  // Illustrative wording - not clinically approved.
  String get _pillLabel => switch (level) {
        RiskLevel.high => 'High risk',
        RiskLevel.medium => 'Medium risk',
        RiskLevel.low => 'Low risk',
      };

  String get _headline => switch (level) {
        RiskLevel.high => 'Seek urgent medical care',
        RiskLevel.medium => 'Get medical advice',
        RiskLevel.low => 'Rest and monitor',
      };

  String get _message => switch (level) {
        RiskLevel.high =>
          'A warning sign was reported. Please seek urgent medical assessment.',
        RiskLevel.medium =>
          "Your answers meet the application's medium-risk criteria. "
              'Please seek medical advice and follow the recommended '
              'clinical assessment.',
        RiskLevel.low =>
          "Your answers do not meet the application's high- or medium-risk "
              'criteria. This does not rule out dengue. Monitor your '
              'symptoms and seek medical advice if you are concerned or '
              'your condition worsens.',
      };

  String get _nextSteps => switch (level) {
        RiskLevel.high =>
          'Go to a hospital now. Tell the staff when your symptoms started '
              'and which warning signs you have.',
        RiskLevel.medium =>
          'See a doctor and get a blood test. Tell your doctor when your '
              'symptoms started and if they are getting worse.',
        RiskLevel.low =>
          'Rest, drink fluids and monitor your symptoms. Tell your doctor '
              'when they started and if they are getting worse.',
      };

  Color get _pillBackground => switch (level) {
        RiskLevel.high => AppColors.riskHighTint,
        RiskLevel.medium => AppColors.riskMediumTint,
        RiskLevel.low => AppColors.riskLowTint,
      };

  Color get _pillText => switch (level) {
        RiskLevel.high => AppColors.riskHighText,
        RiskLevel.medium => AppColors.riskMediumText,
        RiskLevel.low => AppColors.riskLowText,
      };

  Color get _pillDot => switch (level) {
        RiskLevel.high => AppColors.riskHigh,
        RiskLevel.medium => AppColors.riskMedium,
        RiskLevel.low => AppColors.riskLow,
      };

  // Built from the same list the questionnaire uses, so they never drift apart.
  String get _urgentText {
    if (warningSigns.isEmpty) {
      return 'Seek urgent care if you feel seriously unwell. Do not wait.';
    }
    final signs = warningSigns.map((s) => s.toLowerCase()).toList();
    final last = signs.removeLast();
    final list = signs.isEmpty ? last : '${signs.join(', ')} or $last';
    return 'Seek urgent care for $list. Do not wait.';
  }

  void _findCare(BuildContext context) {
    if (onFindCare != null) {
      onFindCare!();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Find medical care is not connected yet.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.softBackground,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: InkWell(
                            onTap: () => Navigator.of(context).maybePop(),
                            child: const Icon(Icons.arrow_back,
                                size: 22, color: AppColors.button),
                          ),
                        ),
                        const Expanded(
                          child: Text(
                            'Symptom Checker',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: AppColors.heading,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Your result · Demo questionnaire',
                      style: TextStyle(fontSize: 13, color: AppColors.body),
                    ),
                    const SizedBox(height: 16),

                    // Result card with risk pill.
                    _whiteCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: _pillBackground,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: _pillDot,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _pillLabel,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: _pillText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _headline,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppColors.heading,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _message,
                            style: const TextStyle(
                              fontSize: 13.5,
                              height: 1.45,
                              color: AppColors.body,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // What to do next.
                    _whiteCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'What to do next',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.heading,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _nextSteps,
                            style: const TextStyle(
                              fontSize: 13.5,
                              height: 1.45,
                              color: AppColors.body,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // When to get urgent help (sage card).
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.alertCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.bannerBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.monitor_heart_outlined,
                                  size: 18, color: AppColors.button),
                              SizedBox(width: 8),
                              Text(
                                'When to get urgent help',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.heading,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _urgentText,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.45,
                              color: AppColors.heading,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Required medical disclaimer - exact wording.
                    const Text(
                      'This is not a medical diagnosis. Always consult a doctor.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: AppColors.body,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom buttons.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _findCare(context),
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: AppColors.button,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Find medical care',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        onRestart();
                        Navigator.pop(context);
                      },
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.heading,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Back to Home',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _whiteCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: child,
    );
  }
}