import 'package:flutter/material.dart';

/// Éléments de marque Zappart, repris des assets de l'app officielle.
///
/// - [ZappartMark] : le monogramme « ZA » (blanc sur pastille noire) — pour
///   les petits emplacements (rail réduit, favicon-like).
/// - [ZappartWordmark] : le logotype « ZappArt » en noir — pour les en-têtes
///   sur fond blanc.
class ZappartMark extends StatelessWidget {
  const ZappartMark({super.key, this.size = 32, this.radius = 9});

  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(size * 0.16),
        child: Image.asset(
          'assets/images/mark_za.png',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

class ZappartWordmark extends StatelessWidget {
  const ZappartWordmark({super.key, this.height = 22});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/logo_zappart_texte_noir.jpg',
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }
}
