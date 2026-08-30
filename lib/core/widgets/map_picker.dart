import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../data/annonce_catalog.dart';
import '../../data/annonce_form.dart';
import '../../theme/app_theme.dart';

/// Carte OpenStreetMap (sans clé Google) pour poser la position exacte d'un
/// bien : recherche d'adresse (Nominatim), tap sur la carte, ou collage d'un
/// lien Google Maps. Cadrée au départ sur le quartier choisi.
class MapPicker extends StatefulWidget {
  const MapPicker({
    super.key,
    required this.lat,
    required this.lng,
    required this.quartierKey,
    required this.onChanged,
  });

  final double? lat;
  final double? lng;
  final String quartierKey;
  final void Function(double lat, double lng) onChanged;

  @override
  State<MapPicker> createState() => _MapPickerState();
}

class _MapPickerState extends State<MapPicker> {
  static const _dakar = LatLng(14.7167, -17.4677);
  final _map = MapController();
  final _searchCtrl = TextEditingController();
  final _linkCtrl = TextEditingController();
  LatLng? _pin;
  bool _mapReady = false;
  bool _searching = false;
  String? _msg;
  List<({String label, LatLng point})> _results = const [];

  LatLng? get _centreQuartier {
    final q = quartierInfoFor(widget.quartierKey);
    return q == null ? null : LatLng(q.lat, q.lng);
  }

  @override
  void initState() {
    super.initState();
    if (widget.lat != null && widget.lng != null) {
      _pin = LatLng(widget.lat!, widget.lng!);
    }
  }

  @override
  void didUpdateWidget(covariant MapPicker old) {
    super.didUpdateWidget(old);
    if (_pin == null &&
        widget.quartierKey != old.quartierKey &&
        _centreQuartier != null &&
        _mapReady) {
      _map.move(_centreQuartier!, 14);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _linkCtrl.dispose();
    super.dispose();
  }

  void _setPin(LatLng p, {bool move = false}) {
    setState(() {
      _pin = p;
      _msg = null;
    });
    widget.onChanged(p.latitude, p.longitude);
    if (move && _mapReady) _map.move(p, 16);
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.length < 3) return;
    setState(() {
      _searching = true;
      _results = const [];
      _msg = null;
    });
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?format=jsonv2&limit=5&countrycodes=sn'
        '&q=${Uri.encodeQueryComponent('$q, Dakar, Sénégal')}',
      );
      final r = await http.get(uri, headers: {'Accept': 'application/json'});
      if (r.statusCode != 200) {
        setState(() => _msg = 'Recherche indisponible — placez le pin à la main.');
        return;
      }
      final list = (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
      setState(() {
        _results = [
          for (final e in list)
            (
              label: (e['display_name'] ?? '').toString(),
              point: LatLng(
                double.parse(e['lat'].toString()),
                double.parse(e['lon'].toString()),
              ),
            ),
        ];
        if (_results.isEmpty) _msg = 'Aucun résultat — placez le pin à la main.';
      });
    } catch (_) {
      setState(() => _msg = 'Recherche indisponible — placez le pin à la main.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _applyLink() {
    final r = AnnonceForm.parseLatLng(_linkCtrl.text);
    if (r == null) {
      setState(() => _msg =
          'Lien non reconnu — collez un lien Maps contenant les coordonnées.');
    } else {
      _setPin(LatLng(r.$1, r.$2), move: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Recherche d'adresse
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(fontSize: 13.5),
                decoration: const InputDecoration(
                  hintText: 'Rechercher une adresse, un lieu…',
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: _searching ? null : _search,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.ink,
                side: const BorderSide(color: AppTheme.ink),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _searching
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Chercher'),
            ),
          ],
        ),
        if (_results.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.line),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                for (final res in _results)
                  ListTile(
                    dense: true,
                    title: Text(res.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5)),
                    leading: const Icon(Icons.place_outlined, size: 18),
                    onTap: () {
                      _searchCtrl.text = '';
                      setState(() => _results = const []);
                      _setPin(res.point, move: true);
                    },
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 280,
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: _pin ?? _centreQuartier ?? _dakar,
                initialZoom: _pin != null ? 16 : 13,
                onTap: (_, p) => _setPin(p),
                onMapReady: () => _mapReady = true,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.zappart.pro',
                ),
                if (_pin != null)
                  MarkerLayer(markers: [
                    Marker(
                      point: _pin!,
                      width: 44,
                      height: 44,
                      alignment: Alignment.topCenter,
                      child: const Icon(Icons.location_pin,
                          color: Color(0xFFE53935), size: 44),
                    ),
                  ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _pin == null
              ? 'Touchez la carte pour placer le bien, ou recherchez une adresse ci-dessus.'
              : 'Position : ${_pin!.latitude.toStringAsFixed(5)}, ${_pin!.longitude.toStringAsFixed(5)}  ·  touchez la carte pour ajuster.',
          style: TextStyle(
              fontSize: 12,
              color: _pin == null ? AppTheme.inkSoft : AppTheme.success),
        ),
        const SizedBox(height: 10),
        // Repli : coller un lien Google Maps
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _linkCtrl,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'Ou collez un lien Google Maps',
                  isDense: true,
                ),
                onSubmitted: (_) => _applyLink(),
              ),
            ),
            const SizedBox(width: 10),
            TextButton(onPressed: _applyLink, child: const Text('Placer')),
          ],
        ),
        if (_msg != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_msg!,
                style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
          ),
      ],
    );
  }
}
