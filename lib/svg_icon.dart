import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Иконка из assets/icons (SVG с stroke="currentColor").
class SvgIcon extends StatelessWidget {
  final String name;
  final double size;
  final Color? color;

  const SvgIcon(
    this.name, {
    super.key,
    this.size = 24,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/icons/$name.svg',
      width: size,
      height: size,
      colorFilter:
          color == null ? null : ColorFilter.mode(color!, BlendMode.srcIn),
    );
  }
}
