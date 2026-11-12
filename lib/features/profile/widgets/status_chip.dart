import 'package:flutter/material.dart';

import '../../../app/theme_proposal.dart';

/// Available status chip types with associated visual palettes.
enum StatusChipType {
  valid,
  pending,
  checking,
  rejected,
  reviewed,
  needsDetail;

  /// Helper parser for dynamic or backend status strings
  static StatusChipType fromString(String value) {
    final lower = value.toLowerCase();
    if (lower == 'valid' || lower.contains('valid') || lower.contains('approved')) {
      return StatusChipType.valid;
    }
    if (lower == 'checking' || lower.contains('checking')) {
      return StatusChipType.checking;
    }
    if (lower.contains('pending')) {
      return StatusChipType.pending;
    }
    if (lower.contains('reviewed')) {
      return StatusChipType.reviewed;
    }
    if (lower.contains('rejected') || lower.contains('detail') || lower.contains('error')) {
      return StatusChipType.rejected;
    }
    return StatusChipType.pending;
  }
}

/// A pill badge displaying state for reports or activities.
class StatusChip extends StatelessWidget {
  final String text;
  final StatusChipType type;

  const StatusChip({
    super.key,
    required this.text,
    required this.type,
  });

  /// Factory constructor to construct a chip directly from a status string
  factory StatusChip.fromStatus({
    Key? key,
    required String text,
    required String status,
  }) {
    return StatusChip(
      key: key,
      text: text,
      type: StatusChipType.fromString(status),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color bgColor;
    final Color textColor;

    switch (type) {
      case StatusChipType.valid:
      case StatusChipType.reviewed:
        bgColor = AppColors.primaryLight;
        textColor = AppColors.primaryDark;
        break;
      case StatusChipType.pending:
        bgColor = AppColors.warningBg;
        textColor = AppColors.warningText;
        break;
      case StatusChipType.checking:
        bgColor = const Color(0xFFFFEDE0);
        textColor = const Color(0xFFB8501A);
        break;
      case StatusChipType.rejected:
      case StatusChipType.needsDetail:
        bgColor = AppColors.errorBg;
        textColor = AppColors.errorText;
        break;
    }

    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: (textTheme.labelSmall ?? AppTypography.caption).copyWith(
          color: textColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
