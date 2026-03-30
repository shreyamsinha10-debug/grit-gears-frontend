// ---------------------------------------------------------------------------
// Animated fade/slide – list item entrance animation.
// ---------------------------------------------------------------------------
// [FadeInSlide] wraps a child and animates opacity + optional vertical offset
// for a smooth appearance (e.g. member cards in the dashboard list).
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';

/// Fade-in with optional slight vertical slide for list items. Use for premium feel.
class FadeInSlide extends StatelessWidget {
  const FadeInSlide({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 350),
    this.offset = 8,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offset;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - value) * offset),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
