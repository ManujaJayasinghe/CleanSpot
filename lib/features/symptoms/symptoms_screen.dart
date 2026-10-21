// lib/features/symptoms/symptoms_screen.dart
import 'package:flutter/material.dart';
import 'symptom_questions.dart';
import 'symptom_result_screen.dart';

class SymptomsScreen extends StatefulWidget {
  const SymptomsScreen({super.key});

  @override
  State<SymptomsScreen> createState() => _SymptomsScreenState();
}

class _SymptomsScreenState extends State<SymptomsScreen> {
  int _index = 0;
  bool _showWarnings = false; // warning-sign list, shown after Q4
  final Set<int> _ticked = {};
  // One entry per question; null = not answered yet.
  final List<bool?> _answers = List.filled(symptomQuestions.length, null);

  void _select(bool value) => setState(() => _answers[_index] = value);

  void _next() {
    if (_answers[_index] == null) return;

    if (_index < symptomQuestions.length - 1) {
      setState(() => _index++);
    } else {
      setState(() => _showWarnings = true);
    }
  }

  void _back() {
    if (_showWarnings) {
      setState(() => _showWarnings = false);
    } else if (_index > 0) {
      setState(() => _index--);
    }
  }

  void _restart() {
    setState(() {
      _index = 0;
      _showWarnings = false;
      _ticked.clear();
      for (var i = 0; i < _answers.length; i++) {
        _answers[i] = null;
      }
    });
  }

  void _finish() {
    // Prevent submitting an incomplete questionnaire.
    if (_answers.contains(null)) return;

    final bool hasWarningSign = _ticked.isNotEmpty;
    bool hasFever = false;
    int otherSymptomCount = 0;

    for (var i = 0; i < symptomQuestions.length; i++) {
      if (_answers[i] != true) continue;
      final q = symptomQuestions[i];
      if (q.isFever) {
        hasFever = true;
      } else {
        otherSymptomCount++;
      }
    }

    RiskLevel level;
    if (hasWarningSign) {
      level = RiskLevel.high;
    } else if (hasFever && otherSymptomCount >= 2) {
      level = RiskLevel.medium;
    } else {
      level = RiskLevel.low;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SymptomResultScreen(
          level: level,
          onRestart: _restart,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _header(context),
                    const SizedBox(height: 8),
                    const Text(
                      'A few simple questions to help you decide when to get support.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: AppColors.body,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _wellbeingBanner(),
                    const SizedBox(height: 20),
                    if (_showWarnings) _warningBody() else _questionBody(),
                    const SizedBox(height: 14),
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
            _bottomButtons(),
          ],
        ),
      ),
    );
  }

  // ---------- Shared pieces ----------

  Widget _header(BuildContext context) {
    return Row(
      children: [
        if (Navigator.of(context).canPop())
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
    );
  }

  Widget _wellbeingBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.alertCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.bannerBorder),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.monitor_heart_outlined,
                  size: 18, color: AppColors.button),
              SizedBox(width: 8),
              Text(
                'Your wellbeing comes first',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.heading,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'If you feel seriously unwell, seek medical help now. '
            'Do not wait for this checklist.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: AppColors.heading,
            ),
          ),
        ],
      ),
    );
  }

  Widget _progress({required String label, required double value}) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.heading,
              ),
            ),
            const Text(
              'Demo questionnaire',
              style: TextStyle(fontSize: 11, color: AppColors.body),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 6,
            backgroundColor: AppColors.border,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.button),
          ),
        ),
      ],
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  // ---------- Questions 1-4 ----------

  Widget _questionBody() {
    final total = symptomQuestions.length;
    final question = symptomQuestions[_index];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _progress(
          label: 'Question ${_index + 1} of $total',
          value: (_index + 1) / total,
        ),
        const SizedBox(height: 16),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                question.question,
                style: const TextStyle(
                  fontSize: 21,
                  height: 1.3,
                  fontWeight: FontWeight.w800,
                  color: AppColors.heading,
                ),
              ),
              const SizedBox(height: 20),
              _option('Yes', true),
              const SizedBox(height: 10),
              _option('No', false),
            ],
          ),
        ),
      ],
    );
  }

  Widget _option(String label, bool value) {
    final selected = _answers[_index] == value;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _select(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 44,
        decoration: BoxDecoration(
          color: selected ? AppColors.alertCard : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.selectedBorder : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.heading : AppColors.button,
              ),
            ),
            if (selected)
              const Positioned(
                right: 12,
                child: Icon(Icons.check_circle_outline,
                    size: 18, color: AppColors.button),
              ),
          ],
        ),
      ),
    );
  }

  // ---------- Warning signs (after Q4) ----------

  Widget _warningBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _progress(label: 'Warning signs', value: 1.0),
        const SizedBox(height: 16),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tick any warning signs you have',
                style: TextStyle(
                  fontSize: 21,
                  height: 1.3,
                  fontWeight: FontWeight.w800,
                  color: AppColors.heading,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'If none apply to you, leave them all unticked.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: AppColors.body,
                ),
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < warningSigns.length; i++) _warningTile(i),
            ],
          ),
        ),
      ],
    );
  }

  Widget _warningTile(int i) {
    final selected = _ticked.contains(i);
    return Container(
      margin: EdgeInsets.only(bottom: i == warningSigns.length - 1 ? 0 : 10),
      decoration: BoxDecoration(
        color: selected ? AppColors.alertCard : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? AppColors.selectedBorder : AppColors.border,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: CheckboxListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        controlAffinity: ListTileControlAffinity.leading,
        activeColor: AppColors.button,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Text(
          warningSigns[i],
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.heading,
          ),
        ),
        value: selected,
        onChanged: (v) => setState(() {
          if (v == true) {
            _ticked.add(i);
          } else {
            _ticked.remove(i);
          }
        }),
      ),
    );
  }

  // ---------- Bottom Back / Next ----------

  Widget _bottomButtons() {
    final bool backEnabled = _showWarnings || _index > 0;
    final bool nextEnabled = _showWarnings || _answers[_index] != null;
    final bool isLast = _showWarnings;
    final String nextLabel = isLast ? 'See Result' : 'Next';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: backEnabled ? _back : null,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: AppColors.disabledButton,
                foregroundColor: AppColors.heading,
                disabledBackgroundColor: AppColors.disabledButton,
                disabledForegroundColor: AppColors.disabledText,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Back',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: ElevatedButton(
              onPressed: nextEnabled ? (isLast ? _finish : _next) : null,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: AppColors.button,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.nextDisabled,
                disabledForegroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                nextLabel,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}