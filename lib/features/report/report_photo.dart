import 'dart:convert';
import 'package:flutter/material.dart';

import '../../app/theme_proposal.dart';

/// Site photo for the report flow.
/// Supports both network URLs (http/https) and Base64 data strings (data:image or raw base64).
/// Falls back to a plain green block when no photo was provided or error occurs.
class ReportPhoto extends StatelessWidget {
  const ReportPhoto({
    super.key,
    required this.url,
    this.height = 220,
    this.radius = 16,
    this.showScanFrame = false,
  });

  final String? url;
  final double height;
  final double radius;

  /// Draws the corner brackets and scan line used on the AI checking screen.
  final bool showScanFrame;

  Widget _buildImageWidget(String source, Widget fallback) {
    if (source.startsWith('data:image') || !source.startsWith('http')) {
      try {
        final cleanBase64 = source.contains(',') ? source.split(',').last : source;
        final bytes = base64Decode(cleanBase64.trim());
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback,
        );
      } catch (_) {
        return fallback;
      }
    }

    return Image.network(
      source,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => fallback,
    );
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: AppColors.primaryDark,
      child: const Center(
        child: Icon(Icons.water_drop_outlined, size: 44, color: Colors.white70),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url == null || url!.isEmpty)
              fallback
            else
              _buildImageWidget(url!, fallback),
            if (showScanFrame)
              const CustomPaint(painter: _ScanFramePainter()),
          ],
        ),
      ),
    );
  }
}

class _ScanFramePainter extends CustomPainter {
  const _ScanFramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const inset = 16.0;
    const len = 26.0;
    final l = inset;
    final t = inset;
    final r = size.width - inset;
    final b = size.height - inset;

    // Four corner brackets.
    canvas.drawPath(
      Path()
        ..moveTo(l, t + len)
        ..lineTo(l, t)
        ..lineTo(l + len, t),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(r - len, t)
        ..lineTo(r, t)
        ..lineTo(r, t + len),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(l, b - len)
        ..lineTo(l, b)
        ..lineTo(l + len, b),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(r - len, b)
        ..lineTo(r, b)
        ..lineTo(r, b - len),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
