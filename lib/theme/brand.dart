import 'package:flutter/material.dart';

/// Éléments de marque Zappart — versions **détourées** (fond transparent),
/// dérivées des logos de l'app officielle.
///
/// - [ZappartMark] : monogramme « ZA ».
/// - [ZappartWordmark] : logotype « ZappArt ».
///
/// `light: true` → version blanche (pour fond sombre) ; sinon version noire.
class ZappartMark extends StatelessWidget {
  const ZappartMark({super.key, this.size = 32, this.light = false});

  final double size;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      light ? 'assets/images/mark_blanc.png' : 'assets/images/mark_noir.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }
}

class ZappartWordmark extends StatelessWidget {
  const ZappartWordmark({super.key, this.height = 28, this.light = false});

  final double height;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      light
          ? 'assets/images/wordmark_blanc.png'
          : 'assets/images/wordmark_noir.png',
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }
}
