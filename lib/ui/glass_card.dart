import 'dart:ui';

import 'package:flutter/material.dart';

/// Translucent blurred surface, the Flutter take on `bg-white/20
/// backdrop-blur-[10px] backdrop-saturate-100 border border-white/15`.
///
/// [blur] and [tint] mirror the CSS values so the bar and the expanded player
/// stay visually consistent.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.blur = 10,
    this.tint = const Color(0x33FFFFFF),
    this.borderColor = const Color(0x26FFFFFF),
    this.radius = 24,
    this.padding = const EdgeInsets.all(10),
  });

  final Widget child;
  final double blur;
  final Color tint;
  final Color borderColor;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        // dart:ui has no saturation filter, so the CSS `backdrop-saturate` is
        // approximated by the tint above the blur.
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Dark scrim behind the glass, so the blur has something to sample.
class PlayerBackdrop extends StatelessWidget {
  const PlayerBackdrop({super.key, required this.child, this.colors});

  final Widget child;
  final List<Color>? colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors:
              colors ??
              const <Color>[
                Color(0xFF121016),
                Color(0xFF1B1622),
                Color(0xFF0E0C11),
              ],
        ),
      ),
      child: child,
    );
  }
}