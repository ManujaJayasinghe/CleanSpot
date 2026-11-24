import 'package:flutter/material.dart';

/// The dark green card background used across the app: a lighter circle in the
/// top right corner with a faint, tilted eco leaf in it.
///
/// Used by the Profile and Rewards points cards ([PointsCard]), and by the
/// compact points card and the Report button on Home. The defaults reproduce
/// the points card exactly; compact uses pass a smaller [circleSize] and
/// [leafSize].
class LeafBackground extends StatelessWidget {
  const LeafBackground({
    super.key,
    required this.child,
    this.borderRadius,
    this.circleSize = 230,
    this.circleTop = -45,
    this.circleRight = -45,
    this.leafSize = 88,
  });

  /// Dark green card colour.
  static const Color darkGreen = Color(0xFF145A32);

  /// Lighter circle behind the leaf.
  static const Color circleGreen = Color(0xFF1E7544);

  static const Color _leafGreen = Color(0xFF81C784);

  static const BorderRadius defaultRadius = BorderRadius.all(Radius.circular(24));

  /// Drawn above the decoration. Sizes the card (it is the only child that is
  /// not positioned).
  final Widget child;

  /// Corner radius of the card. Defaults to 24, like the points cards.
  final BorderRadius? borderRadius;

  /// Diameter of the lighter circle.
  final double circleSize;

  /// Distance of the circle from the top edge. Null centres the circle
  /// vertically, which suits short cards and buttons whose height varies.
  final double? circleTop;

  /// Distance of the circle from the right edge (negative = partly outside).
  final double circleRight;

  /// Size of the leaf icon in the circle.
  final double leafSize;

  @override
  Widget build(BuildContext context) {
    final circle = Container(
      width: circleSize,
      height: circleSize,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: circleGreen,
      ),
      child: Center(
        child: Transform.rotate(
          angle: -0.25,
          child: Icon(
            Icons.eco_outlined,
            size: leafSize,
            color: _leafGreen.withValues(alpha: 0.45),
          ),
        ),
      ),
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: darkGreen,
        borderRadius: borderRadius ?? defaultRadius,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (circleTop != null)
            Positioned(top: circleTop, right: circleRight, child: circle)
          else
            Positioned(
              top: 0,
              bottom: 0,
              right: circleRight,
              width: circleSize,
              child: OverflowBox(
                minHeight: circleSize,
                maxHeight: circleSize,
                child: circle,
              ),
            ),
          child,
        ],
      ),
    );
  }
}
